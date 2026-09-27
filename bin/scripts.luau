--[[
	Print the source of every script in a model: the first 12 lines by default, or all of it.

	Ported from Rensselaer's `.lune/demos/rbxm/inspectScriptSources.luau`.
]]

local process = require("@lune/process")

local ModelIo = require("../src/model_io")
local Properties = require("../src/properties")

local PREVIEW_LINE_COUNT = 12
local SCRIPT_CLASSES = Properties.SCRIPT_CLASSES

local function printUsage()
	print("Usage: lune run bin/scripts <path-to-model.rbxm> [--full]")
	print("  default: print the first 12 lines of each script")
	print("  --full:  print the complete source of each script")
end

local modelPath = process.args[1]
local option = process.args[2]
if not modelPath or modelPath == "--help" or modelPath == "-h" then
	printUsage()
	process.exit(if modelPath then 0 else 1)
end

if option and option ~= "--full" then
	print(`Unknown option: {option}`)
	printUsage()
	process.exit(1)
end

local roots = ModelIo.read(modelPath)
local printFullSource = option == "--full"
local scriptCount = 0
local scriptsWithSourceCount = 0

local function printSource(instance, instancePath: string)
	scriptCount += 1

	local source = (instance :: any).Source :: string
	local normalizedSource = string.gsub(source, "\r\n", "\n")
	local lines = string.split(normalizedSource, "\n")
	if source ~= "" then
		scriptsWithSourceCount += 1
	end

	print(`\n[{instance.ClassName}] {instancePath}`)
	print(`{#source} bytes, {#lines} lines`)

	local displayedLineCount = if printFullSource then #lines else math.min(#lines, PREVIEW_LINE_COUNT)
	for lineNumber = 1, displayedLineCount do
		print(string.format("%4d | %s", lineNumber, lines[lineNumber]))
	end

	local omittedLineCount = #lines - displayedLineCount
	if omittedLineCount > 0 then
		print(`     | ... {omittedLineCount} more lines (use --full to print them)`)
	end
end

local function inspect(instance, instancePath: string)
	if SCRIPT_CLASSES[instance.ClassName] then
		printSource(instance, instancePath)
	end

	for _, child in instance:GetChildren() do
		inspect(child, `{instancePath}/{child.Name}`)
	end
end

print(modelPath)
for _, root in roots do
	inspect(root, root.Name)
end

print(`\nFound {scriptCount} scripts; {scriptsWithSourceCount} contain source.`)
