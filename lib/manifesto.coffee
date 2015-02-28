path = require 'path'
fs = require 'fs'
Validator = require('jsonschema').Validator

v = new Validator()

schemas =
  routing:
    id: '/Routing'
    type: 'object'
    required: true
    properties:
      domain:
        type: 'string', required: true
      directives:
        type: 'array'
        required: false
        items:
          type: 'string'
      location_arguments:
        type: 'array'
        required: false
        items:
          type: 'string'
  opts:
    id: '/Opts'
    type: 'object'
    required: true
    properties:
      setup:
        type: 'array'
        items:
          type: 'string'
      command:
        type: 'array'
        required: true
        items:
          type: 'string'
      commit:
        type: 'string', required: true
      env:
        type: 'object', required: true
      maintenance_mode_upgrades:
        type: 'boolean', required: false
  manifest:
    id: '/Manifest'
    type: 'object'
    required: true
    properties:
      instances:
        type: 'string', required: true
      load:
        type: 'integer', required: true
      routing:
        $ref: '/Routing'
      opts:
        $ref: '/Opts'

v.addSchema(schemas[schema], data.id) for schema, data of schemas

Manifesto = ->
  @manifestDir = path.resolve process.cwd(), 'manifest'
  return this

jsonOnly = (file) ->
  return true if path.extname(file) is '.json'
  false

Manifesto.prototype.manifests = (cb) ->
  fs.readdir @manifestDir, (err, files) =>
    files = files.filter jsonOnly
    return cb null, [] if files.length is 0
    done = 0
    manifests = []
    files.map (file) =>
      fs.readFile path.join(@manifestDir, file), (err, contents) ->
        try
          manifests.push { file: file, manifest: JSON.parse contents.toString() }
        catch e
          console.error 'invalid JSON in manifest directory', file
        done++
        cb null, manifests if done is files.length

Manifesto.prototype.write = (info, cb) ->
  fs.writeFile path.join(@manifestDir, info.file), JSON.stringify(info.manifest), cb

Manifesto.prototype.validate = (manifest) ->
  return new Error 'No manifests provided' if Object.keys(manifest).length is 0
  errors = Object.keys(manifest).map (repo) ->
    errors = v.validate(manifest[repo], '/Manifest').errors
    return null if errors.length is 0
    return errors
  errors = errors.filter (errors) ->
    return true if errors
  return null if errors.length is 0
  return errors

module.exports = new Manifesto
