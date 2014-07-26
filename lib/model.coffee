levelup = require 'level',

Model = ->
  @ttl = 3000
  @slaves = {}
  @latestCommits = levelup './commits.db'
  @prevCommits = levelup './prevCommits.db'

  return this

model = new Model()
module.exports = model
