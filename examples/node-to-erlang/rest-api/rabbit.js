(function() {
  var Rabbit, amqp;

  amqp = require('amqp');

  Rabbit = (function() {

    function Rabbit(server, onReady) {
      var self;
      this.server = server;
      this.defaultExchangeOptions = {
        type: "fanout",
        autoDelete: true
      };
      this.exchanges = {};
      this.queues = {};
      this.defaultQueueOptions = {
        autoDelete: true
      };
      console.log("Creating connection...");
      this.connection = amqp.createConnection({
        host: this.server,
        port: 5672
      });
      self = this;
      this.connection.on("ready", function() {
        console.log("Connection is ready");
        return onReady(self);
      });
    }

    Rabbit.prototype.bind = function(exchange, queue, key) {
      var x;
      key = key ? key : "";
      console.log("Binding " + queue + " to " + exchange + " with topic " + key);
      x = this.exchanges[exchange];
      return this.queues[queue].bind(x, key);
    };

    Rabbit.prototype.exchange = function(exchange, exchangeOpts, callback) {
      var self;
      console.log("Creating " + exchange);
      self = this;
      return this.connection.exchange(exchange, exchangeOpts, function(x) {
        self.exchanges[exchange] = x;
        return callback(x);
      });
    };

    Rabbit.prototype.queue = function(queue, queueOpts, callback) {
      var self;
      console.log("Creating " + queue);
      self = this;
      return this.connection.queue(queue, queueOpts, function(q) {
        self.queues[queue] = q;
        return callback(q);
      });
    };

    Rabbit.prototype.send = function(exchange, key, message, messageOpts) {
      var x;
      x = this.exchanges[exchange];
      key = key ? key : "";
      messageOpts.contentType = "application/json";
      return x.publish(key, message, messageOpts);
    };

    Rabbit.prototype.subscribe = function(queue, handler) {
      return this.queues[queue].subscribe(handler);
    };

    return Rabbit;

  })();

  exports.broker = function(callback) {
    return new Rabbit("localhost", callback);
  };

}).call(this);
