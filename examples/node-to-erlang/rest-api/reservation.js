(function() {
  var init, reservations;

  reservations = require('./topology').reservations;

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
      return reservations.reserve(resourceId, 'sys', function(result) {
        return res.send(responseLookup[result], {
          message: result
        });
      });
    };
    release = function(req, res) {
      var resourceId;
      resourceId = req.uriParams.id;
      return reservations.release(resourceId, 'sys', function(result) {
        return res.send(responseLookup[result], {
          message: result
        });
      });
    };
    status = function(req, res) {
      var resourceId;
      resourceId = req.uriParams.id;
      return reservations.status(resourceId, 'sys', function(result) {
        return res.send(responseLookup[result], {
          message: result
        });
      });
    };
    server.get('/reservation/:id', pre, status, post);
    server.put('/reservation/:id', pre, create, post);
    return server.del('/reservation/:id', pre, release, post);
  };

  exports.init = init;

}).call(this);
