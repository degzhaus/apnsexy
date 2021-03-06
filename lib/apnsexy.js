// Generated by CoffeeScript 1.4.0
(function() {
  var Apnsexy, Debug, Feedback, Librato, Notification, key, value, _ref,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  _ref = require('./apnsexy/common');
  for (key in _ref) {
    value = _ref[key];
    eval("var " + key + " = value;");
  }

  Debug = require('./apnsexy/debug');

  Feedback = require('./apnsexy/feedback');

  Librato = require('./apnsexy/librato');

  Notification = require('./apnsexy/notification');

  Apnsexy = (function(_super) {

    __extends(Apnsexy, _super);

    function Apnsexy(options) {
      this.options = _.extend({
        ca: null,
        cert: null,
        debug: false,
        debug_ignore: [],
        gateway: 'gateway.push.apple.com',
        key: options.cert,
        librato: null,
        passphrase: null,
        port: 2195,
        secure_cert: true,
        timeout: 2000
      }, options);
      this.on('error', function() {});
      new Debug(this);
      if (this.options.librato) {
        this.options.librato.bindApnsexy(this);
      }
      this.resetVars();
      this.keepSending();
    }

    Apnsexy.prototype.checkForStaleConnection = function() {
      var potential_drops, total_errors, total_notifications, total_sent;
      this.debug('checkForStaleConnection#start');
      this.stale_count || (this.stale_count = 0);
      if ((!(this.stale_index != null) && (this.sent_index != null)) || this.stale_index < this.sent_index) {
        this.stale_index = this.sent_index;
        this.stale_count = 0;
      }
      if (this.stale_index === this.sent_index) {
        this.stale_count++;
      }
      if (this.stale_count >= 2) {
        clearInterval(this.stale_connection_timer);
        this.potential_drops += this.notifications.length - (this.sent_index + 1);
        if (this.last_error_index > this.connect_index && this.sent_index >= this.last_error_index) {
          this.sent += this.sent_index - this.last_error_index;
        } else if (this.sent_index >= this.connect_index) {
          this.sent += this.sent_index - this.connect_index;
        }
        this.debug('checkForStaleConnection#@potential_drops', this.potential_drops);
        this.debug('checkForStaleConnection#@sent', this.sent);
        potential_drops = this.potential_drops;
        total_errors = this.errors;
        total_notifications = this.notifications.length;
        total_sent = this.sent;
        this.killSocket();
        this.resetVars();
        this.debug('checkForStaleConnection#stale');
        return this.emit('finish', {
          potential_drops: potential_drops,
          total_errors: total_errors,
          total_notifications: total_notifications,
          total_sent: total_sent
        });
      }
    };

    Apnsexy.prototype.connect = function() {
      var _this = this;
      this.debug('connect#start');
      if (!(this.connecting != null) && (!(this.socket != null) || !this.socket.writable)) {
        delete this.connect_promise;
        delete this.sent_index;
        this.connect_index = this.index - 1;
        if (this.connect_index < -1) {
          this.connect_index = -1;
        }
      }
      return this.connect_promise || (this.connect_promise = defer(function(resolve, reject) {
        var socket_options;
        if ((_this.socket != null) && _this.socket.writable) {
          _this.debug('connect#exists');
          return resolve();
        } else {
          _this.debug('connect#connecting');
          _this.resetVars({
            connecting: true
          });
          _this.connecting = true;
          socket_options = {
            ca: _this.options.ca,
            cert: fs.readFileSync(_this.options.cert),
            key: fs.readFileSync(_this.options.key),
            passphrase: _this.options.passphrase,
            rejectUnauthorized: _this.options.secure_cert,
            socket: new net.Stream()
          };
          return setTimeout(function() {
            _this.socket = tls.connect(_this.options.port, _this.options.gateway, socket_options, function() {
              _this.debug("connect#connected");
              _this.connecting = false;
              return resolve();
            });
            _this.socket.on("close", function() {
              return _this.socketError();
            });
            _this.socket.on("data", function(data) {
              return _this.socketData(data);
            });
            _this.socket.on("error", function(e) {
              return _this.socketError(e);
            });
            _this.socket.setNoDelay(false);
            return _this.socket.socket.connect(_this.options.port, _this.options.gateway);
          }, 10);
        }
      }));
    };

    Apnsexy.prototype.enqueue = function(notification) {
      var _this = this;
      this.debug("enqueue", notification);
      if (this.uid > 0xffffffff) {
        this.uid = 0;
      }
      notification._uid = this.uid++;
      this.notifications.push(notification);
      return this.stale_connection_timer || (this.stale_connection_timer = setInterval(function() {
        return _this.checkForStaleConnection();
      }, this.options.timeout));
    };

    Apnsexy.prototype.keepSending = function() {
      var _this = this;
      return process.nextTick(function() {
        _this.debug("keepSending");
        if (_this.error_index != null) {
          _this.index = _this.error_index;
          delete _this.error_index;
        }
        if (_this.index < _this.notifications.length - 1) {
          _this.send();
        }
        return _this.keepSending();
      });
    };

    Apnsexy.prototype.killSocket = function() {
      delete this.connecting;
      if (this.socket != null) {
        this.socket.removeAllListeners();
        return this.socket.writable = false;
      }
    };

    Apnsexy.prototype.resetVars = function(options) {
      if (options == null) {
        options = {};
      }
      if (options.connecting == null) {
        delete this.connecting;
        delete this.error_index;
        delete this.last_error_index;
        delete this.stale_connection_timer;
        this.errors = 0;
        this.index = -1;
        this.potential_drops = 0;
        this.notifications = [];
        this.sent_index = -1;
        this.sent = 0;
        this.uid = 0;
      }
      delete this.stale_count;
      return delete this.stale_index;
    };

    Apnsexy.prototype.send = function() {
      var index, notification,
        _this = this;
      this.debug('send#@index', this.index + 1);
      notification = this.notifications[this.index + 1];
      if (notification) {
        this.debug("send#start", notification);
        this.index++;
        index = this.index;
        return this.connect().then(function() {
          if (_this.socket.writable) {
            _this.debug("send#write", notification);
            return _this.socket.write(notification.data(), notification.encoding, function() {
              _this.sent_index = index;
              _this.debug("send#written", notification);
              return _this.emit("sent", notification);
            });
          }
        });
      }
    };

    Apnsexy.prototype.socketData = function(data) {
      var error_code, identifier, notification,
        _this = this;
      error_code = data[0];
      identifier = data.readUInt32BE(2);
      this.debug('socketData#start', {
        error_code: error_code,
        identifier: identifier
      });
      delete this.error_index;
      _.each(this.notifications, function(item, i) {
        if (item._uid === identifier) {
          return _this.error_index = i;
        }
      });
      if (this.error_index != null) {
        this.debug('socketData#@error_index', this.error_index);
        notification = this.notifications[this.error_index];
        this.last_error_index = this.error_index;
        this.sent += (this.error_index - 1) - this.connect_index;
        this.debug('socketData#found_notification', identifier, notification);
        if (error_code === 8) {
          this.errors++;
          this.emit('error', notification);
        }
        return this.killSocket();
      }
    };

    Apnsexy.prototype.socketError = function(e) {
      this.debug('socketError#start', e);
      if (this.error_index == null) {
        this.error_index = this.sent_index;
        this.debug('socketError#@error_index', this.error_index);
        this.potential_drops += this.error_index - this.connect_index;
        this.connect_index = this.error_index;
        this.debug('socketError#@connect_index', this.connect_index);
        this.debug('socketError#@potential_drops', this.potential_drops);
      }
      return this.killSocket();
    };

    return Apnsexy;

  })(EventEmitter);

  module.exports = {
    Apnsexy: Apnsexy,
    Feedback: Feedback,
    Librato: Librato,
    Notification: Notification
  };

}).call(this);
