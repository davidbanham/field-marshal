crypto = require 'crypto'
module.exports =
  hashObj: (obj) ->
    md5sum = crypto.createHash 'md5'
    try
      str = JSON.stringify obj
    catch e
      return e
    md5sum.update str
    return md5sum.digest 'hex'
  apiVersion: '1'
