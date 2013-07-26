assert = require 'assert'
model = require("../lib/model.coffee")
WebSocket = require('ws')
EventEmitter = require('events').EventEmitter
wss = null

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
    ws.on 'error', (err) ->
      throw new Error err
    ws.on 'message', (message) ->
      assert model.slaves[rand]
      assert.equal model.slaves[rand].ip, "127.0.0.1"
      done()
  it "should delete stale clients", (done) ->
    rand = Math.floor(Math.random() * (1 << 24)).toString(16)
    ws = new WebSocket "ws://localhost:4000"
    ws.on 'open', ->
      ws.send JSON.stringify
        id: rand
        secret: "testingpass"
        type: "checkin"
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
