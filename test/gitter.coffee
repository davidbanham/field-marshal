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
  this.timeout 30000
  if process.env.TRAVIS
    this.timeout 120000
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
    push = spawn 'git', ['push', "http://test:testingpass@localhost:7000/#{rand}", 'master']
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
  it 'should update the latest commit in the model', (done) ->
    rand = Math.floor(Math.random() * (1 << 24)).toString(16)
    push = spawn 'git', ['push', "http://test:testingpass@localhost:7000/#{rand}", 'master']
    shaChecker = spawn 'git', ['log', 'master', '-n', '1']
    shaChecker.stdout.on 'data', (buf) ->
      targetSha = buf.toString().split('\n')[0].split(' ')[1]
      push.on 'close', ->
        model.latestCommits.get rand, (err, sha) ->
          assert.equal sha, targetSha
          done()
  it 'should update the previous commit in the model', (done) ->
    rand = Math.floor(Math.random() * (1 << 24)).toString(16)
    model.manifest = {}
    model.manifest[rand] =
      opts:
        commit: 'totallyold'
    push = spawn 'git', ['push', "http://test:testingpass@localhost:7000/#{rand}", 'master']
    shaChecker = spawn 'git', ['log', 'master', '-n', '1']
    shaChecker.stdout.on 'data', (buf) ->
      targetSha = buf.toString().split('\n')[0].split(' ')[1]
      push.on 'close', ->
        model.prevCommits.get rand, (err, prevCommit) ->
          assert.deepEqual err, null
          assert.equal prevCommit, 'totallyold'
          model.latestCommits.get rand, (err, sha) ->
            assert.equal sha, targetSha
            done()
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
