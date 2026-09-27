--[[
	Print a model's hierarchy, total instance count, and counts grouped by class.

	Ported from Rensselaer's `.lune/demos/rbxm/inspectModel.luau`.
]]

local process = require("@lune/process")

local ModelIo = require("../src/model_io")

local function printUsage()
	print("Usage: lune run bin/inspect <path-to-model.rbxm>")
end

local modelPath = process.args[1]
if not modelPath or modelPath == "--help" or modelPath == "-h" then
	printUsage()
	process.exit(if modelPath then 0 else 1)
end

local roots = ModelIo.read(modelPath)
local instanceCount = 0
local classCounts: { [string]: number } = {}

local function describe(instance): string
	return `{instance.ClassName} {string.format("%q", instance.Name)}`
end

local function printTree(instance, prefix: string, isLast: boolean)
	instanceCount += 1
	classCounts[instance.ClassName] = (classCounts[instance.ClassName] or 0) + 1

	local connector = if isLast then "\\-- " else "|-- "
	print(`{prefix}{connector}{describe(instance)}`)

	local children = instance:GetChildren()
	local childPrefix = `{prefix}{if isLast then "    " else "|   "}`
	for index, child in children do
		printTree(child, childPrefix, index == #children)
	end
end

print(modelPath)
for index, root in roots do
	printTree(root, "", index == #roots)
end

local classNames = {}
for className in classCounts do
	table.insert(classNames, className)
end
table.sort(classNames)

print(`\n{instanceCount} instances across {#classNames} classes:`)
for _, className in classNames do
	print(`  {className}: {classCounts[className]}`)
end
