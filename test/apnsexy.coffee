for key, value of require('../lib/apnsexy/common')
  eval("var #{key} = value;")

for key, value of require('./helpers')
  eval("var #{key} = value;")

apnsexy = require('../lib/apnsexy')
fs      = require('fs')
_       = require('underscore')

Apnsexy = apnsexy.Apnsexy
Librato = apnsexy.Librato

apns              = null
bad               = []
config            = null
device_id         = null
drops             = 0
errors            = []
expected_drops    = 0
expected_errors   = 0
expected_finishes = 0
finishes          = 0
good              = []
librato           = null
notifications     = []
sample            = process.env.SAMPLE || 6
sample            = parseInt(sample)

if sample < 6
  console.log "SAMPLE must be greater than 5"
  process.exit()

describe 'Apnsexy', ->

  before ->
    config  = fs.readFileSync("#{__dirname}/config.json")
    config  = JSON.parse(config)
    librato = new Librato(config.librato)

    apns = new Apnsexy(
      cert          : config.cert
      debug         : true
      debug_ignore  : [
        'enqueue'
        #'connect#connecting'
        #'connect#connected'
        'connect#start'
        'connect#exists'
        'send#start'
        'keepSending'
        'send#write'
        'send#written'
        'socketData#start'
      ]
      key    : config.key
      gateway: "gateway.sandbox.push.apple.com"
      librato: librato
    )

    apns.on 'debug', console.log

    apns.on 'error', (n) =>
      errors.push(n)

    apns.on 'finish', (counts) =>
      drops += counts.potential_drops
      finishes += 1

      console.log "sent", counts.total_sent
      console.log "drop count", counts.potential_drops
      console.log "drops", drops
      console.log "expected drops", expected_drops
      console.log "finishes", finishes
      console.log "expected finishes", expected_finishes
      console.log "errors.length", errors.length
      console.log "expected errors", expected_errors

      drops.should.equal(expected_drops)
      errors.length.should.equal(expected_errors)
      finishes.should.equal(expected_finishes)

  if process.env.GOOD
    describe '#connect()', ->
      it 'should connect', (done) ->
        apns.connect().then(=> done())

    describe '#enqueue()', ->
      it 'should send a notification', (done) ->
        expected_finishes += 1

        n = notification()
        
        apns.once 'finish', => done()
        apns.enqueue(n)
        
        notifications.push(n)

  describe '#enqueue()', ->
    if process.env.BAD
      it 'should recover from failure (mostly bad)', (done) ->
        expected_finishes += 1
        apns.once 'finish', => done()
        send('mostly bad')

      it 'should recover from failure (all bad)', (done) ->
        expected_finishes += 1
        apns.once 'finish', => done()
        send('all bad')

      it "should recover from socket error mid-way through", (done) ->
        error_at           = Math.floor(sample / 2) - 1
        expected_drops    += error_at + 1
        expected_finishes += 1
        writes             = 0

        # The drops will not trigger an error event as normally expected.
        # We need to decrement those drops from the expected errors variable.
        expected_errors -= error_at

        apns.on 'sent', =>
          if writes == error_at
            apns.socket.destroy()
          writes++

        apns.once 'finish', => done()
        send('mostly bad')

      it "should recover from socket error mid-way through (twice)", (done) ->
        error_at           = Math.floor(sample / 2) - 1
        expected_drops    += error_at * 2
        expected_errors   -= error_at * 2 - 1
        expected_finishes += 1
        writes             = 0

        apns.on 'sent', =>
          if writes == error_at || writes == error_at * 2 - 1
            apns.socket.destroy()
          writes++

        apns.once 'finish', => done()
        send('mostly bad')

      it 'should timeout on failed connection', (done) ->
        expected_drops    += sample
        expected_errors   -= sample
        expected_finishes += 1

        # Stub out connection so it never connects
        apns.connecting = true
        apns.connect_promise = defer (resolve, reject) -> resolve()

        apns.once 'finish', => done()
        send('all bad')

    if process.env.GOOD
      it 'should recover from error (mostly good)', (done) ->
        expected_finishes += 1
        apns.once 'finish', => done()
        send('mostly good')

      it 'should send multiple (all good)', (done) ->
        expected_finishes += 1
        apns.once 'finish', => done()
        send('all good')

  describe 'verify notifications', ->
    it 'should have sent these notifications', (done) ->
      console.log('')

      notifications = _.map notifications, (n) =>
        n.alert.replace(/\D+/g, '')

      errors = _.map errors, (n) =>
        n.alert.replace(/\D+/g, '')

      console.log("\nsample size: #{sample}")
      console.log("\ndrops: #{drops}")
      console.log("\n#{errors.length} errors / #{expected_errors} expected")
      console.log("\n#{notifications.length} notifications:")
      console.log("\n#{notifications.join("\n")}")

      librato.on('finish', => done())

send = (type) ->
  for i in [0..sample-1]
    if type == 'all good'
      is_good = true
    else if type == 'all bad'
      is_good = false
    else if type == 'mostly good'
      is_good = i != 1 && i != sample - 2
    else if type == 'mostly bad'
      is_good = i == 1 || i == sample - 2

    n = notification(i, !is_good)

    if is_good
      good.push(n)
      notifications.push(n)
    else
      expected_errors += 1
      bad.push(n)

    apns.enqueue(n)