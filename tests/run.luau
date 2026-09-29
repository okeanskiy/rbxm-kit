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

local function overlapCount(issues: { Check.Issue }): number
	local count = 0
	for _, issue in issues do
		if issue.kind == "overlap" then
			count += 1
		end
	end
	return count
end

test("check measures rotated parts by their own boxes", function()
	-- Two boards turned 45 degrees and set side by side: their outer boxes overlap, the boards don't.
	local turn = Kit.CFrame.Angles(0, math.rad(45), 0)
	local normal = turn.LookVector
	local near = Build.part({ Name = "Near", Size = Vector3.new(10, 2, 1), CFrame = Kit.CFrame.new(0, 1, 0) * turn })
	local far = Build.part({ Name = "Far", Size = Vector3.new(10, 2, 1), CFrame = Kit.CFrame.new(normal * 1.5 + Vector3.new(0, 1, 0)) * turn })
	assert(overlapCount(Check.run({ Build.folder("Scene", { near, far }) })) == 0, "side by side boards overlap")

	-- Crossed through each other, they do: lifting one board its own height parts them soonest.
	local across = Build.part({ Name = "Across", Size = Vector3.new(10, 2, 1), CFrame = Kit.CFrame.new(0, 1, 0) * Kit.CFrame.Angles(0, math.rad(-45), 0) })
	local issues = Check.run({ Build.folder("Scene", { near, across }) })
	assert(overlapCount(issues) == 1, `crossed boards: expected 1 overlap, got {overlapCount(issues)}`)
	assert(string.find(issues[1].message, "by 2.00 studs", 1, true), `depth: {issues[1].message}`)
end)

test("check can let each model's own parts overlap", function()
	local a1 = block("A1", Vector3.new(4, 1, 4), Vector3.new(0, 0.5, 0))
	local a2 = block("A2", Vector3.new(2, 2, 2), Vector3.new(0, 1, 0))
	local b1 = block("B1", Vector3.new(4, 1, 4), Vector3.new(3, 0.5, 0))
	local loose = block("Loose", Vector3.new(4, 1, 4), Vector3.new(6, 0.5, 0))
	local scene = Build.folder("Scene", { Build.model("A", { a1, a2 }), Build.model("B", { b1 }), loose })
	local all = Check.run({ scene })
	assert(overlapCount(all) == 3, `every pair: expected 3 overlaps, got {overlapCount(all)}`)
	local between = Check.run({ scene }, { betweenModels = true })
	assert(overlapCount(between) == 2, `between models: expected 2 overlaps, got {overlapCount(between)}`)
	for _, issue in between do
		assert(not string.find(issue.message, "A2", 1, true), `A's own parts reported: {issue.message}`)
		assert(issue.where[1] == "Scene" and issue.where[2] == "Scene", `where: {table.concat(issue.where, ", ")}`)
	end
end)

test("check leaves terrain out", function()
	local terrain = Build.new("Terrain", { Size = Vector3.new(2048, 64, 2048) })
	local house = block("House", Vector3.new(20, 10, 20), Vector3.new(0, 5, 0))
	local issues, totals = Check.run({ Build.new("Workspace", {}, { terrain, house }) })
	assert(#issues == 0, `terrain reported: {issues[1] and issues[1].message}`)
	assert(totals.parts == 1, `expected 1 part, got {totals.parts}`)
end)

test("check sweeps a large model instead of testing every pair", function()
	-- 20,000 cubes a stud apart, and ten more sunk into ten of them. Testing every pair would take
	-- 200 million box tests.
	local cubes = {}
	for x = 1, 200 do
		for z = 1, 100 do
			table.insert(cubes, block(`Cube{x}_{z}`, Vector3.new(1, 1, 1), Vector3.new(x * 2, 0.5, z * 2)))
		end
	end
	for k = 1, 10 do
		table.insert(cubes, block(`Sunk{k}`, Vector3.new(1, 1, 1), Vector3.new(k * 20 + 0.5, 0.5, 40.5)))
	end
	local started = os.clock()
	local issues = Check.run({ Build.folder("Grid", cubes) })
	local elapsed = os.clock() - started
	assert(overlapCount(issues) == 10, `expected 10 overlaps, got {overlapCount(issues)}`)
	assert(elapsed < 10, `checking 20,010 parts took {elapsed} seconds`)
end)

test("check lists a long report's first issues and counts the rest by where they are", function()
	local north, south = {}, {}
	for k = 1, 30 do
		table.insert(north, block(`N{k}`, Vector3.new(2, 2, 2), Vector3.new(k * 10, 1, 0)))
		table.insert(north, block(`NSunk{k}`, Vector3.new(2, 2, 2), Vector3.new(k * 10 + 1, 1, 0)))
		table.insert(south, block(`S{k}`, Vector3.new(2, 2, 2), Vector3.new(k * 10, 1, 50)))
		table.insert(south, block(`SSunk{k}`, Vector3.new(2, 2, 2), Vector3.new(k * 10 + 1, 1, 50)))
	end
	local path = `{SCRATCH}/long_report.rbxm`
	ModelIo.write(path, { Build.folder("Root", { Build.folder("North", north), Build.folder("South", south) }) })
	local result = lune({ "run", "bin/rbxm-kit", "check", path, "--limit", "5" })
	assert(not result.ok, "check exits non-zero on issues")
	for _, expected in { "... and 55 more", "Issues by where they are:", "30  [overlap] Root.North  /  Root.North", "60 issue(s) found." } do
		assert(string.find(result.stdout, expected, 1, true), `report is missing {expected}:\n{result.stdout}`)
	end
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
	assert(string.find(run({ "--version" }), "0.1.1", 1, true), "version")
	assert(string.find(run({ "inspect", absoluteModel }), 'Part "Pillar"', 1, true), "inspect")
	assert(string.find(run({ "check", absoluteModel }), "No issues found", 1, true), "check")
	assert(string.find(run({ "textconv", absoluteModel }), ".Size = 1, 6, 1", 1, true), "textconv")
	assert(string.find(run({ "diff", absoluteModel, absoluteModel }), "No differences detected", 1, true), "diff")
end)

test("install-diff writes an unquoted multi-word command into a repository", function()
	local repo = `{SCRATCH}/repo`
	fs.writeDir(repo)
	assert(process.exec("git", { "init", "-q" }, { cwd = repo }).ok, "git init")
	fs.writeFile(`{repo}/.gitattributes`, "*.rbxm diff=rbxm\n*.rbxl diff=rbxm\n")
	local result = lune({ "run", "bin/rbxm-kit", "install-diff", repo, "--command", "mise", "exec", "--", "rbxm-kit", "textconv" })
	assert(result.ok, `install-diff failed: {result.stdout}{result.stderr}`)
	local configured = process.exec("git", { "config", "--local", "--get", "diff.rbxm.textconv" }, { cwd = repo })
	assert(string.gsub(configured.stdout, "%s+$", "") == "mise exec -- rbxm-kit textconv", `configured: {configured.stdout}`)
	assert(not string.find(result.stdout, "does not route", 1, true), "gitattributes check")
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
