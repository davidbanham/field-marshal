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
    webserver.listen 7000, ->
      done()
  after (done) ->
    server.removeAllListeners "request"
    server.close()
    webserver.close ->
      done()
  it 'should accept a git push', (done) ->
    rand = Math.floor(Math.random() * (1 << 24)).toString(16)
    push = spawn 'git', ['push', '-u', "http://test:testingpass@localhost:7000/#{rand}", 'master']
    push.stderr.on 'data', (buf) ->
      #console.log "stderr", buf.toString()
    push.stdout.on 'data', (buf) ->
      #console.log 'stdout', buf.toString()
    gitter.repos.once 'push', () ->
      setTimeout ->
        assert fs.existsSync "./repos/#{rand}.git"
        push.kill()
        rimraf "./repos/#{rand}.git", ->
          done()
      , 500
  it 'should tell all drones to fetch', (done) ->
    rand = Math.floor(Math.random() * (1 << 24)).toString(16)
    model.slaves['fetchtest'] =
      ip: '127.0.0.1'
    server.once "request", (req, res) ->
      req.once "data", (buf) ->
        parsed = JSON.parse buf.toString()
        assert.equal parsed.name, rand
        assert.equal parsed.url, "http://git:testingpass@localhost:4001/#{rand}"
        res.end()
        setTimeout ->
          rimraf "./repos/#{rand}.git", ->
            done()
        , 1000
    push = spawn 'git', ['push', "http://test:testingpass@localhost:7000/#{rand}", 'master']
