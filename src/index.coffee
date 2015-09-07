_ = require 'lodash'
Promise = require 'when'

radius = 100

toRad = (deg) -> Math.PI * deg / 180
dist = (p1, p2) ->
  [lon1, lat1] = p1
  [lon2, lat2] = p2
  R = 3959 # miles; R(km):6371
  dLat = toRad lat2-lat1
  dLon = toRad lon2-lon1
  lat1 = toRad lat1
  lat2 = toRad lat2
  a = Math.sin(dLat/2) * Math.sin(dLat/2)
  a += Math.sin(dLon/2) * Math.sin(dLon/2) * Math.cos(lat1) * Math.cos(lat2)
  c = 2 * Math.atan2 Math.sqrt(a), Math.sqrt(1-a)
  d = R * c

module.exports = (System) ->
  Group = System.getModel 'Group'
  ActivityItem = System.getModel 'ActivityItem'

  cachedGroups = null
  getManagedGroups = ->
    return cachedGroups if cachedGroups?
    mpromise = Group
    .where
      '$or': [
        {'attributes.nearbyManaged': 'me'}
        {'attributes.nearbyManaged': 'city'}
      ]
    .find()
    cachedGroups = Promise mpromise

  getGroup = (id, populateIdentities = false) ->
    q = Group
    .where
      _id: id
    if populateIdentities == true
      q = q.populate 'identities'
    mpromise = q.findOne()
    Promise mpromise

  cachedLocation = null
  getLocation = ->
    return cachedLocation if cachedLocation
    cachedLocation = System.do 'me.location.last', {}

  getNearbyFriends = (location) ->
    where =
      'attributes.isFriend': true
      identity:
        '$ne': System.getMe()._id
      '$or': [
        {'location.0': {'$gt': 0}}
        {'location.0': {'$lt': 0}}
      ]
    mpromise = ActivityItem
    .where where
    .sort postedAt: -1
    .limit 100
    .find()
    Promise(mpromise).then (items) ->
      # console.log 'items', items?.length
      items = _.uniq items, false, (item) ->
        String item.identity?._id ? item.identity
      items = _.filter items, (item) ->
        radius > dist location, item.location
      # console.log 'items', items.length, items?[0]?.identity
      identities = _.pluck items, 'identity'
      identities

  updateGroup = (group, identities) ->
    group.identities = identities
    group.markModified 'identities'
    Promise group.save()
    .then -> group

  updateAllGroups = (location) ->
    getManagedGroups()
    .then (groups) ->
      Promise.all _.map groups, (group) ->
        promise = switch group.attributes.nearbyManaged
          when 'me'
            getNearbyFriends location
          when 'city'
            getNearbyFriends [
              group.attributes.city.lng
              group.attributes.city.lat
            ]
          else
            console.log 'nearbyManaged?', group.attributes
            throw new Error 'wat.'
        promise.then (identities) ->
          updateGroup group, identities

  removeFromGroup = (group, id) ->
    group.identities = _.filter group.identities, (identity) ->
      id != String identity
    group.markModified 'identities'
    Promise group.save()
    .then -> group

  setAttributes = (groupId, attributes) ->
    getGroup groupId
    .then (group) ->
      return unless group
      group.attributes = {} unless group.attributes
      for k, v of attributes
        group.attributes[k] = v
      group.markModified 'attributes'
      Promise group.save()
      .catch (err) ->
        cachedGroups = null
        getManagedGroups()
        throw err
      .then ->
        cachedGroups = null
        getManagedGroups()
        group
    .then (group) ->
      return unless group
      return getGroup groupId, true unless attributes.nearbyManaged
      promise = switch group.attributes.nearbyManaged
        when 'me'
          getLocation()
          .then (data) ->
            getNearbyFriends data.location
        when 'city'
          getNearbyFriends [
            group.attributes.city.lng
            group.attributes.city.lat
          ]
        else
          console.log 'nearbyManaged?', group.attributes
          throw new Error 'wat.'
      promise
      .then (identities) ->
        updateGroup group, identities
      .then ->
        # console.log 'populate identities'
        getGroup groupId, true

  me = (req, res, next) ->
    setAttributes req.params.groupId,
      nearbyManaged: 'me'
    .done (group) ->
      return next() unless group
      res.send group: group
    , (err) ->
      next err

  city = (req, res, next) ->
    return next() unless req.body?.city
    try
      city = JSON.parse req.body.city
    catch ex
      return next ex
    setAttributes req.params.groupId,
      nearbyManaged: 'city'
      city: city
    .done (group) ->
      return next() unless group
      res.send group: group
    , (err) ->
      next err

  disable = (req, res, next) ->
    setAttributes req.params.groupId,
      nearbyManaged: false
    .done (group) ->
      return next() unless group
      res.send group: group
    , (err) ->
      next err

  postSave = (item) ->
    return item unless item?.location?.length == 2
    return item unless item?.attributes?.isFriend
    identityId = item.identity?._id ? item.identity
    return item unless identityId
    identityId = String identityId
    me = System.getMe()
    # console.log 'postSave', identityId, me._id
    if identityId == String me._id
      cachedLocation = null
      return updateAllGroups(item.location).then -> item

    getLocation()
    .then (data) ->
      return unless data.location?.length == 2
      distance = dist data.location, item.location
      if distance < radius
        return addToGroups identityId
      getManagedGroups()
      .then (groups) ->
        Promise.all _.map groups, (group) ->
          found = _.find group.identities, (identity) ->
            identityId == String identity
          if found
            return removeFromGroup group, identityId
          null
    .then -> item

  routes:
    admin:
      '/admin/groups/:groupId/nearby/me': 'me'
      '/admin/groups/:groupId/nearby/city': 'city'
      '/admin/groups/:groupId/nearby/disable': 'disable'

  handlers:
    me: me
    city: city
    disable: disable

  globals:
    public:
      editGroupComponents:
        nearby: 'kerplunk-group-nearby:nearbyToggle'

  events:
    activityItem:
      save:
        post: postSave

  init: (next) ->
    getManagedGroups()
    next()
