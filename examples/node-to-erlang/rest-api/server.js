profiler = require('v8-profiler');
var dummy, profiler, reservation, restify, server;

reservation = require('./reservation');

dummy = require('./dummy-reservation');



restify = require('restify');

server = restify.createServer();

reservation.init(server, [], []);

dummy.init(server, [], []);

profiler.startProfiling('restify');

server.listen(9090);

setTimeout( function() { 
      profiler.stopProfiling('restify');
      console.log("stopping");
    }, 10000);