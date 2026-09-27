--[[
	Configure a repository so Git shows `.rbxm` and `.rbxl` changes as readable text.

	Writes a `diff.rbxm` driver into the target repository's local Git config (not a tracked file).
	Git runs the driver from the repository root through its own shell, so the command must resolve
	there. The default assumes `rbxm-kit` is on PATH; a repository that pins the kit with mise should
	pass `--command "mise exec -- rbxm-kit textconv"` so the pinned version is used.

	Each run also clears Git's cached renderings, so rerun it after updating the kit.

	The repository opts in per file type through its tracked `.gitattributes`, for example:

		*.rbxm filter=lfs diff=rbxm merge=lfs -text
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local DEFAULT_COMMAND = "rbxm-kit textconv"

local function printUsage()
	print("Usage: rbxm-kit install-diff <repo-path> [--command <textconv command>]")
	print(`  --command  Command Git runs to render a model (default: "{DEFAULT_COMMAND}")`)
end

local function exec(command: string, arguments: { string }, cwd: string?): string
	local result = process.exec(command, arguments, { cwd = cwd })
	if not result.ok then
		print(`Error: {command} {table.concat(arguments, " ")} failed\n{result.stderr}`)
		process.exit(1)
	end
	return (string.gsub(result.stdout, "%s+$", ""))
end

return function(args: { string })
	local repoPath: string? = nil
	local command = DEFAULT_COMMAND

	local index = 1
	while index <= #args do
		local argument = args[index]
		if argument == "--help" or argument == "-h" then
			printUsage()
			process.exit(0)
		elseif argument == "--command" then
			index += 1
			command = args[index]
			if not command or command == "" then
				print("--command expects a value")
				process.exit(1)
			end
		elseif repoPath == nil then
			repoPath = argument
		else
			print(`Unexpected argument: {argument}`)
			printUsage()
			process.exit(1)
		end
		index += 1
	end

	if repoPath == nil then
		printUsage()
		process.exit(1)
	end

	local targetRoot = (string.gsub(exec("git", { "rev-parse", "--show-toplevel" }, repoPath), "\\", "/"))

	exec("git", { "config", "--local", "diff.rbxm.textconv", command }, targetRoot)
	exec("git", { "config", "--local", "diff.rbxm.cachetextconv", "true" }, targetRoot)
	-- Cached renderings come from whichever kit version produced them. The ref is absent on first
	-- install, so a failure here is expected and ignored.
	process.exec("git", { "update-ref", "-d", "refs/notes/textconv/rbxm" }, { cwd = targetRoot })
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
end
