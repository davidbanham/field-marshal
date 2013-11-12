assert = require 'assert'
model = require("../lib/model.coffee")
util = require("../lib/util.coffee")
WebSocket = require('ws')
EventEmitter = require('events').EventEmitter
wss = null
http = require 'http'
server = http.createServer()

describe "websocket", ->
  before (done) ->
    wss = require '../lib/websocket.coffee'
    model.ttl = 5
    done()
  after (done) ->
    wss.close()
    done()
  it "should add clients to the database", (done) ->
    rand = Math.floor(Math.random() * (1 << 24)).toString(16)
    ws = new WebSocket "ws://localhost:4000"
    ws.on 'open', ->
      ws.send JSON.stringify
        id: rand
        secret: "testingpass"
        type: "checkin"
        apiVersion: util.apiVersion
    ws.on 'error', (err) ->
      throw new Error err
    ws.on 'message', (message) ->
      assert model.slaves[rand]
      assert.equal model.slaves[rand].ip, "127.0.0.1"
      done()
  it "should update the port map", (done) ->
    rand = Math.floor(Math.random() * (1 << 24)).toString(16)
    ws = new WebSocket "ws://localhost:4000"
    ws.on 'open', ->
      ws.send JSON.stringify
        id: rand
        secret: "testingpass"
        type: "checkin"
        apiVersion: util.apiVersion
        processes:
          somepid:
            id: 'somepid'
            status: 'running'
            repo: 'portTest'
            opts:
              commit: '1'
              env:
                PORT: 3000
    ws.on 'error', (err) ->
      throw new Error err
    ws.on 'message', (message) ->
      assert.deepEqual model.portMap[rand].somepid,
        repo: "portTest"
        commit: "1"
        port: 3000
      done()

  it "should delete stale clients", (done) ->
    rand = Math.floor(Math.random() * (1 << 24)).toString(16)
    ws = new WebSocket "ws://localhost:4000"
    ws.on 'open', ->
      ws.send JSON.stringify
        id: rand
        secret: "testingpass"
        type: "checkin"
        apiVersion: util.apiVersion
        processes: {}
    ws.on 'error', (err) ->
      throw new Error err
    ws.on 'message', (message) ->
      assert model.slaves[rand]
      setTimeout ->
        done assert.equal undefined, model.slaves[rand]
      , 7
  it "should emit events passed up from slaves", (done) ->
    rand = Math.floor(Math.random() * (1 << 24)).toString(16)
    ws = new WebSocket "ws://localhost:4000"
    ws.on 'open', ->
      ws.send JSON.stringify
        id: rand
        secret: "testingpass"
        type: "event"
        event: "exit"
        info:
          code: 2
          signal: "SIGTERM"
    ws.on 'error', (err) ->
      throw new Error err
    wss.once 'slaveEvent', (event) ->
      done assert.deepEqual event,
        slaveId: rand
        type: "exit"
        info:
          code: 2
          signal: "SIGTERM"
  it "should be an eventEmitter", ->
    assert wss instanceof EventEmitter
  it "should re-propagate the routing table if a node isn't up to date", (done) ->
    model.portMap = {}
    model.slaves =
      routingTableTest:
        ip: '127.0.0.1'
    server.listen 3000
    server.on 'request', (req, res) ->
      assert.equal req.url, '/routingTable'
      req.on 'data', (data) ->
        parsed = JSON.parse data.toString()
        assert.deepEqual parsed, {}
        server.removeAllListeners "request"
        server.close()
        done()
    ws = new WebSocket "ws://localhost:4000"
    ws.on 'open', ->
      ws.send JSON.stringify
        secret: "testingpass"
        type: "checkin"
        apiVersion: util.apiVersion
        id: "routingTableTest"
        processes: {}
        routingTableHash: "foo"
    ws.on 'error', (err) ->
      throw new Error err
  it "shouldn't re-propagate the routing table if a node is up to date", (done) ->
    model.portMap = {}
    model.currentRoutingTableHash = "bar"
    model.slaves =
      routingTableTest:
        ip: '127.0.0.1'
    server.listen 3000
    server.on 'request', (req, res) ->
      throw new Error "Routing table request recieved!"
    setTimeout ->
      server.removeAllListeners "request"
      server.close()
      done()
    , 400
    ws = new WebSocket "ws://localhost:4000"
    ws.on 'open', ->
      ws.send JSON.stringify
        secret: "testingpass"
        type: "checkin"
        apiVersion: util.apiVersion
        id: "routingTableTest"
        processes: {}
        routingTableHash: "bar"
    ws.on 'error', (err) ->
      throw new Error err
  it 'should mark checkins as unspawnable where the api version is not matching', (done) ->
    ws = new WebSocket "ws://localhost:4000"
    ws.on 'open', ->
      ws.send JSON.stringify
        secret: 'testingpass'
        type: 'checkin'
        id: 'apiVersionTest'
        processes: {}
        routingTableHash: 'bar'
        apiVersion: '1'
      setTimeout ->
        assert.equal model.slaves.apiVersionTest.spawnable, false
        done()
      , 1
