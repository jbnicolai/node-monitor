# Controller for specific element
# =================================================

# Node Modules
# -------------------------------------------------

# include base modules
debug = require('debug')('monitor:controller')
async = require 'async'
chalk = require 'chalk'
EventEmitter = require('events').EventEmitter
os = require 'os'
# include alinex modules
Config = require 'alinex-config'
sensor = require 'alinex-monitor-sensor'
validator = require 'alinex-validator'
{string} = require 'alinex-util'
# include classes and helpers
check = require './check'


# Controller class
# -------------------------------------------------
class Controller extends EventEmitter

  # ### Check method for configuration
  #
  # This function may be used to be added to [alinex-config](https://alinex.github.io/node-config).
  # It allows to use human readable settings.
  @check = (name, values, cb) =>
    # check general config
    debug "#{name} check configuration"
    validator.check name, check.controller, values, (err, result) ->
      return cb err if err
      values = result
      # check sensors
      async.each [0..values.depend.length-1], (num, cb) ->
        return cb() unless values.depend[num].sensor?
        sensorName = values.depend[num].sensor
        unless sensor[sensorName]?
          return cb new Error "Sensor type #{sensorName} not accessible in alinex-monitor-sensor."
        source = "#{name}.depend[#{num}].config"
        val = values.depend[num].config
        validator.check source, sensor[sensorName].meta.config, val, cb
      , cb

  # ### Factory
  # Get an instance for the name
  @_instances = {}
  @instance = (name) ->
    # create new instance if needed
    unless @_instances[name]?
      @_instances[name] = new Controller name
    # return instance
    @_instances[name]

  # ### Short to run controller
  @run = (name, cb) ->
    ctrl = @instance name
    ctrl.run (err) -> cb err, ctrl

  # ### Create instance
  constructor: (@name) ->
    @config = Config.instance name
    @config.setCheck Controller.check
    debug "#{@name} initialized."

  # ### Run the controller
  running: false
  run: (cb) ->
    @config.load (err, config) =>
      # check if configuration is correct
      if err
        @result =
          date: new Date
          status: 'disabled'
        debug chalk.grey "#{@name} disabled caused by config error"
        console.warn chalk.magenta "Controller #{@name} configuration error: #{err}"
        return cb null, @result
      # check if controller is already running and listen on it
      if @running
        return @once 'done', -> cb null, @result
      # check if controller is disabled manually
      if config.disabled
        @result =
          date: new Date
          status: 'disabled'
        debug chalk.grey "#{@name} disabled manually"
        return cb null, @result
      # check if disabled on this machine
      if config.runat?
        runat = config.runat
        monitor = Config.instance 'monitor'
        runat = monitor.data.alias[runat] if monitor.data?.alias?[runat]?
        unless runat is os.hostname()
          @result =
            date: new Date
            status: 'disabled'
          debug chalk.grey "#{@name} disabled because wrong host"
          return cb null, @result
      # return if already run
      if @result? and @result.date.getTime() >= Date.now() - config.validity
        return cb null, @result
      # start normal run
      @running = true
      # listen on finished loading
      @once 'error', (err) ->
        @running = false
        debug chalk.red "#{@name} failed with #{err}"
        cb err, @result
      @once 'done', ->
        @running = false
        debug "#{@name} done", @result
        cb null, @result
      # run the controller
      @result =
        date: new Date
        status: 'running'
      debug "#{@name} analyzing"
      async.map [0..config.depend.length-1], (num, cb) =>
        # run sensor
        sensorName = config.depend[num].sensor
        if sensorName?
          instance = new sensor[sensorName] config.depend[num].config
          instance.weight = config.depend[num].weight ? 1
          return instance.run (err, result) ->
            debug "#{sensorName} sensor done"
            cb err, result
        # run sub controller
        controllerName = config.depend[num].controller
        Controller.run controllerName, (err, result) ->
          debug "#{controllerName} done"
          cb err, result
      , (err, @depend) =>
        if err
          @result.status = 'disabled'
          @result.message = "Depend error: #{err}"
          return @emit 'done', @result
        # calculate status
        @result.status = calcStatus config.combine, depend
        @result.sensorStatus = calcStatus config.combine, depend, true
        # combine messages
        messages = []
        for instance in depend
          messages.push instance.result.message if instance.result.message
        @result.message = messages.join '\n' if messages.length
        @emit 'error', err if err
        @emit 'done', @result

  # ### Format output
  format: ->
    # Introduce
    text = chalk.bold """#{@name}: #{@config.name}
    ======================================================================"""
    text += "\n#{@config.description}" if @config.description
    text += "\nResult: #{colorStatus @result.status, @result.status.toUpperCase()}"
    text += " #{colorStatus @result.status, @result.message}" if @result.message
    text += "\n\n#{@config.hint}" if @config.hint
    # add dependencie
    return text unless @depend
    text += "\n\nIndividual tests:\n"
    for instance in @depend
      text += "\n- #{instance.name ? instance.constructor.name} - #{colorStatus instance.result.status}"
    # add dependent text
    for instance in @depend
      if argv.verbose or instance.result.status in ['warn', 'fail']
        continue if instance instanceof Controller
        text += chalk.bold """\n\n#{instance.constructor.name}
        ----------------------------------------------------------------------"""
        text += "\n#{instance.format()}"
    text


# Export class
# -------------------------------------------------
module.exports = Controller


# ### Calculate status
#
# The three methods are:
#
# - max - the one with the highest failure value is used
# - min - the lowest failure value is used
# - average - the average status (arithmetic round) is used
#
# With the `weight` settings on the different entries single group entries may
# be rated specific not like the others. Use a number in `average` to make the
# weight higher (1 is normal).  Also the weight 'up' and 'down' changes the error
# level for one step before using in calculation.
calcStatus = (combine, depend, onlySensors = false) ->
  # translate name to number
  values =
    'disabled': 0
    'ok': 1
    'warn': 2
    'fail': 3
  # calculate values
  switch combine
    when 'max'
      status = 0
      for instance in depend
        continue if instance.weight is 0
        continue if onlySensors and instance instanceof Controller
        val = values[instance.result.status]
        val-- if instance.weight is 'down' and val > 0
        val++ if instance.weight is 'up' and val < 2
        status = val if val > status
    when 'min'
      status = 9
      num = 0
      for instance in depend
        continue if instance.weight is 0
        continue if onlySensors and instance instanceof Controller
        val = values[instance.result.status]
        val-- if instance.weight is 'down' and val > 0
        val++ if instance.weight is 'up' and val < 2
        status = val if val < status
        num++
      status = 0 unless num
    when 'average'
      status = 0
      num = 0
      for instance in depend
        continue if instance.weight is 0
        continue if onlySensors and instance instanceof Controller
        val = values[instance.result.status]
        val-- if instance.weight is 'down' and val > 0
        val++ if instance.weight is 'up' and val < 2
        status += val * instance.weight
        num += instance.weight
      status = Math.round status/num
  # translate status number to name
  for name, val of values
    return name if status is val
  return 'ok'

# Helper to colorize output
# -------------------------------------------------
colorStatus = (status, text) ->
  text = status unless text?
  switch status
    when 'ok'
      chalk.green text
    when 'warn'
      chalk.yellow text
    when 'fail'
      chalk.red text
    when 'disabled'
      chalk.grey text
    else
      text

