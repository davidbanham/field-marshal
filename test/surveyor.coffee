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
    model.slaves = {}
    model.manifest = {}
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

  it 'should identify required processes', (done) ->
    rand1 = Math.floor(Math.random() * (1 << 24)).toString(16)
    rand2 = Math.floor(Math.random() * (1 << 24)).toString(16)
    model.slaves[rand1] =
      processes:
        one:
          status: 'running'
          commit: '1'
          repo: 'a'
        two:
          status: 'running'
          commit: '2'
          repo: 'b'
    model.slaves[rand2] =
      processes:
        two:
          status: 'running'
          commit: '2'
          repo: 'b'
    model.manifest =
      a:
        instances: '*'
        opts:
          commit: '1'
      b:
        instances: 3
        opts:
          commit: '2'
    surveyor.buildRequired ->
      assert.deepEqual model.manifest.a.required, [rand2]
      assert.equal model.manifest.b.delta, 1
      done()
  it 'should find the least loaded slave', ->
    model.slaves =
      high:
        load: 9.154
      filler1:
        load: 2.113
      filler2:
        load: 3.2532
      low:
        load: 1.87698
    slaves = surveyor.sortSlaves()
    assert.equal slaves[0], 'low'
    assert.equal slaves[slaves.length - 1], 'high'
  it 'should populate env variables', (done) ->
    rand = Math.floor(Math.random() * (1 << 24)).toString(16)
    server.on "request", (req, res) ->
      res.write JSON.stringify
        port: rand
      res.end()
    opts =
      env:
        PORT: "RANDOM_PORT"
    model.slaves.portTest = { ip: '127.0.0.1' }
    surveyor.populateOptions "portTest", opts, (err, opts) ->
      assert.equal null, err
      assert.equal opts.env.PORT, rand
      done()
  it 'should spawn required processes', (done) ->
    model.manifest =
      one:
        required: ['slave1', 'slave2']
        load: 1
        opts:
          commit: '1'
          name: 'one'
      two:
        delta: 2
        load: 1
        opts:
          commit: '2'
          name: 'two'
    server.on "request", (req, res) ->
      req.on 'data', (data) ->
        parsed = JSON.parse data.toString()
        rand = Math.floor(Math.random() * (1 << 24)).toString(16)
        response = {}
        response[rand] =
          id: rand
          status: 'running'
          repo: 'reponame'
          commit: parsed.commit
          cwd: '/dev/null'
          drone: 'testDrone'
        res.end JSON.stringify response
    model.slaves['slave1'] = { ip: '127.0.0.1', load: 0 }
    model.slaves['slave2'] = { ip: '127.0.0.1', load: 0 }
    surveyor.spawnMissing (errs, procs) ->
      assert.equal errs, null
      assert.equal Object.keys(procs).length, 4
      done()
  it 'should update the portMap', (done) ->
    rand = Math.floor(Math.random() * (1 << 24)).toString(16)
    randPort = 8000 + Math.floor(Math.random() * 100)
    processes = {}
    processes[rand] =
      repo: "portTest"
      opts:
        commit: "1"
        env:
          PORT: randPort
    surveyor.updatePortMap "portMapTest", processes
    assert.deepEqual model.portMap["portMapTest"][rand],
      repo: "portTest"
      commit: "1"
      port: randPort
    done()
  it 'should calculate the routing table', (done) ->
    model.slaves["routingTestSlave1"] =
      ip: "127.0.0.1"
      processes:
        pid1:
          status: "running"
        pid2:
          status: "running"
    model.slaves["routingTestSlave2"] =
      ip: "127.0.0.2"
      processes:
        pid1:
          status: "running"
        pid2:
          status: "running"
    model.manifest =
      test1:
        opts:
          commit: '1'
          env:
            PORT: 8000
      test2:
        opts:
          commit: '1'
          env:
            PORT: 8001
    model.portMap =
      routingTestSlave1:
        pid1:
          repo: 'test1'
          commit: '1'
          port: 8000
        pid2:
          repo: 'test2'
          commit: '1'
          port: 8001
      routingTestSlave2:
        pid1:
          repo: 'test1'
          commit: '1'
          port: 8000
        pid2:
          repo: 'test2'
          commit: '1'
          port: 8001
    surveyor.calculateRoutingTable (err, table) ->
      assert.deepEqual table,
        test1:
          routes: [
            {host: "127.0.0.1", port: "8000"}
            {host: "127.0.0.2", port: "8000"}
          ]
        test2:
          routes: [
            {host: "127.0.0.1", port: "8001"}
            {host: "127.0.0.2", port: "8001"}
          ]
    done()
  it 'should omit services running the wrong commit', (done) ->
    model.slaves["routingTestSlave1"] =
      ip: "127.0.0.1"
      processes:
        pid1:
          status: "running"
        pid2:
          status: "running"
    model.slaves["routingTestSlave2"] =
      ip: "127.0.0.2"
      processes:
        pid1:
          status: "running"
        pid2:
          status: "running"
    model.manifest =
      test1:
        opts:
          commit: '1'
          env:
            PORT: 8000
      test2:
        opts:
          commit: '1'
          env:
            PORT: 8001
    model.portMap =
      routingTestSlave1:
        pid1:
          repo: 'test1'
          commit: '1'
          port: 8000
        pid2:
          repo: 'test2'
          commit: '2'
          port: 8001
      routingTestSlave2:
        pid1:
          repo: 'test1'
          commit: '1'
          port: 8000
        pid2:
          repo: 'test2'
          commit: '1'
          port: 8001
    surveyor.calculateRoutingTable (err, table) ->
      assert.deepEqual table,
        test1:
          routes: [
            {host: "127.0.0.1", port: 8000}
            {host: "127.0.0.2", port: 8000}
          ]
        test2:
          routes: [
            {host: "127.0.0.2", port: 8001}
          ]
    done()
  it 'should disseminate the routing table to all slaves', (done) ->
    model.slaves["routingTestSlave1"] =
      ip: "127.0.0.1"
      processes:
        pid1:
          status: "running"
    table =
      test1:
        routes: [
          {host: "127.0.0.1", port: 8000}
        ]
    server.on "request", (req, res) ->
      req.on 'data', (data) ->
        parsed = JSON.parse data.toString()
        assert.deepEqual parsed, table
        res.end()
    surveyor.propagateRoutingTable table, (err) ->
      assert.equal err, null
      done()
