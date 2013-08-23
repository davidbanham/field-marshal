surveyor = require './lib/surveyor.coffee'
websocket = require './lib/websocket.coffee'
webserver = require './lib/webserver.coffee'
webserver.listen 4001
util = require './lib/util.coffee'

lock = false
check = ->
  return if lock
  lock = true
  surveyor.getManifest (err) ->
    console.error err if err?
    throw new Error err if err?
    surveyor.buildRequired ->
      surveyor.spawnMissing (err, procs) ->
        lock = false
        return console.error err, procs if err?
        console.log "spawned", procs if Object.keys(procs).length isnt 0

currentRoutingTable = ""
route = ->
  surveyor.calculateRoutingTable (err, table) ->
    return console.error err if err?
    hash = util.hashObj(table)
    if hash isnt currentRoutingTable
      surveyor.propagateRoutingTable table, (errs) ->
        currentRoutingTable = hash unless errs?
        console.error errs if err?

setInterval ->
  check()
, 3000

setTimeout ->
  setInterval ->
    route()
  , 3000
, 1500
