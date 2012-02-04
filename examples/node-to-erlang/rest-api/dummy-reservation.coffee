# author Alex Robson
# copyright appendTo, 2012
#
# license MIT
# Created February 2, 2012 by Alex Robson

init = (server, pre, post) ->

	responseLookup = 
		"reservation_created": 200
		"ignored": 304
		"already_reserved": 403
		"unavailable": 403
		"available": 200
		"reserved": 200

	create = (req, res) ->
		resourceId = req.uriParams.id
		#reservations.reserve resourceId, 'sys', (result) ->
		res.send( 200, {message: "dummy"} )

	release = (req, res) ->
		resourceId = req.uriParams.id
		#reservations.release resourceId, 'sys', (result) ->
		res.send( 200, {message: "dummy"} )
		
	status = (req, res) ->
		resourceId = req.uriParams.id
		#reservations.status resourceId, 'sys', (result) ->
		res.send( 200, {message: "dummy"} )

	server.get '/dummy/:id', pre, status, post
	server.put '/dummy/:id', pre, create, post
	server.del '/dummy/:id', pre, release, post

exports.init = init