--!strict

--[[
	Entry point for recipes: `local Kit = require("../src/kit")`.

	Re-exports the kit modules and the Roblox data types a recipe needs, so a recipe reads like
	ordinary Roblox code.
]]

local roblox = require("@lune/roblox")

return {
	Build = require("./build"),
	Check = require("./check"),
	ModelIo = require("./model_io"),
	Place = require("./place"),

	BrickColor = roblox.BrickColor,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
	Vector3 = roblox.Vector3,
}
