(function() {
  var init;

  init = function(server, pre, post) {
    var create, release, responseLookup, status;
    responseLookup = {
      "reservation_created": 200,
      "ignored": 304,
      "already_reserved": 403,
      "unavailable": 403,
      "available": 200,
      "reserved": 200
    };
    create = function(req, res) {
      var resourceId;
      resourceId = req.uriParams.id;
      return res.send(200, {
        message: "dummy"
      });
    };
    release = function(req, res) {
      var resourceId;
      resourceId = req.uriParams.id;
      return res.send(200, {
        message: "dummy"
      });
    };
    status = function(req, res) {
      var resourceId;
      resourceId = req.uriParams.id;
      return res.send(200, {
        message: "dummy"
      });
    };
    server.get('/dummy/:id', pre, status, post);
    server.put('/dummy/:id', pre, create, post);
    return server.del('/dummy/:id', pre, release, post);
  };

  exports.init = init;

}).call(this);
