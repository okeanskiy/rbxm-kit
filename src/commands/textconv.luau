--[[
	Print a stable text rendering of a model or place, for use as a Git `textconv` driver.

	Git runs this on each side of a diff and diffs the text, so `git diff`, `git log -p`, and
	`git show` display `.rbxm` changes as readable hierarchy, property, and script-source lines
	instead of "Binary files differ". Git LFS pointers are resolved from the local LFS store.

	Configure a repository with `rbxm-kit install-diff <repo>`; see its usage for details.
	Use `rbxm-kit diff` for a summarized comparison instead of a line diff.
]]

local process = require("@lune/process")
local stdio = require("@lune/stdio")

local ModelIo = require("../model_io")
local Properties = require("../properties")

return function(args: { string })
	local path = args[1]
	if not path or path == "--help" or path == "-h" then
		print("Usage: rbxm-kit textconv <model.rbxm | place.rbxl>")
		process.exit(if path then 0 else 1)
	end

	-- Git's temporary files keep the original basename, so the extension still tells places apart.
	local contents = ModelIo.readLocal(path)
	local roots = ModelIo.deserialize(contents, path)

	local output: { string } = {}

	local function emit(line: string)
		table.insert(output, line)
	end

	local function render(instance: Instance, indent: string)
		emit(`{indent}{Properties.describe(instance)}`)

		local properties = Properties.createProperties(instance)
		local source = properties.Source
		properties.Source = nil
		for _, key in Properties.sortedKeys(properties) do
			emit(`{indent}  .{key} = {properties[key]}`)
		end

		if Properties.SCRIPT_CLASSES[instance.ClassName] then
			local rawSource = (instance :: any).Source :: string
			if source ~= nil and rawSource ~= "" then
				for _, line in string.split((string.gsub(rawSource, "\r\n", "\n")), "\n") do
					emit(`{indent}  | {line}`)
				end
			end
		end

		for _, child in instance:GetChildren() do
			render(child, `{indent}    `)
		end
	end

	for _, root in roots do
		render(root, "")
	end

	stdio.write(table.concat(output, "\n") .. "\n")
end
