fs = require 'fs'
path = require 'path'
EventEmitter = require('events').EventEmitter
model = require '../lib/model.coffee'
cavalry = require '../lib/cavalry.coffee'
util = require '../lib/util.coffee'

manifestDir = path.resolve process.cwd(), 'manifest'
Surveyor = ->
  @insertCommit = (name, data, cb) ->
    return cb null, name, data if !data.opts?.commit?
    if data.opts.commit is 'LATEST'
      model.latestCommits.get name, (err, commit) ->
        data.opts.commit = commit
        cb err, name, data
    else
      cb null, name, data

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
        @insertCommit name, data, (err, name, data) =>
          throw err if err?
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
      emitter.on 'stanzaComplete', =>
        if numStanzas is 0 and numFiles is 0
          #Check whether or not the manifest has changed
          model.manifest = {} if !model.manifest?
          newManifestHash = util.hashObj manifest
          oldManifestHash = util.hashObj model.manifest
          #If it has, go deal with the processes we no longer need
          if newManifestHash isnt oldManifestHash
            for item, data of manifest
              #Check whether any of the commit SHAs have changed
              if model.manifest[item]
                if data.opts.commit isnt model.manifest[item].opts.commit
                  model.prevCommits.put item, model.manifest[item].opts.commit
            frozenManifest = JSON.parse JSON.stringify model.manifest
            @checkStale manifest, ->
              model.manifest = manifest
              cb errs
          else
            #Load in the fresh manifest and we're done
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
          required.push slave unless present or !slaveData.spawnable
      else
        running = 0
        for slave, slaveData of model.slaves
          for pid, procData of slaveData.processes
            running++ if procData.repo is repo and procData.status is 'running' and procData.commit is repoData.opts.commit
        repoData.delta = repoData.instances - running
    cb()
  @markHealthy = (cb) ->
    return cb null if Object.keys(model.manifest).length is 0
    counter = 0
    for repo, repoData of model.manifest
      if (!repoData.required or repoData.required.length is 0) and (!repoData.delta or repoData.delta is 0)
        counter++
        do (repo, repoData) ->
          model.serviceInfo.get repo, (err, info) ->
            info = {healthyCommits: {}} if !info?
            info.healthyCommits[repoData.opts.commit] = true
            model.serviceInfo.put repo, info, (err) ->
              counter--
              return cb err if err?
              return cb null if counter is 0
    return cb null if counter is 0

  @sortSlaves = (slaves) ->
    ([k, v.load] for k, v of slaves or model.slaves).sort (a,b) ->
      a[1] - b[1]
    .map (n) -> n[0]
  @filterSlaves = (slaves) ->
    filtered = {}
    for name, slave of slaves
      filtered[name] = slave if slave.spawnable
    return filtered
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
    return cb new Error "Send in the Cavalry! (no slaves available)" if Object.keys(model.slaves).length is 0
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
          target = @sortSlaves(@filterSlaves(model.slaves))[0]
          model.slaves[target].load += repoData.load
          repoData.delta--
          do (target) =>
            @spawn target, repoData.opts, checkDone
    cb null, {} if numProcs is 0
  @spawn = (slave, opts, cb) =>
    @populateOptions slave, opts, (err, opts) =>
      return cb err, {slave: slave, proc: null, opts: opts} if err?
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
  @decideHealthyCommit = (service, cb) ->
    model.serviceInfo.get service.repo, (err, info) ->
      return cb err, '' if err?
      if info.healthyCommits[model.manifest[service.repo].opts.commit]
        targetCommit = model.manifest[service.repo].opts.commit
        return cb null, targetCommit
      else
        model.prevCommits.get service.repo, (err, prevCommit) ->
          targetCommit = prevCommit
          return cb new Error('latest commit not healthy'), targetCommit

  @calculateRoutingTable = (cb) ->
    return cb new Error "manifest not ready" unless model.manifest?
    routes = {}
    counter = 0

    checkDone = ->
      return cb null, routes if counter is 0

    return cb null, routes if Object.keys(model.portMap).length is 0

    for name, slave of model.portMap
      for pid, service of slave
        continue if !model.manifest[service.repo]? #Bail if a listen process is no longer present in the manifest
        do (name, slave, pid, service) =>
          #Check whether the current commit has ever successfully been deployed.
          counter++
          @decideHealthyCommit service, (err, targetCommit) ->
            counter--

            if service.commit isnt targetCommit
              return checkDone()

            routes[service.repo] ?= {}
            routes[service.repo].maintenance = false

            if (err && err.message is 'latest commit not healthy')
              if model.manifest[service.repo].opts.maintenance_mode_upgrades
                routes[service.repo].maintenance = true


            #read in all the options like routing method
            for k, v of model.manifest[service.repo].routing
              routes[service.repo][k] = v

            routes[service.repo].routes ?= []
            return checkDone() if !model.slaves[name].processes[pid]?
            if model.slaves[name].processes[pid].status is 'running'
              routes[service.repo].routes.push
                host: model.slaves[name].ip
                port: service.port
            checkDone()
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
  @checkStale = (manifest, cb = ->) ->
    return cb() if Object.keys(manifest).length is 0
    kill = (slave, pid, proc) ->
      model.serviceInfo.get proc.repo, (err, info) ->
        return if err or !info
        return if !info.healthyCommits[manifest[proc.repo].opts.commit] #current commit is not healthy
        return if model.kill and model.kill[slave] and model.kill[slave][pid]? #pid is already scheduled for destruction
        model.kill = {} if !model.kill?
        model.kill[slave] = {} if !model.kill[slave]?
        model.kill[slave][pid] =
          setTimeout ->
            cavalry.stop slave, [pid], (err) ->
              return console.error "Error stopping pid #{pid} on slave #{slave}", err if err?
          , manifest[proc.repo].killTimeout or 300000 # 5 minutes
    for slave, data of model.slaves
      for pid, proc of data.processes
        repo = manifest[proc.repo]
        kill slave, pid, proc if (proc.commit isnt repo.opts.commit) and repo.killable
    cb()

  return this

surveyor = new Surveyor()
module.exports = surveyor
