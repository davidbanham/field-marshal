fs = require 'fs'
path = require 'path'
EventEmitter = require('events').EventEmitter
model = require '../lib/model.coffee'
cavalry = require '../lib/cavalry.coffee'


manifestDir = path.resolve process.cwd(), 'manifest'
Surveyor = ->
  @checkDuplicateName = (name, data, manifest, cb) ->
    if manifest[name]?
      err = "#{name} is duplicated"
    cb err, name, data
  @getManifest = (cb) ->
    manifest = {}
    fs.readdir manifestDir, (err, files) =>
      console.error "Manifest directory not found. You should probably create it" if err?.code is 'ENOENT'
      throw err if err?
      errs = null
      parts = 0
      return cb "No manifest files found" if files.length is 0
      numStanzas = 0
      numFiles = 0
      emitter = new EventEmitter
      emitter.on 'file', (file) ->
        numFiles++
        fs.readFile path.join(manifestDir, file), (err, data) ->
          numFiles--
          try
            parsed = JSON.parse data
          catch err
            emitter.emit 'fileErr', {file: file, error: err} if err?
          emitter.emit 'parsedFile', parsed
      emitter.on 'parsedFile', (parsed) ->
        return emitter.emit 'stanzaComplete' if parsed is undefined
        return emitter.emit 'stanzaComplete' if Object.keys(parsed).length is 0
        for name, data of parsed
          numStanzas++
          emitter.emit 'stanza', {name: name, data: data}
      emitter.on 'stanza', ({name, data}) =>
        @checkDuplicateName name, data, manifest, (err, name, data) ->
          emitter.emit 'duplicateErr', {err: err, name: name, data: data} if err?
          manifest[name] = data
          numStanzas--
          emitter.emit 'stanzaComplete'
      emitter.on 'fileErr', (err) ->
        errs = [] if !errs?
        errs.push err
      emitter.on 'duplicateErr', ({err, name, data}) ->
        errs = [] if !errs?
        errs.push "#{name} is duplicated"
      emitter.on 'stanzaComplete', ->
        if numStanzas is 0 and numFiles is 0
          model.manifest = manifest
          cb errs
      emitter.emit 'file', file for file in files
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
          return checkDone()
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
          return cb err if err?
          return cb new Error("Setup job failed"), {slave: slave, data: res, opts: opts} if res.code isnt 0
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
        continue if !model.manifest[service.repo]? #Bail if a listen process is no longer present in the manifest
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
