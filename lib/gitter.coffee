pushover = require 'pushover'
path = require 'path'
os = require 'os'
repodir = path.resolve process.cwd(), 'repos'
repos = pushover repodir
model = require '../lib/model.coffee'
cavalry = require '../lib/cavalry.coffee'
host = process.env.HOSTNAME or os.hostname()
port = process.env.WEBSERVERPORT or 4001
secret = process.env.SECRET or 'testingpass'

repos.on 'push', (push) ->
  push.accept()
  opts =
    name: push.repo
    commit: push.commit
    url: "http://git:#{secret}@#{host}:#{port}/#{push.repo}"
  model.latestCommits.put opts.name, opts.commit, (err) ->
    throw err if err?
  if model.manifest and model.manifest[opts.name]?
    model.manifest[opts.name].prevCommit = JSON.parse JSON.stringify model.manifest[opts.name].opts.commit
  for slave of model.slaves
    do (slave) ->
      cavalry.fetch slave, opts, (err, body) ->
        console.error err if err?
        console.error err if body?

module.exports =
  handle: (req, res) ->
    repos.handle req, res
  repos: repos
