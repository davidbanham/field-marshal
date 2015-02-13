#!/usr/bin/env node
// Include the CoffeeScript interpreter so that .coffee files will work
var coffee = require('coffee-script');

// Explicitly register the compiler if required. This became necessary in CS 1.7
if (typeof coffee.register !== 'undefined') coffee.register();
require('./index.coffee')
