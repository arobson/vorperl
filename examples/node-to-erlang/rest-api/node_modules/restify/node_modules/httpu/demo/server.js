// Copyright 2011 Mark Cavage <mcavage@gmail.com> All rights reserved.
var http = require('http');

var sPath = '/tmp/httpu-sock';

var server = http.createServer(function(req, res) {
  res.writeHead(200, {'Content-Type': 'text/plain'});
  res.end('Hello Unix Domain Socket Client!\n');
}).listen(sPath);

console.log('listening on ' + sPath);
