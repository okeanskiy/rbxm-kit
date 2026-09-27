--[[
	Greybox of the Tidewater Cove island, inspired by Marco Island, Florida.

	Blocks out every zone from the design (docs/game-design.md in the game repository) at the right
	heights relative to the tide, so the layout can be walked and tuned before any art. Every piece
	is a simple part that an artist can replace zone by zone.

	Coordinates: north is -Z, the Gulf of Mexico is to the west (-X). The seabed is the game's
	baseplate, with its top at SEABED. The water surface moves between LOW_TIDE and HIGH_TIDE.

	Usage:
		lune run recipes/tidewater_island <output.rbxm>

	For the game, the output is `src/Workspace/Island.rbxm`.
]]

local process = require("@lune/process")

local Kit = require("../src/kit")

local Build, Check, ModelIo = Kit.Build, Kit.Check, Kit.ModelIo
local CFrame, Color3, Enum, Vector3 = Kit.CFrame, Kit.Color3, Kit.Enum, Kit.Vector3

local output = process.args[1]
if not output then
	print("Usage: lune run recipes/tidewater_island <output.rbxm>")
	process.exit(1)
end

-- Heights, matching src/shared/config/tide.luau in the game (mean 0, amplitude 1.5).
local SEABED = -6
local HIGH_TIDE = 1.5
local LOW_TIDE = -1.5
local DRY_SAND = 2.5 -- above high tide
local GRASS = 4
local MANGROVE_FLATS = 1.5 -- flooded only at the peak of high tide
local SANDBAR = -0.6 -- dry for the low part of the cycle
local SHOALS = -1.0 -- dry only near the bottom of low tide
local TIDE_POOL_SHELF = -0.8
local LAGOON_FLOOR = -2.5 -- always under water

assert(DRY_SAND > HIGH_TIDE and SANDBAR > LOW_TIDE and SHOALS > LOW_TIDE and LAGOON_FLOOR < LOW_TIDE)

local COLORS = {
	drySand = Color3.fromRGB(241, 228, 196),
	wetSand = Color3.fromRGB(214, 196, 160),
	sandbar = Color3.fromRGB(236, 222, 186),
	lagoonFloor = Color3.fromRGB(198, 184, 150),
	grass = Color3.fromRGB(120, 170, 96),
	moundGrass = Color3.fromRGB(132, 176, 100),
	shells = Color3.fromRGB(240, 235, 220),
	mud = Color3.fromRGB(122, 104, 78),
	rock = Color3.fromRGB(128, 128, 132),
	plaza = Color3.fromRGB(206, 190, 170),
	wood = Color3.fromRGB(150, 110, 78),
	trunk = Color3.fromRGB(96, 74, 56),
	canopy = Color3.fromRGB(70, 120, 70),
	white = Color3.fromRGB(238, 238, 232),
	red = Color3.fromRGB(200, 60, 50),
	pastel = Color3.fromRGB(150, 200, 210),
}

--- A part filling the box between two corners.
local function box(name: string, min: Vector3, max: Vector3, color: Color3, props: { [string]: any }?): Instance
	local size = max - min
	assert(size.X > 0 and size.Y > 0 and size.Z > 0, `{name} has an empty box`)
	local merged: { [string]: any } = {
		Name = name,
		Size = size,
		CFrame = CFrame.new((min + max) / 2),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
	}
	for key, value in props or {} do
		merged[key] = value
	end
	return Build.part(merged)
end

--- Ground from the seabed up to `top` over an XZ rectangle.
local function ground(name: string, x0: number, x1: number, z0: number, z1: number, top: number, color: Color3): Instance
	return box(name, Vector3.new(x0, SEABED, z0), Vector3.new(x1, top, z1), color)
end

