assert = require 'assert'
request = require 'request'
mkdirp = require 'mkdirp'
rimraf = require 'rimraf'
fs = require 'fs'
path = require 'path'
manifesto = require '../lib/manifesto.coffee'
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
        spawnable: true
        apiVersion: util.apiVersion
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
  it 'should filter stopped processes from the slave list if filterStopped is true', (done) ->
    model.slaves =
      slave1:
        ip: "127.0.0.1"
        spawnable: true
        apiVersion: util.apiVersion
        processes:
          pid1:
            id: "pid1"
            status: "running"
            repo: "test1"
            opts:
              commit: "1"
              env:
                PORT: 3008
          pid2:
            id: "pid2"
            status: "stopped"
            repo: "test1"
            opts:
              commit: "1"
              env:
                PORT: 3008
    request.get "http://localhost:4001/slaves?filterStopped=true", (err, res, body) ->
      assert !(JSON.parse(body).slave1.processes.pid2)
      done()
    .auth "user", "testingpass"
  it 'should not filter stopped processes from the slave list if filterStopped is not true', (done) ->
    model.slaves =
      slave1:
        ip: "127.0.0.1"
        spawnable: true
        apiVersion: util.apiVersion
        processes:
          pid1:
            id: "pid1"
            status: "running"
            repo: "test1"
            opts:
              commit: "1"
              env:
                PORT: 3008
          pid2:
            id: "pid2"
            status: "stopped"
            repo: "test1"
            opts:
              commit: "1"
              env:
                PORT: 3008
    request.get "http://localhost:4001/slaves", (err, res, body) ->
      assert JSON.parse(body).slave1.processes.pid2
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
  describe 'manifest', ->
    rand = Math.floor(Math.random() * (1 << 24)).toString(16)
    testFolder = "./#{rand}"
    beforeEach ->
      mkdirp.sync testFolder
      manifesto.manifestDir = testFolder
    afterEach ->
      rimraf.sync testFolder
    it 'should accept a new manifestFile', (done) ->
      manifestFile =
        file: Math.floor(Math.random() * (1 << 24)).toString(16) + '.json'
        manifest:
          test1:
            instances: '1'
            load: 1
            routing:
              domain: 'example.com'
            opts:
              setup: [ 'npm', 'install', '--production' ]
              command:  ['node', 'index.js' ]
              commit: 'LATEST'
              env:
                PORT: 'RANDOM_PORT'
      request uri: "http://localhost:4001/manifestFile", json: manifestFile, (err, res, body) ->
        assert.equal res.statusCode, 200
        assert fs.existsSync path.join testFolder, manifestFile.file
        done()
      .auth "user", "testingpass"

    it 'should return a 400 if the manifest is invalid', (done) ->
      manifestFile =
        file: Math.floor(Math.random() * (1 << 24)).toString(16) + '.json'
        manifest:
          test1:
            instances: '1'
      request uri: "http://localhost:4001/manifestFile", json: manifestFile, (err, res, body) ->
        assert.equal res.statusCode, 400
        assert !fs.existsSync path.join testFolder, manifestFile.file
        done()
      .auth "user", "testingpass"
