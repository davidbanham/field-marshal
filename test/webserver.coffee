assert = require 'assert'
request = require 'request'
http = require 'http'
webserver = require "../lib/webserver.coffee"
model = require("../lib/model.coffee")
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
      done assert.equal res.statusCode, 401
  it 'should return a 401 on the wrong password', (done) ->
    request.get "http://localhost:4001", (err, res, body) ->
      done assert.equal res.statusCode, 401
    .auth "user", "wrongpass"
  it 'should return a 200 on the right password', (done) ->
    request.get "http://localhost:4001/health", (err, res, body) ->
      done assert.equal res.statusCode, 200
    .auth "user", "testingpass"
  it 'should return 404 on a null path', (done) ->
    request.get "http://localhost:4001", (err, res, body) ->
      done assert.equal res.statusCode, 404
    .auth "user", "testingpass"
