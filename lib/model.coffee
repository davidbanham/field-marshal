levelup = require 'level',

Model = ->
  @ttl = 3000
  @slaves = {}
  @latestCommits = levelup './commits.db'
  @prevCommits = levelup './prevCommits.db'
  @serviceInfo = levelup './serviceInfo.db', {valueEncoding: 'json'}

  return this

model = new Model()
module.exports = model
