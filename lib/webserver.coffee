http = require 'http'
url = require 'url'
model = require('../lib/model')
gitter = require '../lib/gitter'

server = http.createServer()

SECRET = process.env.SECRET or "testingpass"

server.on 'request', (req, res) ->
  res.setHeader "Access-Control-Allow-Origin", "*"
  res.setHeader "Access-Control-Allow-Headers", "Authorization, X-Requested-With"
  if !req.headers.authorization?
    res.setHeader('www-authenticate', 'Basic')
    res.writeHead 401
    return res.end "auth required"
  authArray = new Buffer(req.headers.authorization.split(' ')[1], 'base64').toString('ascii').split(':')
  if authArray[1] isnt SECRET
    res.writeHead 401
    return res.end "wrong secret"

  parsed = url.parse(req.url, true)

  switch parsed.pathname
    when "/health"
      res.end "ok"
    when "/slaves"
      res.setHeader "Content-Type", "application/json"
      slaves = {}
      for name, slave of model.slaves
        slaves[name] =
          ip: slave.ip
          processes: slave.processes
          load: slave.load
      res.end JSON.stringify slaves
    else
      gitter.handle req, res
module.exports = server
