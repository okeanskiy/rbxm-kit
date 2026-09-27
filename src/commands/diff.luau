--[[
	Compare two Roblox model files without opening Studio or executing scripts stored in them.

	Summarizes hierarchy and class-count changes, selected serialized properties, attributes,
	CollectionService tags, and embedded script source. Paths are counted rather than treated as
	unique identifiers because Roblox allows same-named siblings: 28 added identical `DoorStep`
	models are reported as one path with a `+28` count.

	Ported from Rensselaer's `.lune/demos/rbxm/diffModels.luau`.
]]

local process = require("@lune/process")

local ModelIo = require("../model_io")
local Properties = require("../properties")

return function(args: { string })
	local SCRIPT_CLASSES = Properties.SCRIPT_CLASSES
	local SUMMARY_PROPERTIES = Properties.SUMMARY_PROPERTIES
	local sortedKeys = Properties.sortedKeys
	local readLocalModel = ModelIo.readLocal
	local readGitModel = ModelIo.readGit

	local function printUsage()
		print("Compare two local model files:")
		print("  rbxm-kit diff <before.rbxm> <after.rbxm> [--full]")
		print("")
		print("Compare a model stored at two Git revisions (including Git LFS models):")
		print("  rbxm-kit diff --git <before-ref> <after-ref> <repo-path> [--full]")
		print("")
		print("Options:")
		print("  --full  Print every changed property and the complete changed portions of scripts")
	end

	local function collect(contents: string, label: string)
		local recordsByPath: { [string]: { any } } = {}
		local classCounts: { [string]: number } = {}
		local scriptsByPath: { [string]: { string } } = {}
		local instanceCount = 0

		local function visit(instance: Instance, parentPath: string)
			instanceCount += 1
			classCounts[instance.ClassName] = (classCounts[instance.ClassName] or 0) + 1

			local segment = Properties.describe(instance)
			local path = if parentPath == "" then segment else `{parentPath}/{segment}`
			local properties = Properties.createProperties(instance)
			local record = {
				path = path,
				properties = properties,
				fingerprint = Properties.createFingerprint(properties),
			}
			if not recordsByPath[path] then
				recordsByPath[path] = {}
			end
			table.insert(recordsByPath[path], record)

			if SCRIPT_CLASSES[instance.ClassName] then
				if not scriptsByPath[path] then
					scriptsByPath[path] = {}
				end
				local success, source = pcall(function()
					return (instance :: any).Source :: string
				end)
				table.insert(scriptsByPath[path], if success then source else "")
			end

			for _, child in instance:GetChildren() do
				visit(child, path)
			end
		end

		for _, root in ModelIo.deserialize(contents, label) do
			visit(root, "")
		end

		return {
			classCounts = classCounts,
			instanceCount = instanceCount,
			recordsByPath = recordsByPath,
			scriptsByPath = scriptsByPath,
		}
	end

	local function copyArray(values: { any }): { any }
		local result = {}
		for _, value in values do
			table.insert(result, value)
		end
		return result
	end

	local function findUnmatched(beforeRecords: { any }, afterRecords: { any }): ({ any }, { any })
		local afterByFingerprint: { [string]: { any } } = {}
		for _, record in afterRecords do
			if not afterByFingerprint[record.fingerprint] then
				afterByFingerprint[record.fingerprint] = {}
			end
			table.insert(afterByFingerprint[record.fingerprint], record)
		end

		local unmatchedBefore = {}
		for _, record in beforeRecords do
			local matches = afterByFingerprint[record.fingerprint]
			if matches and #matches > 0 then
				table.remove(matches)
			else
				table.insert(unmatchedBefore, record)
			end
		end

		local unmatchedAfter = {}
		for _, matches in afterByFingerprint do
			for _, record in matches do
				table.insert(unmatchedAfter, record)
			end
		end
		return unmatchedBefore, unmatchedAfter
	end

	local function getAllPaths(before: any, after: any): { string }
		local paths: { [string]: boolean } = {}
		for path in before.recordsByPath do
			paths[path] = true
		end
		for path in after.recordsByPath do
			paths[path] = true
		end
		return sortedKeys(paths)
	end

	local function signed(number: number): string
		return if number > 0 then `+{number}` else tostring(number)
	end

	local function printClassChanges(before: any, after: any)
		local classes: { [string]: boolean } = {}
		for className in before.classCounts do
			classes[className] = true
		end
		for className in after.classCounts do
			classes[className] = true
		end

		local changes = {}
		for _, className in sortedKeys(classes) do
			local difference = (after.classCounts[className] or 0) - (before.classCounts[className] or 0)
			if difference ~= 0 then
				table.insert(changes, `  {signed(difference)} {className}`)
			end
		end

		print("\nClass counts:")
		if #changes == 0 then
			print("  unchanged")
		else
			for _, change in changes do
				print(change)
			end
		end
	end

	local function isSummaryProperty(name: string): boolean
		return SUMMARY_PROPERTIES[name] == true or string.sub(name, 1, 10) == "Attribute."
	end

	local function printAddedDetails(records: { any }, full: boolean)
		if #records == 0 then
			return
		end

		local common: { [string]: string } = {}
		for name, value in records[1].properties do
			common[name] = value
		end
		for index = 2, #records do
			for name, value in common do
				if records[index].properties[name] ~= value then
					common[name] = nil
				end
			end
		end

		local commonParts = {}
		for _, name in sortedKeys(common) do
			if full or isSummaryProperty(name) then
				table.insert(commonParts, `{name}={common[name]}`)
			end
		end
		if #commonParts > 0 then
			print(`    common: {table.concat(commonParts, ", ")}`)
		end

		local varyingProperties = { "CFrame", "Color", "MeshId", "Size", "Texture", "TextureID" }
		for _, name in varyingProperties do
			if common[name] ~= nil then
				continue
			end
			local values: { [string]: boolean } = {}
			for _, record in records do
				local value = record.properties[name]
				if value ~= nil then
					values[value] = true
				end
			end
			local valueCount = 0
			for _ in values do
				valueCount += 1
			end
			if valueCount > 0 then
				print(`    varying: {name} has {valueCount} distinct values`)
			end
		end

		if full then
			for index, record in records do
				local parts = {}
				for _, name in sortedKeys(record.properties) do
					if name ~= "Source" then
						table.insert(parts, `{name}={record.properties[name]}`)
					end
				end
				print(`    [{index}] {table.concat(parts, ", ")}`)
			end
		end
	end

	local function propertyDifferences(beforeProperties: { [string]: string }, afterProperties: { [string]: string })
		local names: { [string]: boolean } = {}
		for name in beforeProperties do
			if name ~= "Source" then
				names[name] = true
			end
		end
		for name in afterProperties do
			if name ~= "Source" then
				names[name] = true
			end
		end

		local differences = {}
		for _, name in sortedKeys(names) do
			local beforeValue = beforeProperties[name]
			local afterValue = afterProperties[name]
			if beforeValue ~= afterValue then
				table.insert(differences, {
					name = name,
					before = beforeValue or "<unset>",
					after = afterValue or "<unset>",
				})
			end
		end
		return differences
	end

	local function differenceSignature(differences: { any }): string
		local parts = {}
		for _, difference in differences do
			table.insert(parts, `{difference.name}\0{difference.before}\0{difference.after}`)
		end
		return table.concat(parts, "\1")
	end

	local function printPropertyChanges(before: any, after: any, paths: { string }, full: boolean): number
		local groupedChanges: { [string]: { count: number, differences: { any }, path: string } } = {}
		local changeCount = 0

		for _, path in paths do
			local beforeRecords = before.recordsByPath[path] or {}
			local afterRecords = after.recordsByPath[path] or {}
			if #beforeRecords ~= #afterRecords then
				continue
			end

			local unmatchedBefore, unmatchedAfter = findUnmatched(beforeRecords, afterRecords)
			if #unmatchedBefore == 0 or #unmatchedBefore ~= #unmatchedAfter then
				continue
			end

			if #unmatchedBefore > 50 and not full then
				changeCount += #unmatchedBefore
				groupedChanges[`{path}\0bulk`] = {
					count = #unmatchedBefore,
					differences = {},
					path = path,
				}
				continue
			end

			local remainingAfter = copyArray(unmatchedAfter)
			for _, beforeRecord in unmatchedBefore do
				local bestIndex = 1
				local bestDifferences = propertyDifferences(beforeRecord.properties, remainingAfter[1].properties)
				for index = 2, #remainingAfter do
					local differences = propertyDifferences(beforeRecord.properties, remainingAfter[index].properties)
					if #differences < #bestDifferences then
						bestIndex = index
						bestDifferences = differences
					end
				end
				table.remove(remainingAfter, bestIndex)
				if #bestDifferences == 0 then
					continue
				end
				changeCount += 1
				local signature = `{path}\0{differenceSignature(bestDifferences)}`
				local group = groupedChanges[signature]
				if group then
					group.count += 1
				else
					groupedChanges[signature] = {
						count = 1,
						differences = bestDifferences,
						path = path,
					}
				end
			end
		end

		local groups = {}
		for _, group in groupedChanges do
			table.insert(groups, group)
		end
		table.sort(groups, function(a, b)
			return a.path < b.path
		end)

		print("\nProperties and metadata:")
		if #groups == 0 then
			print("  no changes detected on paths whose instance counts stayed stable")
			return changeCount
		end

		local limit = if full then #groups else math.min(#groups, 30)
		for index = 1, limit do
			local group = groups[index]
			print(`  ~{group.count} {group.path}`)
			if #group.differences == 0 then
				print("    multiple property fingerprints changed; use --full to pair and display them")
			else
				for _, difference in group.differences do
					print(`    {difference.name}: {difference.before} -> {difference.after}`)
				end
			end
		end
		if limit < #groups then
			print(`  ... {#groups - limit} more change groups (use --full)`)
		end
		return changeCount
	end

	local function normalizeLines(source: string): { string }
		return string.split(string.gsub(source, "\r\n", "\n"), "\n")
	end

	local function printSourceChange(beforeSource: string, afterSource: string, full: boolean)
		local beforeLines = normalizeLines(beforeSource)
		local afterLines = normalizeLines(afterSource)
		local prefix = 0
		while prefix < #beforeLines and prefix < #afterLines and beforeLines[prefix + 1] == afterLines[prefix + 1] do
			prefix += 1
		end

		local suffix = 0
		while suffix < #beforeLines - prefix and suffix < #afterLines - prefix and beforeLines[#beforeLines - suffix] == afterLines[#afterLines - suffix] do
			suffix += 1
		end

		local removed = {}
		for index = prefix + 1, #beforeLines - suffix do
			table.insert(removed, beforeLines[index])
		end
		local added = {}
		for index = prefix + 1, #afterLines - suffix do
			table.insert(added, afterLines[index])
		end

		print(`    {#beforeLines} lines -> {#afterLines} lines; changed region starts at line {prefix + 1}`)
		local lineLimit = if full then math.max(#removed, #added) else 20
		for index = 1, math.min(#removed, lineLimit) do
			print(`    - {removed[index]}`)
		end
		for index = 1, math.min(#added, lineLimit) do
			print(`    + {added[index]}`)
		end
		if #removed > lineLimit or #added > lineLimit then
			print("      ... changed region truncated (use --full)")
		end
	end

	local function unmatchedStrings(beforeValues: { string }, afterValues: { string }): ({ string }, { string })
		local afterCounts: { [string]: number } = {}
		for _, value in afterValues do
			afterCounts[value] = (afterCounts[value] or 0) + 1
		end
		local beforeUnmatched = {}
		for _, value in beforeValues do
			local count = afterCounts[value] or 0
			if count > 0 then
				afterCounts[value] = count - 1
			else
				table.insert(beforeUnmatched, value)
			end
		end
		local afterUnmatched = {}
		for value, count in afterCounts do
			for _ = 1, count do
				table.insert(afterUnmatched, value)
			end
		end
		return beforeUnmatched, afterUnmatched
	end

	local function printScriptChanges(before: any, after: any, full: boolean): number
		local scriptPaths: { [string]: boolean } = {}
		for path in before.scriptsByPath do
			scriptPaths[path] = true
		end
		for path in after.scriptsByPath do
			scriptPaths[path] = true
		end

		local changes = 0
		local output = {}
		for _, path in sortedKeys(scriptPaths) do
			local beforeSources = before.scriptsByPath[path] or {}
			local afterSources = after.scriptsByPath[path] or {}
			local unmatchedBefore, unmatchedAfter = unmatchedStrings(beforeSources, afterSources)
			if #unmatchedBefore == 0 and #unmatchedAfter == 0 then
				continue
			end
			changes += math.max(#unmatchedBefore, #unmatchedAfter)
			table.insert(output, {
				after = unmatchedAfter,
				before = unmatchedBefore,
				path = path,
			})
		end

		print("\nEmbedded scripts:")
		if #output == 0 then
			print("  unchanged")
			return 0
		end

		for _, change in output do
			local paired = math.min(#change.before, #change.after)
			for index = 1, paired do
				print(`  ~ {change.path}`)
				printSourceChange(change.before[index], change.after[index], full)
			end
			for index = paired + 1, #change.before do
				print(`  - {change.path} ({#normalizeLines(change.before[index])} lines)`)
			end
			for index = paired + 1, #change.after do
				print(`  + {change.path} ({#normalizeLines(change.after[index])} lines)`)
			end
		end
		return changes
	end

	local arguments = {}
	local full = false
	for _, argument in args do
		if argument == "--full" then
			full = true
		elseif argument == "--help" or argument == "-h" then
			printUsage()
			process.exit(0)
		else
			table.insert(arguments, argument)
		end
	end

	local beforeContents: string
	local beforeLabel: string
	local afterContents: string
	local afterLabel: string

	if arguments[1] == "--git" then
		if #arguments ~= 4 then
			printUsage()
			process.exit(1)
		end
		beforeContents, beforeLabel = readGitModel(arguments[2], arguments[4])
		afterContents, afterLabel = readGitModel(arguments[3], arguments[4])
	else
		if #arguments ~= 2 then
			printUsage()
			process.exit(1)
		end
		beforeContents, beforeLabel = readLocalModel(arguments[1])
		afterContents, afterLabel = readLocalModel(arguments[2])
	end

	print(`Before: {beforeLabel}`)
	print(`After:  {afterLabel}`)

	local before = collect(beforeContents, beforeLabel)
	local after = collect(afterContents, afterLabel)
	local difference = after.instanceCount - before.instanceCount

	print(`\nInstances: {before.instanceCount} -> {after.instanceCount} ({signed(difference)})`)
	printClassChanges(before, after)

	local paths = getAllPaths(before, after)
	local hierarchyChangeCount = 0
	print("\nHierarchy:")
	for _, path in paths do
		local beforeRecords = before.recordsByPath[path] or {}
		local afterRecords = after.recordsByPath[path] or {}
		local pathDifference = #afterRecords - #beforeRecords
		if pathDifference == 0 then
			continue
		end
		hierarchyChangeCount += math.abs(pathDifference)
		print(`  {signed(pathDifference)} {path}`)
		if pathDifference > 0 then
			local _, unmatchedAfter = findUnmatched(beforeRecords, afterRecords)
			if #unmatchedAfter == pathDifference then
				printAddedDetails(unmatchedAfter, full)
			elseif full then
				print("    exact additions overlap property changes on other same-path instances")
			end
		end
	end
	if hierarchyChangeCount == 0 then
		print("  unchanged")
	end

	local propertyChangeCount = printPropertyChanges(before, after, paths, full)
	local scriptChangeCount = printScriptChanges(before, after, full)

	if hierarchyChangeCount == 0 and propertyChangeCount == 0 and scriptChangeCount == 0 then
		print("\nNo differences detected in the compared hierarchy, tracked properties, metadata, or scripts.")
	end
end
