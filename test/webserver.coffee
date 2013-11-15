assert = require 'assert'
request = require 'request'
webserver = require "../lib/webserver.coffee"
model = require("../lib/model.coffee")
util = require "../lib/util.coffee"
model.ttl = 5
describe "webserver", ->
  before (done) ->
    webserver.listen 4001, ->
      done()
  after (done) ->
    webserver.close ->
      done()
  it 'should return a 401 if not authed', (done) ->
    request.get "http://localhost:4001", (err, res, body) ->
      assert.equal err, null
      done assert.equal res.statusCode, 401
  it 'should return a 401 on the wrong password', (done) ->
    request.get "http://localhost:4001", (err, res, body) ->
      assert.equal err, null
      done assert.equal res.statusCode, 401
    .auth "user", "wrongpass"
  it 'should return a 200 on the right password', (done) ->
    request.get "http://localhost:4001/health", (err, res, body) ->
      assert.equal err, null
      done assert.equal res.statusCode, 200
    .auth "user", "testingpass"
  it 'should return 404 on a null path', (done) ->
    request.get "http://localhost:4001", (err, res, body) ->
      assert.equal err, null
      done assert.equal res.statusCode, 404
    .auth "user", "testingpass"
  it 'should return a list of current slaves', (done) ->
    model.slaves =
      slave1:
        ip: "127.0.0.1"
        processes:
          pid1:
            id: "pid1"
            status: "running"
            repo: "test1"
            opts:
              commit: "1"
              env:
                PORT: 3008
    request.get "http://localhost:4001/slaves", (err, res, body) ->
      assert.deepEqual JSON.parse(body), model.slaves
      done()
    .auth "user", "testingpass"
  it 'should return the manifest', (done) ->
    model.manifest =
      a:
        instances: '*'
        opts:
          commit: '1'
    request.get "http://localhost:4001/manifest", (err, res, body) ->
      assert.deepEqual JSON.parse(body), model.manifest
      done()
    .auth "user", "testingpass"
  it 'should return permissive CORS headers', (done) ->
    request.get "http://localhost:4001/slaves", (err, res, body) ->
      assert.equal res.headers['access-control-allow-origin'], '*'
      done()
    .auth "user", "testingpass"
  it 'should expose the api version', (done) ->
    request.get "http://localhost:4001/apiVersion", (err, res, body) ->
      assert.equal body, util.apiVersion
      done()
    .auth "user", "testingpass"
