--[[
	Example recipe: a small open-front shelter built entirely from relative placement.

	Recipes are optional, saved generator scripts. The `.rbxm` they write is what gets committed
	to a game repository; the recipe stays here so the model can be regenerated or tweaked later.

	Usage:
		lune run recipes/example_shelter [output.rbxm]
]]

local process = require("@lune/process")

local Kit = require("../src/kit")

local Build, Check, ModelIo, Place = Kit.Build, Kit.Check, Kit.ModelIo, Kit.Place
local Color3, Enum, Vector3 = Kit.Color3, Kit.Enum, Kit.Vector3

local output = process.args[1] or "out/example_shelter.rbxm"

local WIDTH, DEPTH, HEIGHT, THICKNESS = 16, 12, 9, 1
local wood = { Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(124, 92, 64) }

local function slab(name: string, size: Vector3, style: { [string]: any }): Instance
	local props = table.clone(style)
	props.Name = name
	props.Size = size
	return Build.part(props)
end

local floor = slab("Floor", Vector3.new(WIDTH, THICKNESS, DEPTH), { Material = Enum.Material.Concrete, Color = Color3.fromRGB(150, 150, 150) })
Place.moveTo(floor, Vector3.new(0, THICKNESS / 2, 0))

-- Walls stand on the floor, inset by their thickness so they do not overhang its edges.
local backWall = slab("BackWall", Vector3.new(WIDTH, HEIGHT, THICKNESS), wood)
Place.onTopOf(backWall, floor)
Place.offset(backWall, 0, 0, -(DEPTH - THICKNESS) / 2)

local leftWall = slab("LeftWall", Vector3.new(THICKNESS, HEIGHT, DEPTH - THICKNESS), wood)
Place.onTopOf(leftWall, floor)
Place.offset(leftWall, -(WIDTH - THICKNESS) / 2, 0, THICKNESS / 2)

local rightWall = slab("RightWall", Vector3.new(THICKNESS, HEIGHT, DEPTH - THICKNESS), wood)
Place.onTopOf(rightWall, floor)
Place.offset(rightWall, (WIDTH - THICKNESS) / 2, 0, THICKNESS / 2)

local walls = Build.model("Walls", { backWall, leftWall, rightWall })

local roof = slab("Roof", Vector3.new(WIDTH + 2, THICKNESS, DEPTH + 2), { Material = Enum.Material.Slate, Color = Color3.fromRGB(70, 70, 76) })
Place.onTopOf(roof, walls)

local bench = slab("Bench", Vector3.new(6, 1.5, 2), wood)
Place.onTopOf(bench, floor)
Place.against(bench, backWall, "+Z", 0.5)

local shelter = Build.model("ExampleShelter", { floor, walls, roof, bench }, {
	Attributes = { Recipe = "rbxm-kit/recipes/example_shelter" },
})

local issues = Check.run({ shelter })
for _, issue in issues do
	print(`[{issue.kind}] {issue.message}`)
end
if #issues > 0 then
	print("Not writing a model that fails its checks.")
	process.exit(1)
end

ModelIo.write(output, { shelter })
print(`Wrote {output}`)
