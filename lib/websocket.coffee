WebSocketServer = require('ws').Server
model = require('../lib/model')
surveyor = require '../lib/surveyor'
util = require '../lib/util'

SECRET = process.env.SECRET or "testingpass"

wss = new WebSocketServer({port: 4000})
wss.on 'connection', (ws) =>
  ws.on 'message', (message) =>
    parsed = JSON.parse message
    return ws.send JSON.stringify({status: 401}) if parsed.secret isnt SECRET
    switch parsed.type
      when "checkin"
        return if parsed.apiVersion isnt util.apiVersion
        clearTimeout model.slaves[parsed.id].timer if model.slaves[parsed.id]?
        model.slaves[parsed.id] =
          ip: ws._socket.remoteAddress
          processes: parsed.processes
          load: surveyor.calcLoad parsed.processes
          timer: setTimeout ->
            delete model.slaves[parsed.id]
            delete model.portMap[parsed.id] if model.portMap? and model.portMap[parsed.id]?
          , model.ttl
        surveyor.updatePortMap parsed.id, parsed.processes
        if parsed.routingTableHash isnt model.currentRoutingTableHash
          surveyor.calculateRoutingTable (err, table) ->
            return console.error err if err?
            surveyor.propagateRoutingTable table, (err) ->
              console.error err if err?
        ws.send JSON.stringify
          status: 200
      when "event"
        wss.emit "slaveEvent",
          slaveId: parsed.id
          type: parsed.event
          info: parsed.info
      else
        ws.send JSON.stringify
          status: 404

module.exports = wss
