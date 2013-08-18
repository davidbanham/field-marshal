process.env.HOSTNAME = "localhost"
assert = require 'assert'
http = require 'http'
spawn = require('child_process').spawn
webserver = require '../lib/webserver'
gitter = require '../lib/gitter'
model = require '../lib/model'
rimraf = require 'rimraf'
fs = require 'fs'
server = http.createServer()

describe "gitter", ->
  before (done) ->
    server.listen 3000
    webserver.timeout = 100 # Time out connections faster so we can clean up the server. This is an annoying race condition.
    webserver.listen 7000, ->
      done()
  after (done) ->
    server.removeAllListeners "request"
    server.close()
    webserver.timeout = 120000 #default
    webserver.close ->
      done()
  it 'should accept a git push', (done) ->
    push = spawn 'git', ['push', 'http://test:testingpass@localhost:7000/beep', 'master']
    push.stderr.on 'data', (buf) ->
      #console.log "stderr", buf.toString()
    push.stdout.on 'data', (buf) ->
      #console.log 'stdout', buf.toString()
    gitter.repos.once 'push', () ->
      setTimeout ->
        assert fs.existsSync './repos/beep.git'
        push.kill()
        rimraf './repos/beep', ->
          done()
      , 500
  it 'should tell all drones to fetch', (done) ->
    model.slaves['fetchtest'] =
      ip: '127.0.0.1'
    server.once "request", (req, res) ->
      req.once "data", (buf) ->
        assert.deepEqual JSON.parse(buf.toString()),
          name: 'beep'
          url: 'http://git:testingpass@localhost:4001/beep'
        res.end()
        done()
    push = spawn 'git', ['push', 'http://test:testingpass@localhost:7000/beep', 'master']
