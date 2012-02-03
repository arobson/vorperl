# author Alex Robson
# copyright appendTo, 2012
#
# license MIT
# Created February 2, 2012 by Alex Robson

amqp = require 'amqp'

class Rabbit

	constructor: (@server, onReady) ->
		@defaultExchangeOptions = 
			type: "fanout"
			autoDelete: true

		@exchanges = {}
		@queues = {}

		@defaultQueueOptions = 
			autoDelete: true

		console.log "Creating connection..."
		@connection = amqp.createConnection 
						host: @server,
						port: 5672
		self = @
		@connection.on "ready", () -> 
			console.log "Connection is ready"
			onReady(self)

	bind: (exchange, queue, key) ->
		key = if key then key else ""
		console.log "Binding #{queue} to #{exchange} with topic #{key}"
		x = @exchanges[exchange]
		@queues[queue].bind( x, key )

	exchange: (exchange, exchangeOpts, callback) ->
		console.log "Creating #{exchange}"
		self = @
		@connection.exchange exchange, exchangeOpts,
			(x) -> 
				self.exchanges[exchange] = x
				callback(x)

	queue: (queue, queueOpts, callback) ->
		console.log "Creating #{queue}"
		self = @
		@connection.queue queue, queueOpts,
			(q) -> 
				self.queues[queue] = q
				callback(q)

	send: (exchange, key, message, messageOpts) ->
		x = @exchanges[exchange]
		key = if key then key else ""
		messageOpts.contentType ="application/json"
		console.log "Publishing #{message} to #{exchange} on channel #{x} with options #{messageOpts}"
		x.publish key, message, messageOpts

	subscribe: (queue, handler) ->
		 @queues[queue].subscribe handler

exports.broker = (callback) -> new Rabbit( "localhost", callback )