http = require 'http'
url = require 'url'
model = require('../lib/model')
gitter = require '../lib/gitter'

server = http.createServer()

SECRET = process.env.SECRET or "testingpass"

server.on 'request', (req, res) ->
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
    else
      gitter.handle req, res
module.exports = server
