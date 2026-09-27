--[[
	Run offline sanity checks on a model or place: overlapping collidable parts, unanchored parts,
	and optional extent and part-count budgets. Exits non-zero when any issue is found.
]]

local process = require("@lune/process")

local Check = require("../check")
local ModelIo = require("../model_io")

return function(args: { string })
	local function printUsage()
		print("Usage: rbxm-kit check <model.rbxm> [options]")
		print("")
		print("Options:")
		print("  --tolerance <studs>   Overlap depth tolerated before parts intersect (default 0.01)")
		print("  --max-extent <studs>  Fail when a part reaches further than this from the origin")
		print("  --max-parts <count>   Fail when the model has more BaseParts than this")
		print("  --allow-unanchored    Do not report unanchored parts")
	end

	local path: string? = nil
	local options: Check.Options = {}

	local index = 1
	local function numberArgument(flag: string): number
		index += 1
		local value = tonumber(args[index])
		if value == nil then
			print(`{flag} expects a number`)
			process.exit(1)
		end
		return value :: number
	end

	while index <= #args do
		local argument = args[index]
		if argument == "--help" or argument == "-h" then
			printUsage()
			process.exit(0)
		elseif argument == "--tolerance" then
			options.overlapTolerance = numberArgument(argument)
		elseif argument == "--max-extent" then
			options.maxExtent = numberArgument(argument)
		elseif argument == "--max-parts" then
			options.maxParts = numberArgument(argument)
		elseif argument == "--allow-unanchored" then
			options.requireAnchored = false
		elseif path == nil then
			path = argument
		else
			print(`Unexpected argument: {argument}`)
			printUsage()
			process.exit(1)
		end
		index += 1
	end

	if path == nil then
		printUsage()
		process.exit(1)
	end

	local issues, totals = Check.run(ModelIo.read(path :: string), options)
	print(`{path}: {totals.instances} instances, {totals.parts} BaseParts`)
	for _, issue in issues do
		print(`  [{issue.kind}] {issue.message}`)
	end
	print(if #issues == 0 then "No issues found." else `{#issues} issue(s) found.`)
	process.exit(if #issues == 0 then 0 else 1)
end
