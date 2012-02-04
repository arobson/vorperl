# author Alex Robson
# copyright appendTo, 2012
#
# license MIT
# Created February 2, 2012 by Alex Robson

spawnBunny = require('./rabbit').broker
sys = require 'util'
uuid = require 'uuid-lib'

Reservations = () ->
	self = this
	accumulator = 0
	declareExchange = (x) ->
		broker.exchange x.name, x.opts , onExchangeComplete

	declarePublishingExchanges = () ->
		exchanges= [
			{ name: nodeId, opts: {type: "direct", autoDelete: true}}, 
			{ name: "reservation", opts: {type: "fanout"}}
		]
		self.remaining = exchanges.length
		declareExchange(x) for x in exchanges

	declareReceivingQueues = () ->
		broker.queue(
			nodeId, 
			{ autoDelete: true }, 
			(q) -> 
				broker.bind nodeId, nodeId, ""
				broker.subscribe nodeId, onMessage
		)

	onExchangeComplete = () ->
		if (self.remaining -= 1) == 0 then declareReceivingQueues()
		console.log "#{self.remaining} exchanges left to declare"

	onMessage = (message, headers, deliveryInfo) ->
		if (callback = self.callbacks[headers.replyTo])
			callback message.result
		else
			console.log "Received a message that can't be processed."

	registerCallback = (id, callback) ->
		self.callbacks[id] = callback

	reservation = ( exchange, command, user, resourceId, onResponse) ->
		a = new Date()
		id = uuid.create().value
		registerCallback id, onResponse
		message =
			messageType: command
			userId: user
		broker.send exchange, "", message, 
			correlationId: resourceId
			replyTo: nodeId
			messageId: id
		accumulator += new Date() - a
		console.log "******* #{accumulator}"

	self.reserve = (resourceId, user, onResponse) ->
		reservation "reservation", "reserve", user, resourceId, onResponse

	self.release = (resourceId, user, onResponse) ->
		reservation "reservation", "release", user, resourceId, onResponse

	self.status = (resourceId, user, onResponse) ->
		reservation "reservation", "status", user, resourceId, onResponse

	self = this
	self.callbacks = {}
	broker = {}
	spawnBunny (x) ->
		broker = x
		declarePublishingExchanges()
	console.log "#{broker}"
	nodeId = 'api.' + uuid.create().value
	self

exports.reservations = new Reservations()