--[[
	Configure a repository so Git shows `.rbxm` and `.rbxl` changes as readable text.

	Writes a `diff.rbxm` driver into the target repository's local Git config (not a tracked file),
	pointing at this checkout's `bin/textconv.luau` and the absolute Lune executable, because Git
	runs textconv from its own shell where tool shims may not resolve. Rerun it after moving this
	checkout or upgrading Lune.

	The repository opts in per file type through its tracked `.gitattributes`, for example:

		*.rbxm filter=lfs diff=rbxm merge=lfs -text

	Usage:
		lune run bin/install_diff <repo-path>
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local repoPath = process.args[1]
if not repoPath or repoPath == "--help" or repoPath == "-h" then
	print("Usage: lune run bin/install_diff <repo-path>")
	process.exit(if repoPath then 0 else 1)
end

local function forwardSlashes(path: string): string
	return (string.gsub(path, "\\", "/"))
end

local function exec(command: string, arguments: { string }, cwd: string?): string
	local result = process.exec(command, arguments, { cwd = cwd })
	if not result.ok then
		print(`Error: {command} {table.concat(arguments, " ")} failed\n{result.stderr}`)
		process.exit(1)
	end
	return (string.gsub(result.stdout, "%s+$", ""))
end

-- Lune reports the running chunk's absolute path, so this works from any working directory.
local scriptPath = forwardSlashes(debug.info(1, "s"))
local kitRoot = string.match(scriptPath, "^(.*)/bin/[^/]+$")
local textconvPath = `{kitRoot}/bin/textconv.luau`
if not kitRoot or not fs.isFile(textconvPath) then
	print(`Error: could not locate bin/textconv.luau next to {scriptPath}`)
	process.exit(1)
end

local lunePath = forwardSlashes(exec("mise", { "which", "lune" }, kitRoot))
local targetRoot = forwardSlashes(exec("git", { "rev-parse", "--show-toplevel" }, repoPath))

local command = `"{lunePath}" run "{textconvPath}"`
exec("git", { "config", "--local", "diff.rbxm.textconv", command }, targetRoot)
exec("git", { "config", "--local", "diff.rbxm.cachetextconv", "true" }, targetRoot)
print(`Configured diff.rbxm in {targetRoot}:`)
print(`  textconv = {command}`)

local attributesPath = `{targetRoot}/.gitattributes`
local attributes = if fs.isFile(attributesPath) then fs.readFile(attributesPath) else ""
local missing = {}
for _, pattern in { "*.rbxm", "*.rbxl" } do
	local escaped = string.gsub(pattern, "[%*%.]", "%%%0")
	local line = string.match(attributes, `\n{escaped}[^\n]*`) or string.match(attributes, `^{escaped}[^\n]*`)
	if not line or not string.find(line, "diff=rbxm", 1, true) then
		table.insert(missing, pattern)
	end
end

if #missing > 0 then
	print(`\n.gitattributes does not route {table.concat(missing, " or ")} to this driver yet. Add diff=rbxm, e.g.:`)
	for _, pattern in missing do
		print(`  {pattern} filter=lfs diff=rbxm merge=lfs -text`)
	end
end
