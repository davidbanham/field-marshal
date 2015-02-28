http = require 'http'
url = require 'url'
model = require('../lib/model')
gitter = require '../lib/gitter'
cavalry = require '../lib/cavalry'
util = require '../lib/util'
manifesto = require '../lib/manifesto'

server = http.createServer()

SECRET = process.env.SECRET or "testingpass"

getJSON = (req, cb) ->
  optStr = ""
  req.on "data", (buf) ->
    optStr += buf.toString()
  req.on "end", ->
    try
      parsed = JSON.parse optStr
    catch e
      cb e, null
    cb null, parsed

respondJSONerr = (err, res) ->
  res.writeHead 400
  res.end err

server.on 'request', (req, res) ->
  res.setHeader "Access-Control-Allow-Origin", "*"
  res.setHeader "Access-Control-Allow-Headers", req.headers["access-control-request-headers"] || ""
  if req.method is 'OPTIONS'
    return res.end()
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
          spawnable: slave.spawnable
          apiVersion: slave.apiVersion
      res.end JSON.stringify slaves
    when "/manifest"
      res.setHeader "Content-Type", "application/json"
      res.end JSON.stringify model.manifest
    when "/manifestFile"
      getJSON req, (err, manifestFile) ->
        errs = manifesto.validate manifestFile.manifest
        return respondJSONerr JSON.stringify(errs), res if errs?
        manifesto.write manifestFile, (err) ->
          return respondJSONerr err, res if err?
          res.end()

    when "/stop"
      #Should there should be logic here (or elsewhere) to send the right PIDs to the right slaves?
      getJSON req, (err, opts) ->
        return respondJSONerr err, res if err?
        cavalry.stop opts.slave, opts.ids, (err, body) ->
          res.end()
    when "/apiVersion"
      res.end util.apiVersion
    else
      gitter.handle req, res
module.exports = server
