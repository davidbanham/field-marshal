leveldb = require 'level'

Model = ->
  @ttl = 3000
  @db = leveldb "./model.db"
  @slaves = {}
  return this

model = new Model()
module.exports = model
