(function() {
  var Reservations, spawnBunny, sys, uuid;

  spawnBunny = require('./rabbit').broker;

  sys = require('util');

  uuid = require('uuid-lib');

  Reservations = function() {
    var accumulator, broker, declareExchange, declarePublishingExchanges, declareReceivingQueues, nodeId, onExchangeComplete, onMessage, registerCallback, reservation, self;
    self = this;
    accumulator = 0;
    declareExchange = function(x) {
      return broker.exchange(x.name, x.opts, onExchangeComplete);
    };
    declarePublishingExchanges = function() {
      var exchanges, x, _i, _len, _results;
      exchanges = [
        {
          name: nodeId,
          opts: {
            type: "direct",
            autoDelete: true
          }
        }, {
          name: "reservation",
          opts: {
            type: "fanout"
          }
        }
      ];
      self.remaining = exchanges.length;
      _results = [];
      for (_i = 0, _len = exchanges.length; _i < _len; _i++) {
        x = exchanges[_i];
        _results.push(declareExchange(x));
      }
      return _results;
    };
    declareReceivingQueues = function() {
      return broker.queue(nodeId, {
        autoDelete: true
      }, function(q) {
        broker.bind(nodeId, nodeId, "");
        return broker.subscribe(nodeId, onMessage);
      });
    };
    onExchangeComplete = function() {
      if ((self.remaining -= 1) === 0) declareReceivingQueues();
      return console.log("" + self.remaining + " exchanges left to declare");
    };
    onMessage = function(message, headers, deliveryInfo) {
      var callback;
      if ((callback = self.callbacks[headers.replyTo])) {
        return callback(message.result);
      } else {
        return console.log("Received a message that can't be processed.");
      }
    };
    registerCallback = function(id, callback) {
      return self.callbacks[id] = callback;
    };
    reservation = function(exchange, command, user, resourceId, onResponse) {
      var id, message;
      id = uuid.create().value;
      registerCallback(id, onResponse);
      message = {
        messageType: command,
        userId: user
      };
      return broker.send(exchange, "", message, {
        correlationId: resourceId,
        replyTo: nodeId,
        messageId: id
      });
    };
    self.reserve = function(resourceId, user, onResponse) {
      return reservation("reservation", "reserve", user, resourceId, onResponse);
    };
    self.release = function(resourceId, user, onResponse) {
      return reservation("reservation", "release", user, resourceId, onResponse);
    };
    self.status = function(resourceId, user, onResponse) {
      return reservation("reservation", "status", user, resourceId, onResponse);
    };
    self = this;
    self.callbacks = {};
    broker = {};
    spawnBunny(function(x) {
      broker = x;
      return declarePublishingExchanges();
    });
    console.log("" + broker);
    nodeId = 'api.' + uuid.create().value;
    return self;
  };

  exports.reservations = new Reservations();

}).call(this);
