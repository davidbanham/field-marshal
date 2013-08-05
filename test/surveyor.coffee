assert = require 'assert'
surveyor = require '../lib/surveyor'
fs = require 'fs'
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
    surveyor.getManifest (err, manifest) ->
      assert.equal manifest.name1.instances, 7
      assert.equal manifest.name2.instances, 3
      done()
  it 'should complain when something is duplicated', (done) ->
    fs.writeFileSync './manifest/test_2dup.json', JSON.stringify
      name2:
        instances: 3
    surveyor.getManifest (err, manifest) ->
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
  it 'should ps all drones', ->
    assert false
  it 'should identify required processes', ->
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
