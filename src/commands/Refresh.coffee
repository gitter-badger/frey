Command = require "../Command"
debug   = require("depurar")("frey")
chalk   = require "chalk"
glob    = require "glob"
async   = require "async"
fs      = require "fs"
_       = require "lodash"
INI     = require "ini"
YAML    = require "js-yaml"
TOML    = require "toml"

class Refresh extends Command
  boot: [
    "_findTomlFiles"
    "_readTomlFiles"
    "_mergeToml"
    "_splitToml"
    "_gatherTerraformArgs"
  ]

  _findTomlFiles: (cargo, cb) ->
    tomlFiles = []
    pattern   = "#{@options.recipeDir}/*.toml"
    debug "Reading from '#{pattern}'"
    glob pattern, (err, files) ->
      if err
        return cb err

      tomlFiles = files
      cb null, tomlFiles

  _readTomlFiles: (tomlFiles, cb) ->
    tomlContents = []
    async.map tomlFiles, fs.readFile, (err, buf) ->
      if err
        return cb err

      tomlContents.push TOML.parse "#{buf}"
      cb null, tomlContents

  _mergeToml: (tomlContents, cb) ->
    tomlMerged = {}
    for tom in tomlContents
      tomlMerged = _.extend tomlMerged, tom

    cb null, tomlMerged

  _splitToml: (tomlMerged, cb) ->
    filesWritten = []

    async.series [
      (callback) =>
        if !tomlMerged.infra?
          debug "No infra instructions found in merged toml"
          fs.unlink @runtime.paths.infraFile, (err) ->
            callback null # That's not fatal
          return

        encoded = JSON.stringify tomlMerged.infra, null, "  "
        if !encoded
          return callback new Error "Unable to convert recipe to Terraform infra JSON"

        filesWritten.push @runtime.paths.infraFile
        fs.writeFile @runtime.paths.infraFile, encoded, callback
      (callback) =>
        if !tomlMerged.install?.config?
          debug "No config instructions found in merged toml"
          fs.unlink @runtime.paths.ansibleCfg, (err) ->
            callback null # That's not fatal
          return

        encoded = INI.encode tomlMerged.install.config
        if !encoded
          return callback new Error "Unable to convert recipe to ansibleCfg INI"

        # Ansible strips over a quoted `ssh_args="-o x=y -o w=z"`, as it uses exec to call
        # ssh, and all treats multiple option arguments as one.
        # So we remove all double-quotes here. If that poses problems I don't foresee at
        # this point, the replace has to be limited in scope:
        encoded = encoded.replace /\"/g, ""

        filesWritten.push @runtime.paths.ansibleCfg
        fs.writeFile @runtime.paths.ansibleCfg, encoded, callback
      (callback) =>
        if !tomlMerged.install?.playbooks?
          debug "No install playbook instructions found in merged toml"
          fs.unlink @runtime.paths.playbookFile, (err) ->
            callback null # That's not fatal
          return

        encoded = YAML.safeDump tomlMerged.install.playbooks
        if !encoded
          return callback new Error "Unable to convert recipe to Ansible playbook YAML"

        filesWritten.push @runtime.paths.playbookFile
        fs.writeFile @runtime.paths.playbookFile, encoded, callback
    ], (err) ->
      if err
        return cb err

      cb null, filesWritten

  _gatherTerraformArgs: (filesWritten, cb) ->
    terraformArgs = []
    if !chalk.enabled
      terraformArgs.push "-no-color"

    terraformArgs.push "-state=#{@runtime.paths.stateFile}"

    cb null, terraformArgs

  main: (cargo, cb) ->
    terraformExe = (dep.exe for dep in @runtime.deps when dep.name == "terraform")[0]
    cmd          = [
      terraformExe
      "refresh"
    ]
    cmd = cmd.concat @bootCargo._gatherTerraformArgs

    @_exe cmd, verbose: false, limitSamples: false, (err, stdout) ->
      if err
        if "#{err.details}".match /when there is existing state/
          debug "Ignoring refresh error about missing statefile"
          return cb null
        else
          return cb err

      cb null

module.exports = Refresh
