assert = require 'assert'
surveyor = require '../lib/surveyor'
model = require '../lib/model'
fs = require 'fs'
http = require 'http'
server = http.createServer()

describe "surveyor.getManifest", ->
  before ->
    fs.writeFileSync './manifest/test_1.json', JSON.stringify
      name1:
        instances: 7
    fs.writeFileSync './manifest/test_2.json', JSON.stringify
      name2:
        instances: 3
  after ->
    fs.unlinkSync './manifest/test_1.json'
    fs.unlinkSync './manifest/test_2.json'
  it 'should concatenate all json files in a dir into one manifest', (done) ->
    surveyor.getManifest (err) ->
      assert.equal err, null
      assert.equal model.manifest.name1.instances, 7
      assert.equal model.manifest.name2.instances, 3
      done()
  it 'should complain when something is duplicated', (done) ->
    fs.writeFileSync './manifest/test_2dup.json', JSON.stringify
      name2:
        instances: 3
    surveyor.getManifest (err) ->
      fs.unlinkSync './manifest/test_2dup.json'
      for error in err
        done() if error is "name2 is duplicated"
  it 'should handle malformed JSON', (done) ->
    fs.writeFileSync './manifest/test_malformed.json', "lol this totally isn't JSON"
    surveyor.getManifest (err, manifest) ->
      fs.unlinkSync './manifest/test_malformed.json'
      for error in err
        if error.file is "test_malformed.json"
          done() if error.error.type is "unexpected_token"
describe "surveyor", ->
  beforeEach ->
    server.listen 3000
  afterEach ->
    server.removeAllListeners "request"
    server.close()
  it 'should ps all drones', (done) ->
    rand1 = Math.floor(Math.random() * (1 << 24)).toString(16)
    rand2 = Math.floor(Math.random() * (1 << 24)).toString(16)
    model.slaves[rand1] = { ip: '127.0.0.1' }
    model.slaves[rand2] = { ip: '127.0.0.1' }
    server.on "request", (req, res) ->
      res.end JSON.stringify
        someID:
          id: 'someID'
          status: 'running'
          repo: 'reponame'
          commit: 'commitid'
          cwd: '/dev/null'
          drone: 'testDrone'
    surveyor.ps (err, procs) ->
      assert.equal procs[rand1].someID.status, "running"
      assert.equal procs[rand2].someID.status, "running"
      done()

  it.only 'should identify required processes', ->
    assert false
  it 'should find the least loaded slave', ->
    assert false
  it 'should populate env variables', ->
    assert false
  it 'should spawn required processes', ->
    assert false
  it 'should calculate the routing table', ->
    assert false
  it 'should disseminate the routing table to all slaves', ->
    assert false
