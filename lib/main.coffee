fs = require 'fs'
path = require 'path'
mkdirp = require 'mkdirp'
Q = require 'q'

{CompositeDisposable} = require 'atom'
CodewarsView = require './codewars-view'

DATA_DIR = 'codewars-workspace'
OPEN_FILE_KEY = DATA_DIR + '-loading'

module.exports = Codewars =
  subscriptions: null
  codewarsView: null
  path: null
  pathStatesDir: null
  pathWindowState: null
  pathFocusState: null
  firstWindowAtLaunch: false

  activate: (state) ->
    window.codewars = @
    @state = state
    @path = path.join atom.getConfigDirPath(), DATA_DIR
    @pathStatesDir = path.join @path, '.states'
    @pathWindowState = path.join @pathStatesDir, 'window'
    @pathFocusState = path.join @pathStatesDir, 'focus'

    if state.isCodewarsWindow
      @_clearWindowState ->
        atom.close()
      return

    if atom.getCurrentWindow().id is 1
      @firstWindowAtLaunch = true
      fs.access @pathWindowState, (err) =>
        if err then @firstWindowAtLaunch = false

    checkIfCodewarsWindow = (textEditorFile) =>
      if (path.basename textEditorFile) is OPEN_FILE_KEY
        @_writeWindowState()
        # Actually create the view now
        @createView state

    mkdirp @pathStatesDir, (err) =>
      throw err if err
      # Check if the window has the codewars initial file open
      textEditorFile = atom.workspace.getActiveTextEditor()?.buffer.file?.path
      if textEditorFile
        checkIfCodewarsWindow textEditorFile
      else
        @_textEditorObserver =
          atom.workspace.observeTextEditors (editor) =>
            checkIfCodewarsWindow editor?.buffer.file?.path
            @_textEditorObserver?.dispose()

    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace', 'codewars:toggle': => @toggle()

  createView: (state) ->
    @codewarsView = new CodewarsView @path, state.codewarsViewState
    @codewarsView.show()
    @_watchStateFiles()

  deactivate: ->
    @_pathStatesWatcher?.close()
    @_clearWindowState()
    @subscriptions?.dispose()
    @codewarsView?.destroy()

  serialize: ->
    isCodewarsWindow: !!@codewarsView
    codewarsViewState: @codewarsView?.serialize()

  toggle: ->
    @_checkWindowState (openNewWindow) =>
      return unless openNewWindow
      atom.open pathsToOpen: [path.join(@path, OPEN_FILE_KEY)], newWindow: true

    if @codewarsView
      if @codewarsView.isVisible() then @codewarsView.hide()
      else @codewarsView.show()
    else
      @_touchFocusState()

  # == Private functions == #

  _writeWindowState: (cb) ->
    fs.writeFile @pathWindowState, atom.getCurrentWindow().id, cb

  _checkWindowState: (callback) ->
    fs.readFile @pathWindowState, (err, data) =>
      if err or @firstWindowAtLaunch or not data?.toString()?.length
        @firstWindowAtLaunch = false
        @_clearWindowState -> callback true
      else callback false

  _clearWindowState: (callback) ->
    fs.unlink @pathWindowState, callback

  _touchFocusState: ->
    fs.writeFile @pathFocusState

  _watchStateFiles: ->
    @_pathStatesWatcher = fs.watch @pathStatesDir
    @_pathStatesWatcher.on 'change', (event, filename) =>
      if filename is 'window'
        fs.readFile @pathWindowState, (err, data) =>
          if err or (parseInt data.toString()) isnt atom.getCurrentWindow().id
            @_writeWindowState()
      if filename is 'focus'
        if not @codewarsView.isVisible() then @codewarsView.show()
        atom.getCurrentWindow().focus()