fs = require 'fs'
path = require 'path'
model = require '../lib/model.coffee'
cavalry = require '../lib/cavalry.coffee'

manifestDir = path.resolve __dirname, '..', 'manifest'
Surveyor = ->
  @getManifest = (cb) ->
    manifest = {}
    fs.readdir manifestDir, (err, files) ->
      errs = null
      parts = 0
      for file in files
        parts++
        do (file) ->
          fs.readFile path.join(manifestDir, file), (err, data) ->
            try
              parsed = JSON.parse data
            catch e
              errs = [] if !errs?
              errs.push {file: file, error: e}
            for name, data of parsed
              if manifest[name]?
                errs = [] if !errs?
                errs.push "#{name} is duplicated"
              manifest[name] = data
            parts--
            model.manifest = manifest
            cb errs if parts is 0
  @ps = (cb) ->
    ps = {}
    errs = []
    jobs = 0
    for slave of model.slaves
      jobs++
      do (slave) ->
        cavalry.ps slave, (err, procs) ->
          errs.push err if err?
          ps[slave] = procs
          jobs--
          cb errs, ps if jobs is 0
  @buildRequired = (cb) ->
    for repo, repoData of model.manifest
      if repoData.instances is '*'
        required = repoData.required = []
        for slave, slaveData of model.slaves
          present = false
          for pid, procData of slaveData.processes
            present = true if procData.repo is repo and procData.status is 'running' and procData.commit is repoData.opts.commit
          required.push slave unless present
      else
        running = 0
        for slave, slaveData of model.slaves
          for pid, procData of slaveData.processes
            running++ if procData.repo is repo and procData.status is 'running' and procData.commit is repoData.opts.commit
        repoData.delta = repoData.instances - running
    cb()

  return this

surveyor = new Surveyor()
module.exports = surveyor
