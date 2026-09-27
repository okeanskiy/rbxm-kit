--!strict

--[[
	Relative placement for built geometry.

	Hand-typed absolute coordinates are where generated scenes go wrong: a roof one stud too high,
	a wall clipping a floor. These helpers position instances relative to each other's world-space
	bounding boxes instead.

	Bounds are axis-aligned boxes around every BasePart, so relative placement is exact for
	axis-aligned geometry and conservative (outer box) for rotated parts. Models are moved by moving
	their parts, since `PivotTo` is an engine method that is unavailable outside Roblox.
]]

local roblox = require("@lune/roblox")

local Build = require("./build")

local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

export type Side = "+X" | "-X" | "+Y" | "-Y" | "+Z" | "-Z"

local Place = {}

--- World-space axis-aligned bounds of a part or of every part under an instance.
function Place.bounds(instance: Instance): (Vector3, Vector3)
	local parts = Build.parts(instance)
	if #parts == 0 then
		error(`{instance:GetFullName()} contains no BaseParts to measure`, 2)
	end

	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, part in parts do
		local cframe = (part :: any).CFrame :: CFrame
		local half = ((part :: any).Size :: Vector3) / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = cframe * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					minX, minY, minZ = math.min(minX, corner.X), math.min(minY, corner.Y), math.min(minZ, corner.Z)
					maxX, maxY, maxZ = math.max(maxX, corner.X), math.max(maxY, corner.Y), math.max(maxZ, corner.Z)
				end
			end
		end
	end
	return Vector3.new(minX, minY, minZ), Vector3.new(maxX, maxY, maxZ)
end

function Place.center(instance: Instance): Vector3
	local min, max = Place.bounds(instance)
	return (min + max) / 2
end

function Place.size(instance: Instance): Vector3
	local min, max = Place.bounds(instance)
	return max - min
end

--- Translate a part or every part under an instance, keeping relative layout and rotation.
function Place.moveBy(instance: Instance, delta: Vector3): Instance
	for _, part in Build.parts(instance) do
		(part :: any).CFrame += delta
	end
	if instance:IsA("Model") then
		local ok, pivot = pcall(function()
			return (instance :: any).WorldPivot
		end)
		if ok and pivot then
			(instance :: any).WorldPivot = pivot + delta
		end
	end
	return instance
end

--- Move an instance so its bounding-box center is at `position`.
function Place.moveTo(instance: Instance, position: Vector3): Instance
	return Place.moveBy(instance, position - Place.center(instance))
end

local AXES: { [string]: { axis: string, sign: number } } = {
	["+X"] = { axis = "X", sign = 1 },
	["-X"] = { axis = "X", sign = -1 },
	["+Y"] = { axis = "Y", sign = 1 },
	["-Y"] = { axis = "Y", sign = -1 },
	["+Z"] = { axis = "Z", sign = 1 },
	["-Z"] = { axis = "Z", sign = -1 },
}

local function component(vector: Vector3, axis: string): number
	return (vector :: any)[axis]
end

local function withComponent(vector: Vector3, axis: string, value: number): Vector3
	return Vector3.new(if axis == "X" then value else vector.X, if axis == "Y" then value else vector.Y, if axis == "Z" then value else vector.Z)
end

--- Place `instance` flush against `side` of `target`, centered on the other two axes, with an
--- optional `gap`. Horizontal sides also align the bottoms, so a wall beside a floor slab stands
--- on the same level instead of floating at the slab's center height.
function Place.against(instance: Instance, target: Instance, side: Side, gap: number?): Instance
	local spec = AXES[side]
	if not spec then
		error(`unknown side '{side}'`, 2)
	end
	local targetMin, targetMax = Place.bounds(target)
	local targetCenter = (targetMin + targetMax) / 2
	local size = Place.size(instance)

	local halfExtent = component(size, spec.axis) / 2
	local faceValue = component(if spec.sign > 0 then targetMax else targetMin, spec.axis)
	local position = withComponent(targetCenter, spec.axis, faceValue + spec.sign * (halfExtent + (gap or 0)))
	if spec.axis ~= "Y" then
		position = withComponent(position, "Y", targetMin.Y + size.Y / 2)
	end
	return Place.moveTo(instance, position)
end

--- Rest `instance` on top of `target`, centered over it.
function Place.onTopOf(instance: Instance, target: Instance, gap: number?): Instance
	return Place.against(instance, target, "+Y", gap)
end

--- Nudge an instance along one axis relative to its current position.
function Place.offset(instance: Instance, x: number, y: number, z: number): Instance
	return Place.moveBy(instance, Vector3.new(x, y, z))
end

--- Centers of a `columns` x `rows` grid on the XZ plane around `origin`.
function Place.grid(columns: number, rows: number, spacing: number, origin: Vector3?): { Vector3 }
	local center = origin or Vector3.new(0, 0, 0)
	local positions = {}
	for row = 0, rows - 1 do
		for column = 0, columns - 1 do
			local x = (column - (columns - 1) / 2) * spacing
			local z = (row - (rows - 1) / 2) * spacing
			table.insert(positions, center + Vector3.new(x, 0, z))
		end
	end
	return positions
end

local UP = Vector3.new(0, 1, 0)

--- A CFrame at `position` facing `target`, kept upright.
---
--- Use this instead of `CFrame.lookAt`: in Lune 0.10.5, `CFrame.lookAt` returns a reversed look
--- vector when facing along the Z axis. Looking straight up or down is undefined here.
function Place.lookAt(position: Vector3, target: Vector3): CFrame
	local look = (target - position).Unit
	local right = look:Cross(UP).Unit
	return CFrame.fromMatrix(position, right, right:Cross(look), -look)
end

--- `count` evenly spaced CFrames on a horizontal circle, each facing outward from `center`.
function Place.ring(count: number, radius: number, center: Vector3?): { CFrame }
	local origin = center or Vector3.new(0, 0, 0)
	local cframes = {}
	for index = 0, count - 1 do
		local angle = (index / count) * math.pi * 2
		local position = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		table.insert(cframes, Place.lookAt(position, position + (position - origin)))
	end
	return cframes
end

function Place.snap(value: number, increment: number): number
	return math.round(value / increment) * increment
end

function Place.snapVector(vector: Vector3, increment: number): Vector3
	return Vector3.new(Place.snap(vector.X, increment), Place.snap(vector.Y, increment), Place.snap(vector.Z, increment))
end

return Place
