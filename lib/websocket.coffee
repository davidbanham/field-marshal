WebSocketServer = require('ws').Server
model = require('../lib/model')

SECRET = process.env.Secret or "testingpass"

wss = new WebSocketServer({port: 4000})
wss.on 'connection', (ws) =>
  ws.on 'message', (message) =>
    parsed = JSON.parse message
    return ws.send JSON.stringify({status: 401}) if parsed.secret isnt SECRET
    switch parsed.type
      when "checkin"
        model.slaves[parsed.id] =
          ip: ws._socket.remoteAddress
          processes: parsed.processes
          timer: setTimeout ->
            delete model.slaves[parsed.id]
          , model.ttl
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