--- A beach slope over an XZ rectangle, descending from `top` to the seabed toward `downhill`.
local function slope(name: string, x0: number, x1: number, z0: number, z1: number, top: number, downhill: "-X" | "+X" | "-Z" | "+Z", color: Color3): Instance
	-- A wedge is tallest at its back (+Z) and slopes down toward its front (-Z). Turn it so the
	-- front faces downhill; across is the horizontal extent perpendicular to the slope.
	local turn = ({ ["-Z"] = 0, ["+X"] = -math.pi / 2, ["+Z"] = math.pi, ["-X"] = math.pi / 2 })[downhill]
	local alongX = downhill == "-X" or downhill == "+X"
	local run = if alongX then x1 - x0 else z1 - z0
	local across = if alongX then z1 - z0 else x1 - x0
	local height = top - SEABED
	local center = Vector3.new((x0 + x1) / 2, SEABED + height / 2, (z0 + z1) / 2)
	return Build.wedge({
		Name = name,
		Size = Vector3.new(across, height, run),
		CFrame = CFrame.new(center) * CFrame.Angles(0, turn, 0),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
	})
end

local function zone(name: string, children: { Instance }): Instance
	return Build.model(name, children, { Attributes = { Zone = name } })
end

-- Main island interior: grassland from Hideaway Pass down to Caxa Point.
local interior = zone("Interior", {
	ground("Grassland", -120, 150, -330, 300, GRASS, COLORS.grass),
	slope("EastShore", 150, 180, -330, 300, GRASS, "+X", COLORS.wetSand),
})

-- Crescent Strand: the long west-coast beach, with the huts along its dunes.
local huts = {}
for index = 1, 20 do
	local z = -252 + 24 * index
	table.insert(
		huts,
		box(string.format("HutPlot%02d", index), Vector3.new(-141, DRY_SAND, z - 6), Vector3.new(-129, DRY_SAND + 1, z + 6), COLORS.wood, { Attributes = { PlotIndex = index } })
	)
end
local crescentStrand = zone("CrescentStrand", {
	ground("DryBeach", -160, -120, -270, 300, DRY_SAND, COLORS.drySand),
	slope("WetBeach", -200, -160, -270, 300, DRY_SAND, "-X", COLORS.wetSand),
	Build.model("HutPlots", huts),
})

-- Tigerfin Lagoon: a shallow lagoon behind a sand spit in the northwest.
local tigerfinLagoon = zone("TigerfinLagoon", {
	ground("LagoonFloor", -190, -120, -420, -270, LAGOON_FLOOR, COLORS.lagoonFloor),
	ground("NorthShore", -190, -120, -440, -420, DRY_SAND, COLORS.drySand),
	ground("Spit", -230, -190, -440, -270, DRY_SAND, COLORS.drySand),
	slope("SpitBeach", -260, -230, -440, -270, DRY_SAND, "-X", COLORS.wetSand),
})

-- Sand Dollar Bar: the offshore sandbar, walkable only at low tide.
local sandDollarBar = zone("SandDollarBar", {
	ground("Sandbar", -330, -290, -430, -300, SANDBAR, COLORS.sandbar),
})

-- Hideaway Pass: mangrove flats at the north tip.
local mangroves = {}
for index, spot in { { -90, -390 }, { -60, -360 }, { -30, -400 }, { 0, -370 }, { 30, -395 }, { 60, -360 }, { 90, -390 }, { 120, -365 } } do
	local x, z = spot[1], spot[2]
	table.insert(
		mangroves,
		Build.model(`Mangrove{index}`, {
			box("Trunk", Vector3.new(x - 1, MANGROVE_FLATS, z - 1), Vector3.new(x + 1, MANGROVE_FLATS + 6, z + 1), COLORS.trunk),
			box("Canopy", Vector3.new(x - 6, MANGROVE_FLATS + 6, z - 6), Vector3.new(x + 6, MANGROVE_FLATS + 11, z + 6), COLORS.canopy),
		})
	)
end
local hideawayPass = zone("HideawayPass", {
	ground("MangroveFlats", -120, 150, -420, -330, MANGROVE_FLATS, COLORS.mud),
	Build.model("Mangroves", mangroves),
})

-- Goodhaven: the fishing-village hub on the east side, with the shop, the dock, and the spawn.
local goodhaven = zone("Goodhaven", {
	box("Plaza", Vector3.new(80, GRASS, -40), Vector3.new(140, GRASS + 0.2, 40), COLORS.plaza),
	box("Shop", Vector3.new(96, GRASS + 0.2, -40), Vector3.new(124, GRASS + 12.2, -26), COLORS.pastel, { Attributes = { Landmark = "Shop" } }),
	box("Dock", Vector3.new(150, GRASS, -6), Vector3.new(220, GRASS + 1, 6), COLORS.wood),
	box("SpawnPad", Vector3.new(104, GRASS + 0.2, 10), Vector3.new(116, GRASS + 0.4, 22), COLORS.white, { Attributes = { Landmark = "Spawn" } }),
})

