MessagePanelView = require('atom-message-panel').MessagePanelView
PlainMessageView = require('atom-message-panel').PlainMessageView
LineMessageView = require('atom-message-panel').LineMessageView
ProofObligationView = require('./proof-obligation-view')
MetavariablesView = require './metavariables-view'

class IdrisController
  idrisBuffers: 0
  localChanges: undefined

  constructor: (@statusbar, @model) ->
    @idrisBuffers = 0

    atom.workspace.getTextEditors().forEach (editor) =>
      uri = editor.getURI()
      if @isIdrisFile(uri)
        console.log editor
        @idrisFileOpened editor

    @statusbar.initialize()
    @messages = new MessagePanelView
      title: 'Idris Messages'
      closeMethod: 'hide'
    @messages.attach()
    @messages.hide()

    atom.workspace.observeActivePaneItem @paneChanged

    editor = atom.workspace.getActiveTextEditor()
    if editor?.isModified()
      @idrisFileChanged editor

  getCommands: ->
    'language-idris:type-of': @getTypeForWord
    'language-idris:docs-for': @getDocsForWord
    'language-idris:case-split': @doCaseSplit
    'language-idris:add-clause': @doAddClause
    'language-idris:metavariables': @showMetavariables
    'language-idris:proof-search': @doProofSearch

  isIdrisFile: (uri) ->
    if uri? && uri.match?
      uri.match /\.idr$/
    else
      false

  idrisFileOpened: (editor) ->
    @idrisBuffers += 1
    if !@model.running()
      console.log 'Starting Idris IDESlave'
      @model.start()
    editor.buffer.onDidDestroy @idrisFileClosed.bind(this, editor)
    editor.buffer.onDidSave @idrisFileSaved.bind(this, editor)
    editor.buffer.onDidChange @idrisFileChanged.bind(this, editor)

  idrisFileSaved: (editor) ->
    @messages.clear()
    @messages.hide()
    @localChanges = false
    if @isIdrisFile(editor.getURI())
      @loadFile editor.getURI()

  idrisFileChanged: (editor) ->
    @localChanges = editor.isModified()
    if @localChanges
      @statusbar.setStatus 'Idris: local modifications'
    else if @isIdrisFile(editor.getURI())
      @loadFile editor.getURI()

  idrisFileClosed: (editor) ->
    @idrisBuffers -= 1
    if @idrisBuffers == 0
      console.log 'Shut down Idris IDESlave'
      @model.stop()

  paneChanged: =>
    @messages.clear()
    @messages.hide()
    editor = atom.workspace.getActiveTextEditor()
    if editor
      uri = editor.getPath()
      if @isIdrisFile(uri)
        @statusbar.show()
        @loadFile uri
      else
        @statusbar.hide()

  destroy: ->
    if @idrisModel
      console.log 'Idris: Shutting down!'
      @model.stop()
    @statusbar.destroy()

  getWordUnderCursor: (editorView) ->
    editor = editorView.model
    cursorPosition = editor.getLastCursor().getCurrentWordBufferRange()
    editor.getTextInBufferRange cursorPosition

  loadFile: (uri) ->
    console.log 'Loading ' + uri
    @messages.clear()
    @model.load uri, (err, message, progress) =>
      if err
        @statusbar.setStatus 'Idris: ' + err.message
        @messages.show()
        @messages.clear()
        @messages.setTitle '<i class="icon-bug"></i> Idris Errors', true
        for warning in err.warnings
          @messages.add new LineMessageView
            line: warning[1][0]
            character: warning[1][1]
            message: warning[3]
      else if progress
        console.log '... ' + progress
        @statusbar.setStatus 'Idris: ' + progress
      else
        @statusbar.setStatus 'Idris: ' + JSON.stringify(message)

  getDocsForWord: ({target}) =>
    word = @getWordUnderCursor target
    @model.docsFor word, (err, type, highlightingInfo) =>
      if err
        @statusbar.setStatus 'Idris: ' + err.message
      else
        @messages.show()
        @messages.clear()
        @messages.setTitle 'Idris: Type of <tt>' + word + '</tt>', true
        @messages.add new ProofObligationView
          obligation: type
          highlightingInfo: highlightingInfo

  getTypeForWord: ({target}) =>
    word = @getWordUnderCursor target
    @model.getType word, (err, type, highlightingInfo) =>
      if err
        @statusbar.setStatus 'Idris: ' + err.message
      else
        @messages.show()
        @messages.clear()
        @messages.setTitle 'Idris: Type of <tt>' + word + '</tt>', true
        @messages.add new ProofObligationView
          obligation: type
          highlightingInfo: highlightingInfo

  doCaseSplit: ({target}) =>
    editor = target.model
    cursor = editor.getLastCursor()
    line = cursor.getBufferRow()
    word = @getWordUnderCursor target
    @model.caseSplit line + 1, word, (err, split) =>
      if err
        @statusbar.setStatus 'Idris: ' + err.message
      else
        lineRange = cursor.getCurrentLineBufferRange(includeNewline: true)
        editor.setTextInBufferRange lineRange, split

  doAddClause: ({target}) =>
    editor = atom.workspace.getActiveTextEditor()
    line = editor.getLastCursor().getBufferRow()
    word = @getWordUnderCursor target
    @model.addClause line + 1, word, (err, clause) =>
      if err
        @statusbar.setStatus 'Idris: ' + err.message
      else
        editor.transact ->
          # Insert a newline and the new clause
          editor.insertNewlineBelow()
          editor.insertText clause
          # And move the cursor to the beginning of
          # the new line
          editor.moveCursorToBeginningOfLine()

  showMetavariables: ({target}) =>
    @model.metavariables 80, (err, metavariables) =>
      if err
        @statusbar.setStatus 'Idris: ' + err.message
      else
        @messages.show()
        @messages.clear()
        @messages.setTitle 'Idris: Metavariables'
        @messages.add new MetavariablesView metavariables

  doProofSearch: ({target}) =>
    editor = atom.workspace.getActiveTextEditor()
    line = editor.getLastCursor().getBufferRow()
    word = @getWordUnderCursor target
    @model.proofSearch line + 1, word, (err, res) =>
      if err
        @statusbar.setStatus 'Idris: ' + err.message
      else
        editor.transact ->
          # Move the cursor to the beginning of the word
          editor.moveToBeginningOfWord()
          # Because the ? in the metavariable isn't part of
          # the word, we move left once, and then select two
          # words
          editor.moveLeft()
          editor.selectToEndOfWord()
          editor.selectToEndOfWord()
          # And then replace the replacement with the guess..
          editor.insertText res

module.exports = IdrisController
