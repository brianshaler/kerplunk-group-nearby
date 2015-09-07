_ = require 'lodash'
React = require 'react'

{DOM} = React

module.exports = React.createFactory React.createClass
  getInitialState: ->
    attr = @props.group.attributes
    managedValue = if attr?.nearbyManaged
      attr?.nearbyManaged
    else
      'disable'

    previousValue: managedValue
    nearbyManaged: managedValue
    previousCity: attr?.city ? {}
    city: attr?.city ? {}

  updateManaged: (e) ->
    @setState
      nearbyManaged: e.target.value

  save: (e) ->
    e.preventDefault()
    url = "/admin/groups/#{@props.group._id}/nearby/#{@state.nearbyManaged}.json"
    opt =
      city: (JSON.stringify @state.city unless @state.nearbyManaged != 'city')
    @props.request.post url, opt, (err, data) =>
      console.log err?.stack ? err if err
      console.log 'result', @state.nearbyManaged, data
      if data.group?.identities
        @props.onUpdate
          group: data.group
          identities: data.group.identities
    @setState
      previousValue: @state.nearbyManaged
      previousCity: @state.city

  onCitySelect: (city) ->
    console.log 'onCitySelect', arguments
    @setState
      city: city

  render: ->
    cityInputPath = 'kerplunk-city-autocomplete:input'
    CityInputComponent = @props.getComponent cityInputPath
    saveable = true
    unless @state.previousValue != @state.nearbyManaged
      saveable = false
    if @state.nearbyManaged == 'city'
      if !@state.city?.name
        saveable = false
      else if @state.previousCity?.name != @state.city?.name
        saveable = true

    DOM.div null,
      'nearby..'
      DOM.select
        onChange: @updateManaged
        value: @state.nearbyManaged
      ,
        DOM.option
          value: 'disable'
        , 'not managed'
        DOM.option
          value: 'me'
        , 'my current location'
        DOM.option
          value: 'city'
        , 'near city..'
      if @state.nearbyManaged == 'city'
        DOM.div null,
          'city'
          CityInputComponent _.extend {}, @props,
            onSelect: @onCitySelect
            city: @state.city
      else
        null
      if saveable
        DOM.a
          href: '#'
          onClick: @save
          className: 'btn btn-success'
        ,
          'save '
          @state.previousValue
          ' => '
          @state.nearbyManaged
