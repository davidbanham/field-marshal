fs = require 'fs'
path = require 'path'
model = require '../lib/model.coffee'
cavalry = require '../lib/cavalry.coffee'

manifestDir = path.resolve process.cwd(), 'manifest'
Surveyor = ->
  @getManifest = (cb) ->
    manifest = {}
    fs.readdir manifestDir, (err, files) ->
      console.error "Manifest directory not found. You should probably create it" if err?.code is 'ENOENT'
      throw err if err?
      errs = null
      parts = 0
      return cb "No manifest files found" if files.length is 0
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
  @sortSlaves = ->
    ([k, v.load] for k, v of model.slaves).sort (a,b) ->
      a[1] - b[1]
    .map (n) -> n[0]
  @populateOptions = (slave, opts, cb) ->
    opts = JSON.parse JSON.stringify opts
    required = {}
    errs = null
    required.port = true if opts.env? and opts.env.PORT is "RANDOM_PORT"
    checkDone = ->
      cb errs, opts if Object.keys(required).length is 0
    checkDone()
    if required.port
      cavalry.port slave, (err, res) ->
        if err?
          errs = [] if !errs?
          errs.push {slave: slave, err: err}
        opts.env.PORT = res.port
        delete required.port
        checkDone()

  @spawnMissing = (cb) =>
    return cb new Error "no slaves available" if Object.keys(model.slaves).length is 0
    errs = null
    procs = {}
    numProcs = 0
    checkDone = (err, info) ->
      slave = info.slave
      proc = info.proc
      opts = info.opts
      numProcs--
      if err?
        errs = [] if !errs?
        errs.push {slave: slave, err: err}
      else
        for pid, data of proc
          procs[pid] = data
      cb errs, procs if numProcs is 0

    for repo, repoData of model.manifest
      repoData.opts.repo = repo
      if repoData.required?
        numProcs += repoData.required.length
        for slave in repoData.required
          do (slave) =>
            model.slaves[slave].load += repoData.load
            @spawn slave, repoData.opts, checkDone
      else if repoData.delta > 0
        numProcs += repoData.delta
        while repoData.delta > 0
          target = @sortSlaves()[0]
          model.slaves[target].load += repoData.load
          repoData.delta--
          do (target) =>
            @spawn target, repoData.opts, checkDone
    cb null, {} if numProcs is 0
  @spawn = (slave, opts, cb) =>
    @populateOptions slave, opts, (err, opts) =>
      return cb err, {slave: slave, proc: null, opts: opts} if err?
      if opts.setup?
        setupOpts = JSON.parse JSON.stringify opts
        setupOpts.command = JSON.parse JSON.stringify setupOpts.setup
        setupOpts.once = true
        cavalry.exec slave, setupOpts, (err, res) ->
          cavalry.spawn slave, opts, (err, res) ->
            cb err, {slave: slave, proc: res, opts: opts}
      else
        cavalry.spawn slave, opts, (err, res) =>
          cb err, {slave: slave, proc: res, opts: opts}
  @updatePortMap = (slave, processes) ->
    for pid, proc of processes
      if proc.opts.env? and proc.opts.env.PORT?
        model.portMap ?= {}
        model.portMap[slave] ?= {}
        model.portMap[slave][pid] =
          repo: proc.repo
          port: proc.opts.env.PORT
          commit: proc.opts.commit
  @calculateRoutingTable = (cb) ->
    return cb new Error "manifest not ready" unless model.manifest?
    routes = {}
    for name, slave of model.portMap
      for pid, service of slave
        continue if service.commit isnt model.manifest[service.repo].opts.commit

        routes[service.repo] ?= {}
        #read in all the options like routing method
        for k, v of model.manifest[service.repo].routing
          routes[service.repo][k] = v

        routes[service.repo].routes ?= []
        continue if !model.slaves[name].processes[pid]?
        if model.slaves[name].processes[pid].status is 'running'
          routes[service.repo].routes.push
            host: model.slaves[name].ip
            port: service.port
    cb null, routes
  @propagateRoutingTable = (table, cb) =>
    jobs = Object.keys(model.slaves).length
    errs = null
    for name, slave of model.slaves
      cavalry.sendRouting name, table, (err, body) ->
        jobs--
        if err?
          errs ?= []
          errs.push {slave: name, err: err}
        cb errs if jobs is 0
  @calcLoad = (processes) ->
    load = 0
    for pid, proc of processes when proc.status is 'running'
      continue if !model.manifest?
      continue if !model.manifest[proc.repo]?
      load += model.manifest[proc.repo].load
    return load

  return this

surveyor = new Surveyor()
module.exports = surveyor
