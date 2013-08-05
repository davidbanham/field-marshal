fs = require 'fs'
path = require 'path'

manifestDir = path.resolve __dirname, '..', 'manifest'
Surveyor = ->
  @getManifest = (cb) ->
    manifest = {}
    fs.readdir manifestDir, (err, files) ->
      errs = []
      parts = 0
      for file in files
        parts++
        do (file) ->
          fs.readFile path.join(manifestDir, file), (err, data) ->
            try
              parsed = JSON.parse data
            catch e
              errs.push {file: file, error: e}
            for name, data of parsed
              errs.push "#{name} is duplicated" if manifest[name]?
              manifest[name] = data
            parts--
            cb errs, manifest if parts is 0
  return this

surveyor = new Surveyor()
module.exports = surveyor
