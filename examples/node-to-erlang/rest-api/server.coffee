# author Alex Robson
# copyright appendTo, 2012
#
# license MIT
# Created February 2, 2012 by Alex Robson

reservation = require './reservation'
dummy = require './dummy-reservation'
#profiler = require 'profiler'

restify = require 'restify'
server = restify.createServer()

reservation.init server, [], []
dummy.init server, [], []

server.listen(9090)
