(function() {
  var broker, send, spawn, start, uuid;

  spawn = require('./rabbit').broker;

  uuid = require('uuid-lib');

  broker = {};

  start = function(x) {
    broker = x;
    return broker.exchange("ex1", {
      autoDelete: true
    }, function() {
      return send();
    });
  };

  send = function() {
    var A, B, Times, f, x, _i, _j, _len, _results;
    Times = (function() {
      _results = [];
      for (_i = 0; _i < 2000; _i++){ _results.push(_i); }
      return _results;
    }).apply(this);
    f = function() {
      return broker.send("ex1", "", {
        message: "Hi"
      }, {
        contentType: "application/json"
      });
    };
    A = new Date();
    for (_j = 0, _len = Times.length; _j < _len; _j++) {
      x = Times[_j];
      f();
    }
    B = new Date();
    return console.log("" + (B - A));
  };

  spawn(start);

}).call(this);
