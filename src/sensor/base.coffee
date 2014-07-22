# Ping test class
# =================================================

# Node Modules
# -------------------------------------------------

# include base modules
EventEmitter = require('events').EventEmitter
object = require('alinex-util').object
colors = require 'colors'

# Sensor class
# -------------------------------------------------
class Sensor extends EventEmitter

  # ### Default Configuration
  @config:
    verbose: false

  # ### Create instance
  constructor: (config) ->
    @config = object.extend Sensor.config, config
    unless config
      throw new Error "Could not initialize sensor without configuration."

  _start: (title) ->
    @result =
      date: new Date
      status: 'running'
    @emit 'start'
    if @config.verbose
      console.log "#{title}..."

  _end: (status, message) ->
    @result.status = status
    @result.message = message if message
    if @config.verbose and status is 'fail' and message
      console.log "#{@type} #{status}: #{message}".red
      console.log @result.data.grey
    @emit status
    @emit 'end'

# Export class
# -------------------------------------------------
module.exports = Sensor