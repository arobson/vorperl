# author Alex Robson
# copyright appendTo, 2012
#
# license MIT
# Created February 2, 2012 by Alex Robson

spawn = require('./rabbit').broker
uuid = require 'uuid-lib'

broker = {}

start = (x) ->
	broker = x
	broker.exchange "ex1", { autoDelete: true }, () -> send()


send = () ->
	Times = [0...2000]

	f = () -> broker.send(
		"ex1", 
		"",
		{message: "Hi"}, 
		{contentType: "application/json" }
	)

	A = new Date()
	
	f() for x in Times

	B = new Date()
	console.log "#{B - A}"


spawn start