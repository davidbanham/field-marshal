assert = require 'assert'
surveyor = require '../lib/surveyor'
model = require '../lib/model'
util = require '../lib/util.coffee'
fs = require 'fs'
http = require 'http'
server = http.createServer()

describe "surveyor.getManifest", ->
  beforeEach ->
    try
      fs.mkdirSync './manifest'
    fs.writeFileSync './manifest/test_1.json', JSON.stringify
      name1:
        instances: 7
        opts:
          commit: '1'
    fs.writeFileSync './manifest/test_2.json', JSON.stringify
      name2:
        instances: 3
        opts:
          commit: '1'
  afterEach ->
    fs.unlinkSync './manifest/test_1.json'
    fs.unlinkSync './manifest/test_2.json'
    model.manifest = {}
    model.slaves = {}
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
        opts:
          commit: '1'
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
  it 'should prune jobs no longer in the manifest', (done) ->
    rand1 = Math.floor(Math.random() * (1 << 24)).toString(16)
    model.slaves[rand1] =
      processes:
        one:
          status: 'running'
          commit: '1'
          repo: 'a'
        two:
          status: 'running'
          commit: '2'
          repo: 'a'
    manifest =
      a:
        killable: true
        opts:
          commit: '2'
    surveyor.checkStale manifest, ->
      setTimeout ->
        assert model.kill[rand1].one
        clearTimeout model.kill[rand1].one
        model.kill = {}
        done()
      , 10
  it 'should prune jobs once the next commit is healthy', (done) ->
    rand1 = Math.floor(Math.random() * (1 << 24)).toString(16)
    model.slaves[rand1] =
      processes:
        one:
          status: 'running'
          commit: '1'
          repo: 'a'
    manifest =
      a:
        killable: true
        opts:
          commit: '2'
    model.serviceInfo.put 'a', {healthyCommits: {'2': true}}, ->
      surveyor.checkStale manifest, ->
        setTimeout ->
          assert model.kill[rand1].one
          clearTimeout model.kill[rand1].one
          model.kill = {}
          done()
        , 10

  it 'should not prune jobs if the next commit is not healthy', (done) ->
    rand1 = Math.floor(Math.random() * (1 << 24)).toString(16)
    model.slaves[rand1] =
      processes:
        one:
          status: 'running'
          commit: '1'
          repo: 'a'
    manifest =
      a:
        opts:
          commit: '2'
    model.serviceInfo.put 'a', {healthyCommits: {'1': true, '2': false}}, ->
      surveyor.checkStale manifest, ->
        assert !model.kill or !model.kill[rand1]
        model.kill = {}
        done()

  it 'should not cut over routing while the new commit is not healthy', (done) ->
    rand1 = Math.floor(Math.random() * (1 << 24)).toString(16)
    model.slaves = {}
    model.slaves[rand1] =
      ip: 'example.com'
      processes:
        pidone:
          status: 'running'
          commit: '1'
          repo: 'a'
        pidtwo:
          status: 'running'
          commit: '2'
          repo: 'a'
    model.portMap = {}
    model.portMap[rand1] =
      pidone:
        repo: 'a'
        port: 2014
        commit: '1'
    model.manifest =
      a:
        instances: 2
        killable: true
        opts:
          commit: '2'
    model.prevCommits.put 'a', '1', ->
      model.serviceInfo.put 'a', {healthyCommits: {'1': true}}, ->
        surveyor.calculateRoutingTable (err, routes) ->
          assert.deepEqual err, null
          assert.deepEqual routes,
            a:
              routes: [
                {
                  host: 'example.com'
                  port: 2014
                }
              ]
          done()

  it 'should rut over routing once the new commit is healthy', (done) ->
    rand1 = Math.floor(Math.random() * (1 << 24)).toString(16)
    model.slaves = {}
    model.slaves[rand1] =
      ip: 'example.com'
      processes:
        pidone:
          status: 'running'
          commit: '1'
          repo: 'a'
        pidtwo:
          status: 'running'
          commit: '2'
          repo: 'a'
        pidthree:
          status: 'running'
          commit: '2'
          repo: 'a'
    model.portMap = {}
    model.portMap[rand1] =
      pidone:
        repo: 'a'
        port: 2014
        commit: '1'
      pidtwo:
        repo: 'a'
        port: 2015
        commit: '2'
      pidthree:
        repo: 'a'
        port: 2016
        commit: '2'
    model.manifest =
      a:
        instances: 2
        killable: true
        opts:
          commit: '2'
    model.prevCommits.put 'a', '1', -> #FIXME Decide whether this should be checked by router or whether something else should remove the prevCommit
      model.serviceInfo.put 'a', {healthyCommits: {'2': true, '1': true}}, ->
        surveyor.calculateRoutingTable (err, routes) ->
          assert.deepEqual err, null
          assert.deepEqual routes,
            a:
              routes:[
                {
                  host: 'example.com'
                  port: 2015
                }
                {
                  host: 'example.com'
                  port: 2016
                }
              ]
          done()
  it 'should respect the kill ttl set in the options', (done) ->
    rand1 = Math.floor(Math.random() * (1 << 24)).toString(16)
    model.slaves[rand1] =
      processes:
        one:
          status: 'running'
          commit: '1'
          repo: 'a'
    manifest =
      a:
        killable: true
        killTimeout: 1000
        opts:
          commit: '2'
    model.serviceInfo.put 'a', {healthyCommits: {'2': true}}, ->
      surveyor.checkStale manifest, ->
        setTimeout ->
          assert.equal model.kill[rand1].one._idleTimeout, manifest.a.killTimeout
          clearTimeout model.kill[rand1].one
          model.kill = {}
          done()
        , 10
  it 'should prune jobs no longer in the manifest - integration', (done) ->
    fs.writeFileSync './manifest/test_2.json', JSON.stringify
      name2:
        instances: 3
        killable: true
        opts:
          commit: '1'
    model.serviceInfo.put 'name2', {healthyCommits: {'2': true}}, ->
      surveyor.getManifest (errs) ->
        throw errs if errs?
        fs.writeFileSync './manifest/test_2.json', JSON.stringify
          name2:
            instances: 3
            killable: true
            opts:
              commit: '2'
        rand1 = Math.floor(Math.random() * (1 << 24)).toString(16)
        model.slaves[rand1] =
          processes:
            one:
              status: 'running'
              commit: '1'
              repo: 'name2'
        surveyor.getManifest (errs) ->
          setTimeout ->
            throw errs if errs?
            assert model.kill[rand1].one
            clearTimeout model.kill[rand1].one
            model.kill = {}
            done()
          , 10
