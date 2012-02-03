THIS PROJECT HAS BEEN MERGED INTO NODE.JS CORE.  YOU PROBABLY DON'T WANT
THIS ANYMORE.  It's in the 0.5 branch, so only use this as a short-term
dependency if you're using the 0.4.x branch and really need this.


node-httpu is a very small library that enables you to make http client requests
over a Unix Domain Socket.  Arguably, this code should be in node core, but for
the time being, it's not.

## Usage

The library is very simple, and small, and only exposes you the ability to
create a new fd socket that can be used with the existing node net API:

    var httpu = require('httpu');

    var options = {
      socketPath: '/tmp/httpu-sock',
      path: '/index.html'
    };

    var req = httpu.get(options, function(res) {
      console.log('STATUS: ' + res.statusCode);
      console.log('HEADERS: ' + JSON.stringify(res.headers));
      res.setEncoding('utf8');
      res.on('data', function (chunk) {
        console.log('BODY: ' + chunk);
      });
    }).on('error', function(e) {
      console.log("Got error: " + e.message);
    });

This is just a direct overlay on top of the HTTP binding, except you can specify
a `socketPath` as opposed to `host:port`.

## Installation

    npm install httpu

## License

MIT.

## Bugs

See <https://github.com/mcavage/node-httpu/issues>.
