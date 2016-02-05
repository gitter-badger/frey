Depurar    = require("depurar")
debug      = Depurar("frey")
info       = Depurar("frey")
inflection = require "inflection"
async      = require "async"
util       = require "util"
_          = require "lodash"
fs         = require "fs"
os         = require "os"
path       = require "path"
mkdirp     = require "mkdirp"
chalk      = require "chalk"
Base       = require "./Base"
Mustache   = require "mustache"
osHomedir  = require "os-homedir"

class Frey extends Base
  @chain = [
    "prepare"
    "refresh"
    "validate"
    "plan"
    "backup"
    "launch"
    "install"
    "deploy"
    "restart"
    "show"
  ]

  @commands =
    prepare   : "Install dependencies like Terraform"
    refresh   : "Refreshes current infra state and saves to terraform.tfstate"
    validate  : "Checks your recipes"
    plan      : "Shows infra changes and saves in an executable plan"
    backup    : "Backs up server state"
    launch    : "Launches virtual machines at a provider"
    install   : "Runs Ansible to install software packages & configuration templates"
    deploy    : "Upload your own application(s)"
    restart   : "Restart your own application(s) and its dependencies"
    show      : "Displays active platform"

    docbuild  : "Build docs"
    restore   : "Restore latest state backup"
    remote    : "Execute a remote command - or opens console"

  boot: [
    "_injectOptions"
    "_defaults"
    "_normalize"
    "_setup"
    "_composeChain"
  ]

  constructor: (options) ->
    @options = options
    @runtime = {}

  _injectOptions: (options, nextCb) ->
    nextCb null, _.clone @options

  _defaults: (options, nextCb) ->
    options      ?= {}
    options._    ?= []
    options._[0] ?= "prepare"
    options.tmp  ?= os.tmpdir()
    options.home ?= osHomedir()
    options.user ?= process.env.USER

    nextCb null, options

  _normalize: (options, nextCb) ->
    # Render interdependent arguments
    for key, val of options
      if val == "#{val}"
        options[key] = Mustache.render val, options
        if options[key].indexOf("{{{") > -1
          return nextCb new Error "Unable to render vars in '#{key}' '#{options[key]}'"

    # Apply simple functions
    for key, val of options
      if "#{val}".match /\|basename$/
        val          = val.replace /\|basename$/, ""
        val          = path.basename val
        options[key] = val

    # Resolve to absolute paths
    for key in [ "sshkeysDir", "recipeDir", "toolsDir" ]
      if !options[key]?
        throw new Error "options.#{key} was found empty"

      options[key] = path.resolve options.recipeDir, options[key]

    if !options.tags?
      options.tags = ""

    nextCb null, options

  _setup: (options, nextCb) ->
    async.parallel [
      (callback) ->
        mkdirp options.toolsDir, callback
    ], (err) ->
      nextCb err, options

  _composeChain: (options, nextCb) ->
    cmd        = options._[0]
    indexStart = Frey.chain.indexOf(cmd)

    if indexStart < 0
      # This command is not part of the chain
      options.filteredChain = [ cmd ]
    else
      if options.bail
        length = indexStart + 1
      else if options.bailAfter && Frey.chain.indexOf(options.bailAfter) > -1
        length = Frey.chain.indexOf(options.bailAfter) + 1
      else
        length = Frey.chain.length

      options.filteredChain = Frey.chain.slice indexStart, length

    if options.filteredChain.indexOf("prepare") < 0
      options.filteredChain.unshift "prepare"

    options.filteredChain.unshift "runtime"

    nextCb null, options

  main: (bootOptions, cb) ->
    @options = bootOptions

    if @options.verbose > 0
      @_out "--> Will run: %o\n", @options.filteredChain
    else
      @_out "--> Will run: %o\n", @options.filteredChain

    async.eachSeries @options.filteredChain, @_runOne.bind(this), cb

  _runOne: (command, cb) ->
    className = inflection.classify command
    path      = "./commands/#{className}"
    obj       = new (require path) command, @options, @runtime
    func      = obj.run.bind(obj)

    @_out chalk.gray "--> "
    @_out chalk.gray "#{os.hostname()} - "
    @_out chalk.green "#{command}"
    @_out chalk.green "\n"

    func (err, result) =>
      append          = {}
      append[command] = result
      @runtime        = _.extend @runtime, append
      cb err

module.exports = Frey
