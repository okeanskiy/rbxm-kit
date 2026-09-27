--[[
	Build the standalone `rbxm-kit` binary.

	Usage:
		lune run tools/build [--target <os-arch>] [--output <path>]

	Targets use `lune build`'s `os-arch` format, e.g. `windows-x86_64` or `macos-aarch64`, and
	default to the current system. The bundled source is written next to the binary for inspection.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Bundle = require("./bundle")

local target: string? = nil
local output: string? = nil

local index = 1
while index <= #process.args do
	local argument = process.args[index]
	if argument == "--target" then
		index += 1
		target = process.args[index]
	elseif argument == "--output" then
		index += 1
		output = process.args[index]
	else
		print(`Unexpected argument: {argument}`)
		process.exit(1)
	end
	index += 1
end

local isWindows = if target then string.find(target, "windows", 1, true) ~= nil else process.os == "windows"
local binary = output or `out/build/rbxm-kit{if isWindows then ".exe" else ""}`
local directory = string.match(binary, "^(.*)[/\\][^/\\]+$") or "."
if not fs.isDir(directory) then
	fs.writeDir(directory)
end

local bundled = `{directory}/rbxm-kit.bundle.luau`
fs.writeFile(bundled, Bundle.bundle("bin/rbxm-kit.luau"))

local arguments = { "build", bundled, "--output", binary }
if target then
	table.insert(arguments, "--target")
	table.insert(arguments, target)
end
local result = process.exec("lune", arguments, { stdio = "forward" })
if not result.ok then
	process.exit(result.code)
end
print(`Built {binary}`)
