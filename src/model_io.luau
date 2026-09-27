--!strict

--[[
	Read and write Roblox model and place files.

	Reads resolve Git LFS pointers from the current repository's local LFS store, so a model can be
	read from any revision (`git show rev:path`) or from a checkout where LFS content is not
	smudged. Nothing here executes scripts stored in a model.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local stdio = require("@lune/stdio")

local ModelIo = {}

local LFS_POINTER_HEADER = "version https://git-lfs.github.com/spec/v1"

function ModelIo.fail(message: string): never
	stdio.ewrite(`Error: {message}\n`)
	process.exit(1)
	error(message)
end

local function trim(value: string): string
	return (string.gsub(string.gsub(value, "^%s+", ""), "%s+$", ""))
end

local function runGit(arguments: { string }): string
	local result = process.exec("git", arguments)
	if not result.ok then
		local detail = trim(result.stderr or "")
		ModelIo.fail(if detail == "" then `git {table.concat(arguments, " ")} failed` else detail)
	end
	return result.stdout
end

local gitCommonDirectory: string? = nil

local function getGitLfsObjectPath(oid: string): string
	if not gitCommonDirectory then
		gitCommonDirectory = trim(runGit({ "rev-parse", "--git-common-dir" }))
	end
	return `{gitCommonDirectory}/lfs/objects/{string.sub(oid, 1, 2)}/{string.sub(oid, 3, 4)}/{oid}`
end

--- Replace a Git LFS pointer with the object it points to. Other contents are returned unchanged.
function ModelIo.resolveLfs(contents: string, label: string): string
	local isLfsPointer = string.sub(contents, 1, #LFS_POINTER_HEADER) == LFS_POINTER_HEADER
	local oid = if isLfsPointer then string.match(contents, "oid sha256:([%da-f]+)") else nil
	if not oid then
		return contents
	end

	local objectPath = getGitLfsObjectPath(oid)
	if not fs.isFile(objectPath) then
		ModelIo.fail(`Git LFS object {oid} for {label} is not available locally. Fetch the revision's LFS objects and try again.`)
	end
	return fs.readFile(objectPath)
end

--- Read a file from disk, resolving an LFS pointer. Returns the contents and a display label.
function ModelIo.readLocal(path: string): (string, string)
	if not fs.isFile(path) then
		ModelIo.fail(`Model file not found: {path}`)
	end
	return ModelIo.resolveLfs(fs.readFile(path), path), path
end

--- Read a repository path at a Git revision, resolving an LFS pointer.
function ModelIo.readGit(revision: string, path: string): (string, string)
	local gitPath = string.gsub(path, "\\", "/")
	local label = `{revision}:{gitPath}`
	return ModelIo.resolveLfs(runGit({ "show", label }), label), label
end

local function isPlacePath(path: string): boolean
	return string.match(string.lower(path), "%.rbxlx?$") ~= nil
end

--- Deserialize contents into root instances. Places yield the DataModel's children.
function ModelIo.deserialize(contents: string, label: string): { Instance }
	local success, roots = pcall(function(): { Instance }
		if isPlacePath(label) then
			return roblox.deserializePlace(contents):GetChildren()
		end
		return roblox.deserializeModel(contents)
	end)
	if not success then
		ModelIo.fail(`Unable to deserialize {label}: {tostring(roots)}`)
	end
	return roots :: { Instance }
end

--- Read and deserialize a model or place file from disk.
function ModelIo.read(path: string): { Instance }
	local contents, label = ModelIo.readLocal(path)
	return ModelIo.deserialize(contents, label)
end

--- Serialize instances as a model. A `.rbxmx` path is written as XML, anything else as binary.
function ModelIo.write(path: string, instances: { Instance })
	local xml = string.match(string.lower(path), "%.rbxmx$") ~= nil
	local directory = string.match(path, "^(.*)[/\\][^/\\]+$")
	if directory and directory ~= "" and not fs.isDir(directory) then
		fs.writeDir(directory)
	end
	fs.writeFile(path, roblox.serializeModel(instances, xml))
end

return ModelIo
