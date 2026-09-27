--[[
	The kit's own tests. Run with `mise run test`.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local Kit = require("../src/kit")

local Build, Check, ModelIo, Place = Kit.Build, Kit.Check, Kit.ModelIo, Kit.Place
local Vector3 = Kit.Vector3

local SCRATCH = "out/test"

local cases: { { name: string, body: () -> () } } = {}
local function test(name: string, body: () -> ())
	table.insert(cases, { name = name, body = body })
end

local function near(actual: number, expected: number, label: string)
	if math.abs(actual - expected) > 1e-4 then
		error(`{label}: expected {expected}, got {actual}`, 2)
	end
end

local function nearVector(actual: Vector3, expected: Vector3, label: string)
	near(actual.X, expected.X, `{label}.X`)
	near(actual.Y, expected.Y, `{label}.Y`)
	near(actual.Z, expected.Z, `{label}.Z`)
end

local function block(name: string, size: Vector3, position: Vector3?): Instance
	local part = Build.part({ Name = name, Size = size })
	if position then
		Place.moveTo(part, position)
	end
	return part
end

local function lune(arguments: { string }): { ok: boolean, stdout: string, stderr: string }
	local result = process.exec(process.env.LUNE_EXECUTABLE or "lune", arguments)
	return { ok = result.ok, stdout = result.stdout, stderr = result.stderr }
end

test("onTopOf rests the bottom on the target's top and centers over it", function()
	local floor = block("Floor", Vector3.new(10, 1, 10), Vector3.new(3, 0.5, -2))
	local crate = block("Crate", Vector3.new(2, 2, 2))
	Place.onTopOf(crate, floor)
	local min = Place.bounds(crate)
	near(min.Y, 1, "crate bottom")
	nearVector(Place.center(crate), Vector3.new(3, 2, -2), "crate center")
end)

test("against aligns bottoms on horizontal sides and honors the gap", function()
	local floor = block("Floor", Vector3.new(10, 1, 10), Vector3.new(0, 0.5, 0))
	local wall = block("Wall", Vector3.new(1, 8, 10))
	Place.against(wall, floor, "+X", 0.5)
	local min, max = Place.bounds(wall)
	near(min.X, 5.5, "wall inner face")
	near(max.X, 6.5, "wall outer face")
	near(min.Y, 0, "wall bottom")
end)

test("moveBy translates every part in a model", function()
	local a = block("A", Vector3.new(1, 1, 1), Vector3.new(0, 0, 0))
	local b = block("B", Vector3.new(1, 1, 1), Vector3.new(4, 0, 0))
	local model = Build.model("Pair", { a, b })
	Place.moveTo(model, Vector3.new(10, 5, 0))
	nearVector((a :: any).CFrame.Position, Vector3.new(8, 5, 0), "a")
	nearVector((b :: any).CFrame.Position, Vector3.new(12, 5, 0), "b")
end)

test("grid and ring produce evenly spaced layouts", function()
	local grid = Place.grid(3, 2, 4)
	assert(#grid == 6, "grid count")
	nearVector(grid[1], Vector3.new(-4, 0, -2), "first grid cell")
	nearVector(grid[6], Vector3.new(4, 0, 2), "last grid cell")

	local ring = Place.ring(4, 10)
	assert(#ring == 4, "ring count")
	for index, cframe in ring do
		near(cframe.Position.Magnitude, 10, `ring[{index}] radius`)
		-- Facing outward: the look vector points away from the center.
		assert(cframe.LookVector:Dot(cframe.Position.Unit) > 0.99, `ring[{index}] faces outward`)
	end

	near(Place.snap(3.26, 0.5), 3.5, "snap")
end)

test("Position props set the CFrame position and keep rotation", function()
	local part = Build.part({ CFrame = Kit.CFrame.Angles(0, math.pi / 2, 0), Position = Vector3.new(1, 2, 3) })
	local cframe = (part :: any).CFrame
	nearVector(cframe.Position, Vector3.new(1, 2, 3), "position")
	nearVector(cframe.LookVector, Kit.CFrame.Angles(0, math.pi / 2, 0).LookVector, "rotation")
end)

test("check reports intersecting parts but not touching ones", function()
	local base = block("Base", Vector3.new(4, 1, 4), Vector3.new(0, 0.5, 0))
	local touching = block("Touching", Vector3.new(2, 2, 2))
	Place.onTopOf(touching, base)
	local sunk = block("Sunk", Vector3.new(2, 2, 2), Vector3.new(0, 1, 0))
	local issues = Check.run({ Build.model("Scene", { base, touching }) })
	assert(#issues == 0, `expected no issues, got {#issues}`)

	issues = Check.run({ Build.model("Scene", { base, touching, sunk }) })
	local overlaps = 0
	for _, issue in issues do
		if issue.kind == "overlap" then
			overlaps += 1
		end
	end
	assert(overlaps == 2, `expected Sunk to intersect Base and Touching, got {overlaps} overlaps`)
end)

test("check reports unanchored parts unless allowed", function()
	local loose = Build.part({ Name = "Loose", Anchored = false, Size = Vector3.new(1, 1, 1) })
	local issues = Check.run({ loose })
	assert(#issues == 1 and issues[1].kind == "unanchored", "unanchored part reported")
	issues = Check.run({ loose }, { requireAnchored = false })
	assert(#issues == 0, "unanchored part allowed")
end)

test("models round-trip through binary and XML files with attributes and tags", function()
	for _, extension in { "rbxm", "rbxmx" } do
		local path = `{SCRATCH}/roundtrip.{extension}`
		local part = Build.part({ Name = "Tagged", Size = Vector3.new(2, 3, 4), Attributes = { Health = 50 }, Tags = { "Breakable" } })
		ModelIo.write(path, { Build.model("Root", { part }) })
		local roots = ModelIo.read(path)
		local read = roots[1]:FindFirstChild("Tagged") :: any
		assert(read ~= nil, `{extension}: child survives`)
		nearVector(read.Size, Vector3.new(2, 3, 4), `{extension} size`)
		assert(read:GetAttribute("Health") == 50, `{extension}: attribute survives`)
		assert(read:HasTag("Breakable"), `{extension}: tag survives`)
	end
end)

test("the example recipe writes a model that passes its checks", function()
	local path = `{SCRATCH}/example_shelter.rbxm`
	local result = lune({ "run", "recipes/example_shelter", path })
	assert(result.ok, `recipe failed: {result.stdout}{result.stderr}`)
	local issues = Check.run(ModelIo.read(path))
	assert(#issues == 0, "recipe output has issues")
end)

test("textconv renders properties and script source as text", function()
	local script = Build.new("Script", { Name = "Door", Source = "print('open')\nreturn nil" })
	local path = `{SCRATCH}/textconv.rbxm`
	ModelIo.write(path, { Build.model("Root", { block("Frame", Vector3.new(4, 7, 1)), script }) })
	local result = lune({ "run", "bin/rbxm-kit", "textconv", path })
	assert(result.ok, `textconv failed: {result.stderr}`)
	for _, expected in { 'Model "Root"', 'Part "Frame"', ".Size = 4, 7, 1", 'Script "Door"', "| print('open')", "| return nil" } do
		assert(string.find(result.stdout, expected, 1, true), `textconv output is missing {expected}:\n{result.stdout}`)
	end
end)

test("diff reports a changed property between two models", function()
	local before = `{SCRATCH}/before.rbxm`
	local after = `{SCRATCH}/after.rbxm`
	ModelIo.write(before, { Build.model("Root", { block("Pillar", Vector3.new(1, 6, 1)) }) })
	ModelIo.write(after, { Build.model("Root", { block("Pillar", Vector3.new(1, 9, 1)) }) })
	local result = lune({ "run", "bin/rbxm-kit", "diff", before, after })
	assert(result.ok, `diff failed: {result.stderr}`)
	assert(string.find(result.stdout, "Pillar", 1, true), `diff does not mention the pillar:\n{result.stdout}`)
	assert(not string.find(result.stdout, "No differences detected", 1, true), "diff missed the size change")
end)

test("the standalone binary runs every command without the source tree", function()
	local binary = `{SCRATCH}/bin/rbxm-kit{if process.os == "windows" then ".exe" else ""}`
	local build = lune({ "run", "tools/build", "--output", binary })
	assert(build.ok, `build failed: {build.stdout}{build.stderr}`)

	local model = `{SCRATCH}/binary.rbxm`
	ModelIo.write(model, { Build.model("Root", { block("Pillar", Vector3.new(1, 6, 1)) }) })

	local root = string.gsub(process.cwd, "[/\\]+$", "")
	local absoluteBinary = `{root}/{binary}`

	local function run(arguments: { string }): string
		-- Run from outside the repository so nothing can resolve against the source files. The
		-- binary path is absolute because Linux resolves a relative one against the new cwd.
		local result = process.exec(absoluteBinary, arguments, { cwd = process.env.TEMP or process.env.TMPDIR or "/tmp" })
		assert(result.ok, `rbxm-kit {table.concat(arguments, " ")} failed: {result.stdout}{result.stderr}`)
		return result.stdout
	end

	local absoluteModel = `{root}/{model}`
	assert(string.find(run({ "--version" }), "0.1.0", 1, true), "version")
	assert(string.find(run({ "inspect", absoluteModel }), 'Part "Pillar"', 1, true), "inspect")
	assert(string.find(run({ "check", absoluteModel }), "No issues found", 1, true), "check")
	assert(string.find(run({ "textconv", absoluteModel }), ".Size = 1, 6, 1", 1, true), "textconv")
	assert(string.find(run({ "diff", absoluteModel, absoluteModel }), "No differences detected", 1, true), "diff")
end)

if fs.isDir(SCRATCH) then
	fs.removeDir(SCRATCH)
end
fs.writeDir(SCRATCH)

local failures = 0
for _, case in cases do
	local ok, err = pcall(case.body)
	if ok then
		stdio.write(`PASS  {case.name}\n`)
	else
		failures += 1
		stdio.write(`FAIL  {case.name}\n      {tostring(err)}\n`)
	end
end

stdio.write(`\n{#cases - failures} passed, {failures} failed\n`)
process.exit(if failures == 0 then 0 else 1)
