--[[
	The `rbxm-kit` command line.

	Run from source with `lune run bin/rbxm-kit <command> ...`, or as the released standalone binary
	with `rbxm-kit <command> ...`. Release binaries are built by `tools/build.luau`.
]]

local process = require("@lune/process")

local VERSION = "0.2.0"

local COMMANDS: { [string]: { run: ({ string }) -> (), summary: string } } = {
	inspect = { run = require("../src/commands/inspect"), summary = "Print a model's hierarchy and class counts" },
	scripts = { run = require("../src/commands/scripts"), summary = "Print the source of every script in a model" },
	check = { run = require("../src/commands/check"), summary = "Check a model for overlaps, loose parts, and budgets" },
	diff = { run = require("../src/commands/diff"), summary = "Summarize changes between two models or Git revisions" },
	textconv = { run = require("../src/commands/textconv"), summary = "Render a model as text for Git diffs" },
	["install-diff"] = { run = require("../src/commands/install_diff"), summary = "Configure a repository's Git diff driver" },
}

local ORDER = { "inspect", "scripts", "check", "diff", "textconv", "install-diff" }

local function printUsage()
	print(`rbxm-kit {VERSION}`)
	print("")
	print("Usage: rbxm-kit <command> [arguments]")
	print("")
	print("Commands:")
	for _, name in ORDER do
		print(string.format("  %-13s %s", name, COMMANDS[name].summary))
	end
	print("")
	print("Run `rbxm-kit <command> --help` for a command's options.")
end

local name = process.args[1]
if name == "--version" or name == "-V" then
	print(VERSION)
	process.exit(0)
end
if name == nil or name == "--help" or name == "-h" or name == "help" then
	printUsage()
	process.exit(if name == nil then 1 else 0)
end

local command = COMMANDS[name :: string]
if not command then
	print(`Unknown command: {name}\n`)
	printUsage()
	process.exit(1)
end

command.run(table.move(process.args, 2, #process.args, 1, {}))