-- Shell Mound: a tiered hill inland, capped with shells.
local shellMound = zone("ShellMound", {
	box("Tier1", Vector3.new(-20, GRASS, 100), Vector3.new(60, GRASS + 4, 180), COLORS.moundGrass),
	box("Tier2", Vector3.new(0, GRASS + 4, 120), Vector3.new(40, GRASS + 8, 160), COLORS.moundGrass),
	box("Cap", Vector3.new(10, GRASS + 8, 130), Vector3.new(30, GRASS + 11, 150), COLORS.shells),
})

-- Caxa Point: a rocky southern point with tide pools and a lighthouse.
local poolRocks = {}
for index, spot in { { -192, 340 }, { -176, 356 }, { -188, 376 }, { -164, 388 }, { -172, 336 } } do
	local x, z = spot[1], spot[2]
	table.insert(poolRocks, box(`PoolRock{index}`, Vector3.new(x - 3, TIDE_POOL_SHELF, z - 3), Vector3.new(x + 3, TIDE_POOL_SHELF + 2, z + 3), COLORS.rock))
end
local lighthouseBase = GRASS - 1
local caxaPoint = zone("CaxaPoint", {
	ground("Headland", -150, -30, 300, 400, lighthouseBase, COLORS.rock),
	ground("TidePoolShelf", -200, -150, 330, 400, TIDE_POOL_SHELF, COLORS.wetSand),
	Build.model("PoolRocks", poolRocks),
	Build.part({
		Name = "Lighthouse",
		Shape = Enum.PartType.Cylinder,
		-- A cylinder's axis is its X axis; stand it upright.
		Size = Vector3.new(36, 10, 10),
		CFrame = CFrame.new(-90, lighthouseBase + 18, 380) * CFrame.Angles(0, 0, math.pi / 2),
		Color = COLORS.white,
		Material = Enum.Material.SmoothPlastic,
		Attributes = { Landmark = "Lighthouse" },
	}),
	box("Lantern", Vector3.new(-94, lighthouseBase + 36, 376), Vector3.new(-86, lighthouseBase + 42, 384), COLORS.red),
})

-- Dome Shoals: ruins of dome houses standing in the water, reached over shoals at low tide.
local domes = {}
for index, spot in { { -325, 445 }, { -305, 445 }, { -325, 475 }, { -305, 475 } } do
	local x, z = spot[1], spot[2]
	table.insert(
		domes,
		Build.model(`Dome{index}`, {
			box("Pillar", Vector3.new(x - 1.5, SHOALS, z - 1.5), Vector3.new(x + 1.5, SHOALS + 9, z + 1.5), COLORS.white),
			Build.part({
				Name = "Dome",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(16, 16, 16),
				CFrame = CFrame.new(x, SHOALS + 9 + 8, z),
				Color = COLORS.white,
				Material = Enum.Material.SmoothPlastic,
			}),
		})
	)
end
local domeShoals = zone("DomeShoals", {
	ground("Shoal1", -230, -200, 395, 410, SHOALS, COLORS.sandbar),
	ground("Shoal2", -260, -230, 410, 425, SHOALS, COLORS.sandbar),
	ground("Shoal3", -290, -260, 425, 440, SHOALS, COLORS.sandbar),
	ground("DomeFlat", -340, -290, 430, 490, SHOALS, COLORS.sandbar),
	Build.model("Domes", domes),
})

local island = Build.model("Island", {
	interior,
	crescentStrand,
	tigerfinLagoon,
	sandDollarBar,
	hideawayPass,
	goodhaven,
	shellMound,
	caxaPoint,
	domeShoals,
}, {
	Attributes = { Recipe = "rbxm-kit/recipes/tidewater_island" },
})

local issues, totals = Check.run({ island })
for _, issue in issues do
	print(`[{issue.kind}] {issue.message}`)
end
if #issues > 0 then
	print("Not writing a model that fails its checks.")
	process.exit(1)
end

ModelIo.write(output, { island })
print(`Wrote {output} ({totals.parts} parts)`)
