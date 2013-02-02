for key, value of require('./apnshit/common')
  eval("var #{key} = value;")

Debug        = require './apnshit/debug'
Feedback     = require './apnshit/feedback'
Notification = require './apnshit/notification'

class Apnshit extends EventEmitter
  
  constructor: (options) ->

    @options = _.extend(
      ca          : null
      cert        : 'cert.pem'
      debug       : false
      debug_ignore: []
      gateway     : 'gateway.push.apple.com'
      key         : 'key.pem'
      passphrase  : null
      port        : 2195
      secure_cert : true
      timeout     : 2000
      
      options
    )

    # EventEmitter requires something bound to error event
    @on('error', ->)

    new Debug(@)  if @options.debug

    @resetVars()
    @keepSending()

  checkForStaleConnection: ->
    @debug('checkForStaleConnection#start')

    @stale_index ||= @sent_index
    @stale_count ||= 0

    @stale_count++  if @stale_index == @sent_index

    if @stale_count >= 2
      clearInterval(@stale_connection_timer)
      @resetVars()
      
      @debug('checkForStaleConnection#stale')
      @emit('finish')

  connect: ->
    @debug('connect#start')

    unless @socket && @socket.writable
      delete @connect_promise

    @connect_promise ||= defer (resolve, reject) =>
      if @socket && @socket.writable
        @debug('connect#exists')
        resolve()
      else
        @debug('connect#connecting')
        @resetVars(connecting: true)
        
        socket_options =
          ca                : @options.ca
          cert              : fs.readFileSync(@options.cert)
          key               : fs.readFileSync(@options.key)
          passphrase        : @options.passphrase
          rejectUnauthorized: @options.secure_cert
          socket            : new net.Stream()
    
        setTimeout(
          =>
            @socket = tls.connect(
              @options.port
              @options.gateway
              socket_options
              =>
                @debug("connect#connected")
                resolve()
            )

            @socket.on "close",        => @socketError()
            @socket.on "data" , (data) => @socketData(data)
            @socket.on "error", (e)    => @socketError(e)

            @socket.setNoDelay(false)
            @socket.socket.connect(
              @options.port
              @options.gateway
            )
          100
        )

  killSocket: ->
    @socket.removeAllListeners()
    @socket.writable = false

  enqueue: (notification) ->
    @debug("enqueue", notification)

    @uid = 0  if @uid > 0xffffffff
    notification._uid = @uid++
    
    @notifications.push(notification)

    @stale_connection_timer ||= setInterval(
      => @checkForStaleConnection()
      @options.timeout
    )

  keepSending: ->
    process.nextTick(
      =>
        @debug("keepSending")
        
        if @error_index?
          @index = @error_index + 1
          delete @error_index

        if !@sending && @index != @notifications.length
          @send()
        
        @keepSending()
    )

  resetVars: (options = {})->
    unless options.connecting?
      delete @error_index
      delete @stale_connection_timer

      @index         = 0
      @notifications = []
      @sent_index    = 0
      @uid           = 0

    delete @stale_count
    delete @stale_index

  send: ->
    notification = @notifications[@index]

    if notification
      @debug('send#@index', @index)

      index    = @index
      @sending = true

      @index++

      @debug("send#start", notification)
      
      @connect().then(
        =>
          @debug("send#write", notification)
          
          if @socket.writable
            @socket.write(
              notification.data()
              notification.encoding
              =>
                @debug("send#written", notification)

                @sending    = false
                @sent_index = index
            )
          else
            @sending = false
      )

  socketData: (data) ->
    error_code = data[0]
    identifier = data.readUInt32BE(2)

    @debug(
      'socketData#start'
      error_code: error_code
      identifier: identifier
    )

    delete @error_index

    _.each @notifications, (item, i) =>
      if item._uid == identifier
        @error_index = i
    
    if @error_index?
      @debug('socketData#@error_index', @error_index)
      notification = @notifications[@error_index]
      
      @debug('socketData#found_notification', notification)
      @emit('error', notification)  if error_code == 8

      @killSocket()

  socketError: (e) ->
    @debug('socketError#start', e)

    @error_index = @sent_index + 1  unless @error_index?
    @debug('socketError#@error_index', @error_index)

    @killSocket()

module.exports = 
  Apnshit     : Apnshit
  Feedback    : Feedback
  Notification: Notification