model = require '../lib/model.coffee'
request = require 'request'
SECRET = process.env.CAVALRYPASS or "testingpass"

parseJSON = (str) ->
  try
    str = JSON.parse str
  catch err
  return str

Cavalry = ->
  @postJSON = (arg, slave, opts, cb) ->
    url = "http://#{model.slaves[slave].ip}:3000/#{arg}"
    request
      json: opts
      auth:
        user: "master"
        pass: SECRET
      url: url
    , (error, response, body) ->
      body = parseJSON body
      cb error, body
  @getJSON = (arg, slave, cb) ->
    url = "http://#{model.slaves[slave].ip}:3000/#{arg}"
    request.get
      url: url
      auth:
        user: "master"
        pass: SECRET
    , (error, response, body) ->
      body = parseJSON body
      cb error, body
  @spawn = (slave, opts, cb) =>
    @postJSON "spawn", slave, opts, cb
  @stop = (slave, opts, cb) =>
    @postJSON "stop", slave, opts, cb
  @restart = (slave, opts, cb) =>
    @postJSON "restart", slave, opts, cb
  @fetch = (slave, opts, cb) =>
    @postJSON "fetch", slave, opts, cb
  @deploy = (slave, opts, cb) =>
    @postJSON "deploy", slave, opts, cb
  @port = (slave, cb) =>
    @getJSON "port", slave, cb
  @ps = (slave, cb) ->
    @getJSON "ps", slave, cb

  return this

cavalry = new Cavalry()
module.exports = cavalry
