assert = require 'assert'
util = require '../lib/util.coffee'
describe 'util', ->
  it 'should return the same hash for the same object', (done) ->
    obj1 =
      oh: 'hai'
    obj2 =
      oh: 'hai'
    assert.equal util.hashObj(obj1), util.hashObj(obj2)
    done()
  it 'should return a different hash for different objects', (done) ->
    obj1 =
      oh: 'hai'
    obj2 =
      oh: 'noes!'
    assert.notEqual util.hashObj(obj1), util.hashObj(obj2)
    done()
  it 'should return an error object for an unJSON.stringifiable object', (done) ->
    Circ = ->
      @circ = @
    obj = new Circ
    assert.deepEqual util.hashObj(obj), new Error "TypeError: Converting circular structure to JSON"
    done()
