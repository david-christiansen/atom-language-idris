spawn = require('child_process').spawn
parse = require './parse'
utils = require('./utils')
EventEmitter = require('events').EventEmitter
{Logger} = require './Logger'

class IdrisModel extends EventEmitter
  constructor: ->
    @buffer = ''
    @process = undefined
    @callbacks = {}
    @warnings = {}
    super this

  process: undefined
  requestId: 0

  start: ->
    pathToIdris = atom.config.get("atom-language-idris.pathToIdris")
    @process = spawn pathToIdris, ['--ide-mode']
    @process.on 'exit', @exited.bind(this)
    @process.on 'error', @exited.bind(this)
    @process.stdout.setEncoding('utf8').on 'data', @stdout

  stop: ->
    if @process?
      @process.kill()

  stdout: (data) =>
    console.log "Data", data
    @buffer += data
    while @buffer.length > 6
      @buffer = @buffer.trimLeft().replace /\r\n/g, "\n"
      # We have 6 chars, which is the length of the command
      len = parseInt(@buffer.substr(0, 6), 16)
      if @buffer.length >= 6 + len
        # We also have the length of the command in the buffer, so
        # let's read in the command
        cmd = @buffer.substr(6, len).trim()
        Logger.logIncomingCommand cmd
        # Remove the length + command from the buffer
        @buffer = @buffer.substr(6 + len)
        # And then we can try to parse to command..
        try
          obj = parse.parse(cmd.trim())

          @handleCommand obj
        catch e
          console.log cmd.trim()
          console.log e.toString()
      else
        # We didn't have the entire command, so let's break the
        # while-loop and wait for the next data-event
        break

  handleCommand: (cmd) ->
    if cmd.length > 0
      op = cmd[0]
      params = cmd.slice 1
      switch op
        when ':return'
          id = params[params.length - 1]
          ret = params[0]
          if @callbacks[id]
            if ret[0] == ':ok'
              @callbacks[id] undefined, ret[1]
            else
              @callbacks[id]
                message: ret[1]
                warnings: @warnings[id]
            delete @callbacks[id]
            delete @warnings[id]
        when ':write-string'
          id = params[params.length - 1]
          msg = params[0]
          if @callbacks[id]
            @callbacks[id] undefined, undefined, msg
        when ':warning'
          id = params[params.length - 1]
          warning = params[0]
          @warnings[id].push warning
        when ':set-prompt'
          # Ignore
        else
          console.log op, params

  exited: ->
    console.log 'Exited'
    @process = undefined

  running: ->
    ! !@process

  load: (uri, callback) ->
    id = ++@requestId
    cmd = [
      {
        op: 'load-file'
        params: [ uri ]
      }
      id
    ]
    @callbacks[id] = callback
    @warnings[id] = []
    @sendCommand cmd

  sendCommand: (cmd) ->
    Logger.logOutgoingCommand cmd
    @process.stdin.write utils.formatObj(cmd)

cmds = [
  [
    'docs-for'
    'docsFor'
  ]
  [
    'type-of'
    'getType'
  ]
]
cmds.forEach (info) ->
  IdrisModel.prototype[info[1]] = (word, callback) ->
    id = ++@requestId
    cmd = [
      {
        op: info[0]
        params: [ word ]
      }
      id
    ]
    @callbacks[id] = callback
    @warnings[id] = []
    @sendCommand cmd

cmds = [
  [
    'case-split'
    'caseSplit'
  ]
  [
    'add-clause'
    'addClause'
  ]
]
cmds.forEach (info) ->

  IdrisModel.prototype[info[1]] = (line, word, callback) ->
    id = ++@requestId
    cmd = [
      {
        op: info[0]
        params: [
          line
          word
        ]
      }
      id
    ]
    @callbacks[id] = callback
    @warnings[id] = []
    @sendCommand cmd

IdrisModel::proofSearch = (line, word, callback) ->
  id = ++@requestId
  cmd = [
    {
      op: 'proof-search'
      params: [
        line
        word
        []
      ]
    }
    id
  ]
  @callbacks[id] = callback
  @warnings[id] = []
  @sendCommand cmd

module.exports = IdrisModel

# ---
# generated by js2coffee 2.0.4
