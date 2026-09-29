--[[
	Run offline sanity checks on a model or place: overlapping collidable parts, unanchored parts,
	and optional extent and part-count budgets. Exits non-zero when any issue is found.

	A long report lists its first issues, then counts the rest by kind and by the collections they
	sit in, so a place with thousands of expected contacts still reads at a glance.
]]

local process = require("@lune/process")

local Check = require("../check")
local ModelIo = require("../model_io")

local DEFAULT_LIMIT = 40
local GROUPS_SHOWN = 30

return function(args: { string })
	local function printUsage()
		print("Usage: rbxm-kit check <model.rbxm> [options]")
		print("")
		print("Options:")
		print("  --tolerance <studs>   Overlap depth tolerated before parts intersect (default 0.01)")
		print("  --between-models      Let each Model's own parts overlap; report overlaps between Models")
		print("  --max-extent <studs>  Fail when a part reaches further than this from the origin")
		print("  --max-parts <count>   Fail when the model has more BaseParts than this")
		print("  --allow-unanchored    Do not report unanchored parts")
		print(`  --limit <count>       List at most this many issues, then count the rest (default {DEFAULT_LIMIT})`)
		print("  --all                 List every issue")
	end

	local path: string? = nil
	local options: Check.Options = {}
	local limit = DEFAULT_LIMIT

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
		elseif argument == "--between-models" then
			options.betweenModels = true
		elseif argument == "--max-extent" then
			options.maxExtent = numberArgument(argument)
		elseif argument == "--max-parts" then
			options.maxParts = numberArgument(argument)
		elseif argument == "--allow-unanchored" then
			options.requireAnchored = false
		elseif argument == "--limit" then
			limit = numberArgument(argument)
		elseif argument == "--all" then
			limit = math.huge
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
	for position, issue in issues do
		if position > limit then
			break
		end
		print(`  [{issue.kind}] {issue.message}`)
	end
	if #issues > limit then
		print(`  ... and {#issues - limit} more`)
		local counts: { [string]: number } = {}
		local keys: { string } = {}
		for _, issue in issues do
			local key = `[{issue.kind}] {table.concat(issue.where, "  /  ")}`
			if counts[key] == nil then
				counts[key] = 0
				table.insert(keys, key)
			end
			counts[key] += 1
		end
		table.sort(keys, function(a: string, b: string): boolean
			if counts[a] ~= counts[b] then
				return counts[a] > counts[b]
			end
			return a < b
		end)
		print("")
		print("Issues by where they are:")
		for position, key in keys do
			if position > GROUPS_SHOWN then
				print(`  ... and {#keys - GROUPS_SHOWN} more places`)
				break
			end
			print(string.format("  %8d  %s", counts[key], key))
		end
	end
	print(if #issues == 0 then "No issues found." else `{#issues} issue(s) found.`)
	process.exit(if #issues == 0 then 0 else 1)
end