describe 'prevCommit', ->
  after ->
    fs.unlinkSync './manifest/test_3.json'
    model.manifest = {}
    model.slaves = {}
  it 'should update prevCommit', (done) ->
    fs.writeFileSync './manifest/test_3.json', JSON.stringify
      name3:
        instances: 3
        opts:
          commit: 'old'
    surveyor.getManifest (errs) ->
      assert !errs
      fs.writeFileSync './manifest/test_3.json', JSON.stringify
        name3:
          instances: 3
          opts:
            commit: 'new'
      surveyor.getManifest (errs) ->
        assert !errs
        model.prevCommits.get 'name3', (err, prevCommit) ->
          assert.deepEqual err, null
          assert.equal prevCommit, 'old'
          done()

describe "surveyor", ->
  beforeEach ->
    model.slaves = {}
    model.manifest = {}
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

  it 'should identify required processes', (done) ->
    rand1 = Math.floor(Math.random() * (1 << 24)).toString(16)
    rand2 = Math.floor(Math.random() * (1 << 24)).toString(16)
    model.slaves[rand1] =
      spawnable: true
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
      spawnable: true
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

  it 'should mark a commit as healthy if it has been fully deployed', (done) ->
    rand1 = Math.floor(Math.random() * (1 << 24)).toString(16)
    rand2 = Math.floor(Math.random() * (1 << 24)).toString(16)
    model.manifest[rand1] =
      instances: '*'
      opts:
        commit: '1'
    model.manifest[rand2] =
      instances: 3
      opts:
        commit: '2'
    surveyor.markHealthy ->
      model.serviceInfo.get rand1, (err, info) ->
        assert.deepEqual err, null, 'star instances failed'
        assert info.healthyCommits['1'], 'star instances failed'
        model.serviceInfo.get rand2, (err, info) ->
          assert.deepEqual err, null, 'numbered instances failed'
          assert info.healthyCommits['2'], 'numbered instances failed'
          done()

  it 'should not mark a commit as healthy if it has not been fully deployed', (done) ->
    rand1 = Math.floor(Math.random() * (1 << 24)).toString(16)
    rand2 = Math.floor(Math.random() * (1 << 24)).toString(16)
    model.manifest[rand1] =
      instances: '*'
      required: ['slave1']
    model.manifest[rand2] =
      instances: 3
      delta: 1
    model.serviceInfo.put rand1, {healthyCommits: {'foo': true}}, ->
      model.serviceInfo.put rand2, {healthyCommits: {'foo': true}}, ->
        surveyor.markHealthy ->
          model.serviceInfo.get rand1, (err, info) ->
            assert.deepEqual err, null
            assert.deepEqual info.healthyCommits['1'], undefined
            model.serviceInfo.get rand2, (err, info) ->
              assert.deepEqual err, null, 'numbered instances failed'
              assert.deepEqual info.healthyCommits['2'], undefined
              done()

  it 'should not include unspawnable slaves in buildRequired', (done) ->
    rand1 = Math.floor(Math.random() * (1 << 24)).toString(16)
    rand2 = Math.floor(Math.random() * (1 << 24)).toString(16)
    model.slaves[rand1] =
      spawnable: true
    model.slaves[rand2] =
      spawnable: false
    model.manifest =
      a:
        instances: '*'
        opts:
          commit: '1'
    surveyor.buildRequired ->
      assert.deepEqual model.manifest.a.required, [rand1]
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
    model.slaves['slave1'] = { ip: '127.0.0.1', load: 0, spawnable: true }
    model.slaves['slave2'] = { ip: '127.0.0.1', load: 0, spawnable: true }
    surveyor.spawnMissing (errs, procs) ->
      assert.equal errs, null
      assert.equal Object.keys(procs).length, 4
      done()
  it 'should not include any non spawnable drones', (done) ->
    model.manifest =
      one:
        required: ['slave1']
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
          drone: 'slave1'
        res.end JSON.stringify response
    model.slaves['slave1'] = { ip: '127.0.0.1', load: 0, spawnable: true }
    model.slaves['slave2'] = { ip: '127.0.0.2', load: 0, spawnable: false }
    surveyor.spawnMissing (errs, procs) ->
      for pid, proc of procs
        throw new Error 'unspawnable slave found' if proc.drone isnt 'slave1'
      assert.equal errs, null
      assert.equal Object.keys(procs).length, 3
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
    model.serviceInfo.put 'test1', {healthyCommits: {'1': true}}, ->
      model.serviceInfo.put 'test2', {healthyCommits: {'1': true}}, ->
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
  it 'should calculate load correctly', ->
    model.manifest =
      load:
        load: 1
    processes =
      one:
        status: 'running'
        repo: 'load'
      two:
        status: 'running'
        repo: 'load'
      three:
        status: 'stopped'
        repo: 'load'
    load = surveyor.calcLoad processes
    assert.equal load, 2
  it 'should add load to slaves as processes are spawned', (done) ->
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
    model.slaves['slave1'] = { ip: '127.0.0.1', load: 0, spawnable: true }
    model.slaves['slave2'] = { ip: '127.0.0.1', load: 0, spawnable: true }
    surveyor.spawnMissing (errs, procs) ->
      assert.equal errs, null
      assert.equal model.slaves.slave1.load, 2
      assert.equal model.slaves.slave2.load, 2
      done()
  it 'should insert the most recent commit id if requested', (done) ->
    model.latestCommits.put 'one', "I don't know, like a sha or something?", (err) ->
      assert.equal err, null
      data =
        opts:
          commit: 'LATEST'
          name: 'one'
      surveyor.insertCommit 'one', data, (err, name, data) ->
        assert.equal err, null
        assert.equal data.opts.commit, "I don't know, like a sha or something?"
        done()
  it 'should filter to only spawnable slaves', ->
    model.slaves['spawn1'] = { ip: '127.0.0.1', load: 3, spawnable: true }
    model.slaves['spawn2'] = { ip: '127.0.0.1', load: 1, spawnable: true }
    model.slaves['nospawn1'] = { ip: '127.0.0.1', load: 0, spawnable: false }
    model.slaves['nospawn2'] = { ip: '127.0.0.1', load: 2, spawnable: false }
    slaves = surveyor.filterSlaves model.slaves
    assert.equal slaves.nospawn1, undefined
    assert.equal slaves.nospawn2, undefined
