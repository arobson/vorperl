# author Alex Robson
# copyright appendTo, 2012
#
# license MIT
# Created February 2, 2012 by Alex Robson

reservation = require './reservation'

restify = require 'restify'
server = restify.createServer()

reservation.init server, [], []

server.listen(9000)