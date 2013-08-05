assert = require 'assert'
request = require 'request'
http = require 'http'
cavalry = require '../lib/cavalry'
model = require '../lib/model.coffee'

server = http.createServer()

describe "cavalry", ->
  beforeEach (done) ->
    server.listen 3000
    model.slaves['cavalry-us'] =
      ip: '127.0.0.1'
    done()
  afterEach (done) ->
    server.removeAllListeners "request"
    server.close()
    done()

  it "should send the correct auth headers", (done) ->
    server.on 'request', (req, res) ->
      authArray = new Buffer(req.headers.authorization.split(' ')[1], 'base64').toString('ascii').split(':')
      res.end()
      assert.equal authArray[0], "master"
      assert.equal authArray[1], "testingpass"
      done()
    cavalry.spawn 'cavalry-us', {}, (err, procs) ->
      assert.equal err, null

  it "should pass a spawn command to a slave", (done) ->
    server.on "request", (req, res) ->
      req.on "data", (buf) ->
        assert.deepEqual JSON.parse(buf.toString()), {test: "testing"}
        res.end()
    cavalry.spawn 'cavalry-us', {test: "testing"}, (err, procs) ->
      assert.equal err, null
      done()

  it "should pass back the procs object", (done) ->
    server.on "request", (req, res) ->
      res.end JSON.stringify { somePID: { id: "somePID", status: "running" } }
    cavalry.spawn 'cavalry-us', {test: "testing"}, (err, procs) ->
      assert.equal err, null
      assert.deepEqual procs, { somePID: { id: "somePID", status: "running" } }
      done()
  it "should fetch a ps object", (done) ->
    server.on "request", (req, res) ->
      res.end JSON.stringify
        someID:
          id: 'someID'
          status: 'running'
          repo: 'reponame'
          commit: 'commitid'
          cwd: '/dev/null'
          drone: 'testDrone'
    cavalry.ps 'cavalry-us', (err, procs) ->
      done assert.deepEqual procs,
        someID:
          id: 'someID'
          status: 'running'
          repo: 'reponame'
          commit: 'commitid'
          cwd: '/dev/null'
          drone: 'testDrone'
