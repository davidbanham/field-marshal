manifesto = require '../lib/manifesto'

fs = require 'fs'
rimraf = require 'rimraf'
mkdirp = require 'mkdirp'
assert = require 'assert'

rand = Math.floor(Math.random() * (1 << 24)).toString(16)
testFolder = "./#{rand}"

test1 =
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

test2 = JSON.parse JSON.stringify test1
test2.test2 = test2.test1
delete test2.test1
test2.test2.routing.domain = '2.example.com'

describe 'manifesto', ->
  beforeEach ->
    mkdirp.sync testFolder
    fs.writeFileSync "#{testFolder}/test1.json", JSON.stringify test1
    fs.writeFileSync "#{testFolder}/test2.json", JSON.stringify test2
    manifesto.manifestDir = testFolder
  afterEach ->
    rimraf.sync testFolder

  it 'should return all the manifests by file', (done) ->
    expected = [ {file: 'test1.json', manifest: test1}, {file: 'test2.json', manifest: test2} ]
    manifesto.manifests (err, manifests) ->
      done assert.deepEqual manifests, expected
  it 'should allow you to overwrite a manifest', (done) ->
    new_test1 = JSON.parse JSON.stringify test1
    new_test1.load = 5
    manifesto.write {file: 'test1.json', manifest: new_test1}, (err) ->
      assert.equal err, null
      manifesto.manifests (err, manifests) ->
        done assert.equal manifests[0].manifest.load, 5
  it 'should allow you to write a new manifest', (done) ->
    new_manifest = JSON.parse JSON.stringify test1
    new_manifest.domain = 'totallynew.example.com'
    manifesto.write {file: 'totallynew.json', manifest: new_manifest}, (err) ->
      assert.equal err, null
      manifesto.manifests (err, manifests) ->
        assert.equal manifests[2].file, 'totallynew.json'
        done assert.equal manifests[2].manifest.domain, 'totallynew.example.com'
  it 'should fail an invalid manifest', ->
    new_manifest = JSON.parse JSON.stringify test1
    delete new_manifest.test1
    assert.notEqual null, manifesto.validate new_manifest

    new_manifest = JSON.parse JSON.stringify test1
    delete new_manifest.test1.opts
    assert.notEqual null, manifesto.validate new_manifest

    new_manifest = JSON.parse JSON.stringify test1
    delete new_manifest.test1.opts.commit
    assert.notEqual null, manifesto.validate new_manifest

    new_manifest = JSON.parse JSON.stringify test1
    delete new_manifest.test1.instances
    assert.notEqual null, manifesto.validate new_manifest

    new_manifest = JSON.parse JSON.stringify test1
    delete new_manifest.test1.routing
    assert.notEqual null, manifesto.validate new_manifest

  it 'should pass a valid manifest', ->
    new_manifest = JSON.parse JSON.stringify test1
    assert.equal null, manifesto.validate new_manifest

  it 'should pass multiple valid manifests', ->
    new_manifest = JSON.parse JSON.stringify test1
    new_manifest.test2 = JSON.parse JSON.stringify new_manifest.test1
    assert.equal null, manifesto.validate new_manifest

  it 'should fail multiple manifests where one is invalid', ->
    new_manifest = JSON.parse JSON.stringify test1
    new_manifest.test2 = JSON.parse JSON.stringify new_manifest.test1
    delete new_manifest.test2.routing
    assert.notEqual null, manifesto.validate new_manifest
