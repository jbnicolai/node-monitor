# Ping test class
# =================================================

# Node Modules
# -------------------------------------------------

# include base modules
os = require 'os'
{spawn} = require 'child_process'
debug = require('debug')('monitor:ping')
colors = require 'colors'
EventEmitter = require('events').EventEmitter

object = require('alinex-util').object
Sensor = require './base'

# Sensor class
# -------------------------------------------------
class PingSensor extends Sensor

  # ### General information
  # This information may be used later for display and explanation.
  @meta =
    name: 'Ping'
    description: "Test the reachability of a host on a IP network and measure the
    round-trip time for the messages send."
    category: 'net'
    level: 1

  # ### Value Definition
  # This will define the values measured and their specifics, used to display
  # results.
  @values = [
    name: 'success'
    description: "true if test succeeded"
    type: 'bool'
  ,
    name: 'responsetime'
    description: "round-trip time of the first packet"
    type: 'int'
    unit: 'ms'
  ,
    name: 'quality'
    description: "quality of response (packets succeeded)"
    type: 'percent'
  ]

  # ### Default Configuration
  # The values starting with underscore are general help messages.
  @config =
    _ip: "IP address to test"
    count: 1
    _count: "Number of packets to send"
    timeout: 1
    _timeout: "Timeout in seconds"

  # ### Create instance
  constructor: (config) ->
    super object.extend @constructor.config, config
    unless config
      throw new Error "Could not initialize sensor without configuration."

  run: (cb = ->) ->

    # comand syntax, os dependent
    p = os.platform()
    ping = switch
      when p is 'linux'
        cmd: '/bin/ping'
        args: ['-c', @config.count, '-w', @config.timeout]
      when p.match /^win/
        cmd: 'C:/windows/system32/ping.exe'
        args: ['-n', @config.count, '-w', @config.timeout*1000]
      when p is 'darwin'
        cmd: '/sbin/ping'
        args: ['-c', @config.count, '-t', @config.timeout]
      else
        throw new Error "Operating system #{p} is not supported in ping."
    ping.args.push @config.ip

    # run the ping test
    @_start "Ping #{@config.ip}..."
    @result.data = ''
    debug "exec> #{ping.cmd} #{ping.args.join ' '}"
    proc = spawn ping.cmd, ping.args

    # collect results
    stdout = stderr = ''
    proc.stdout.on 'data', (data) ->
      stdout += (text = data.toString())
      for line in text.trim().split /\n/
        debug line[if ~line.indexOf "%" then 'yellow' else 'grey'] if line
    proc.stderr.on 'data', (data) ->
      stderr += (text = data.toString())
      for line in text.trim().split /\n/
        debug line.magenta
    store = (code) =>
      @result.data = ''
      @result.data += "STDOUT:\n#{stdout}\n" if stdout
      @result.data += "STDERR:\n#{stderr}\n" if stderr
      @result.data += "RETURN CODE: #{code}" if code?

    # Error management
    proc.on 'error', (err) ->
      store()
      @_end 'fail', err
      cb err

    # process finished
    proc.on 'exit', (code) =>
      store code
      # get the values
      @result.value = {}
      @result.value.success = code is 0
      match = /time=(\d+.?\d*) ms/.exec stdout
      @result.value.responsetime = match?[1]
      match = /\s(\d+)% packet loss/.exec stdout
      @result.value.quality = 100-match?[1]
      # evaluate to check status
      status = switch
        when not @result.value.success
          'fail'
        else
          'ok'
      message = switch status
        when 'fail'
          "#{@constructor.meta.name} exited with code #{status}"
      @_end status, message
      return cb new Error message if status is 'fail'
      cb()

# Export class
# -------------------------------------------------
module.exports = PingSensor
