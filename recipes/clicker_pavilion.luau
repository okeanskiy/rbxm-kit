--[[
	Rest pavilion for the roblox-project-template clicker world.

	Sits on open ground southwest of the click pedestal, clear of the existing stations.

	Usage:
		lune run recipes/clicker_pavilion <output.rbxm>

	For the template, the output is `src/Workspace/ClickerWorld/RestPavilion.rbxm`.
]]

local process = require("@lune/process")

local Kit = require("../src/kit")

local Build, Check, ModelIo, Place = Kit.Build, Kit.Check, Kit.ModelIo, Kit.Place
local Color3, Enum, Vector3 = Kit.Color3, Kit.Enum, Kit.Vector3

local output = process.args[1]
if not output then
	print("Usage: lune run recipes/clicker_pavilion <output.rbxm>")
	process.exit(1)
end

local CENTER = Vector3.new(-26, 0, 22)
local SIZE, PILLAR_HEIGHT = 14, 9

local stone = { Material = Enum.Material.Cobblestone, Color = Color3.fromRGB(128, 124, 116) }
local wood = { Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(124, 92, 64) }

local function styled(style: { [string]: any }, props: { [string]: any }): { [string]: any }
	local merged = table.clone(style)
	for key, value in props do
		merged[key] = value
	end
	return merged
end

local floor = Build.part(styled(stone, { Name = "Floor", Size = Vector3.new(SIZE, 1, SIZE) }))
Place.moveTo(floor, CENTER + Vector3.new(0, 0.5, 0))

-- One pillar per corner, inset so the pillars sit fully on the floor.
local pillars = {}
for index, position in Place.grid(2, 2, SIZE - 2, CENTER) do
	local pillar = Build.part(styled(wood, { Name = `Pillar{index}`, Size = Vector3.new(1, PILLAR_HEIGHT, 1) }))
	Place.onTopOf(pillar, floor)
	Place.moveBy(pillar, position - CENTER)
	table.insert(pillars, pillar)
end
local frame = Build.model("Pillars", pillars)

local roof = Build.part(styled(wood, { Name = "Roof", Size = Vector3.new(SIZE + 2, 1, SIZE + 2) }))
Place.onTopOf(roof, frame)

local benches = {}
for index, side in { -1, 1 } do
	local bench = Build.part(styled(wood, { Name = `Bench{index}`, Size = Vector3.new(8, 1.5, 2) }))
	Place.onTopOf(bench, floor)
	Place.offset(bench, 0, 0, side * (SIZE / 2 - 3))
	table.insert(benches, bench)
end

local pavilion = Build.model("RestPavilion", { floor, frame, roof, Build.model("Benches", benches) }, {
	Attributes = { Recipe = "rbxm-kit/recipes/clicker_pavilion" },
})

local issues = Check.run({ pavilion }, { maxParts = 32 })
for _, issue in issues do
	print(`[{issue.kind}] {issue.message}`)
end
if #issues > 0 then
	print("Not writing a model that fails its checks.")
	process.exit(1)
end

ModelIo.write(output, { pavilion })
print(`Wrote {output}`)
