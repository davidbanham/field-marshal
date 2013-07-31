model = require '../lib/model.coffee'
request = require 'request'
SECRET = process.env.CAVALRYPASS or "testingpass"

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

  return this

cavalry = new Cavalry()
module.exports = cavalry
