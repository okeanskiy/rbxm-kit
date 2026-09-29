--!strict

--[[
	Offline sanity checks for built or edited models.

	These catch the mistakes that are otherwise only visible in Studio: parts sunk into each other,
	parts left unanchored, geometry drifting outside the intended area. They are heuristics over
	each part's box, not physics or mesh shapes; a human playtest remains the final check.

	Overlaps are found in two passes. A sweep along X over each part's world-aligned bounds finds
	the pairs whose bounds meet, in O(n log n) plus the pairs found rather than testing every pair
	of parts. Each such pair is then tested as two oriented boxes on their separating axes, so a
	rotated part is measured by its own box rather than the larger box around it.
]]

local Build = require("./build")
local Place = require("./place")

export type Issue = {
	kind: string,
	message: string,
	-- The collections the issue sits in, one per part involved: the full name of the parent of each
	-- part's object (see `betweenModels`), or of the part itself when no Model holds it. A long
	-- report groups its issues by these.
	where: { string },
}

export type Options = {
	-- Overlap depth, in studs, tolerated before two parts count as intersecting. Parts that merely
	-- touch or share a face are always fine.
	overlapTolerance: number?,
	-- Treat each Model as one object whose own parts may overlap one another, and report only
	-- overlaps between different objects or loose parts. A part's object is the outermost instance
	-- of class Model around it (Workspace does not count). Suits assembled scenes and maps, where
	-- each object's meshes share space by design.
	betweenModels: boolean?,
	-- Maximum distance from the origin on any axis; omitted means unbounded.
	maxExtent: number?,
	-- Maximum number of BaseParts; omitted means unbounded.
	maxParts: number?,
	-- Report unanchored parts. Defaults to true, since built world geometry is normally anchored.
	requireAnchored: boolean?,
}

-- A part's oriented box, and the world-aligned bounds around it.
type Box = {
	part: Instance,
	index: number,
	object: Instance?,
	-- Center; the box's three unit axes, the columns of its rotation, flattened as x1, y1, z1, x2, ...;
	-- and the half size along each axis.
	cx: number,
	cy: number,
	cz: number,
	axes: { number },
	half: { number },
	minX: number,
	maxX: number,
	minY: number,
	maxY: number,
	minZ: number,
	maxZ: number,
}

local Check = {}

local function name(part: Instance): string
	return part:GetFullName()
end

local function collidable(part: Instance): boolean
	return (part :: any).CanCollide == true and (part :: any).Transparency < 1
end

-- The outermost Model around a part, if any.
local function objectOf(part: Instance): Instance?
	local object: Instance? = nil
	local ancestor = part.Parent
	while ancestor do
		if ancestor.ClassName == "Model" then
			object = ancestor
		end
		ancestor = ancestor.Parent
	end
	return object
end

local function collectionOf(part: Instance): string
	local holder = objectOf(part) or part
	local parent = holder.Parent
	return if parent then parent:GetFullName() else "(root)"
end

local function boxOf(part: Instance, index: number): Box
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = ((part :: any).CFrame :: CFrame):GetComponents()
	local size = (part :: any).Size :: Vector3
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	-- Half extents of the world-aligned box around the rotated one.
	local ex = math.abs(r00) * hx + math.abs(r01) * hy + math.abs(r02) * hz
	local ey = math.abs(r10) * hx + math.abs(r11) * hy + math.abs(r12) * hz
	local ez = math.abs(r20) * hx + math.abs(r21) * hy + math.abs(r22) * hz
	return {
		part = part,
		index = index,
		object = nil,
		cx = x,
		cy = y,
		cz = z,
		axes = { r00, r10, r20, r01, r11, r21, r02, r12, r22 },
		half = { hx, hy, hz },
		minX = x - ex,
		maxX = x + ex,
		minY = y - ey,
		maxY = y + ey,
		minZ = z - ez,
		maxZ = z + ez,
	}
end

--[[
	How far two oriented boxes sink into each other: the least overlap of their projections over
	the fifteen separating axes (each box's three face normals and the nine cross products of their
	edges), which is the shortest move that would part them. Zero or less when they only touch or
	are apart. Returns early once an axis shows them no deeper than `tolerance`. After Ericson,
	Real-Time Collision Detection, 4.4.1.
]]
local function depth(a: Box, b: Box, tolerance: number): number
	local A, B = a.axes, b.axes
	local ea, eb = a.half, b.half
	local tx, ty, tz = b.cx - a.cx, b.cy - a.cy, b.cz - a.cz
	-- R[i][j] is a's axis i dotted with b's axis j, stored at i * 3 + j + 1.
	local R, AbsR = table.create(9, 0), table.create(9, 0)
	for i = 0, 2 do
		for j = 0, 2 do
			local r = A[i * 3 + 1] * B[j * 3 + 1] + A[i * 3 + 2] * B[j * 3 + 2] + A[i * 3 + 3] * B[j * 3 + 3]
			R[i * 3 + j + 1] = r
			AbsR[i * 3 + j + 1] = math.abs(r) + 1e-9
		end
	end
	-- The offset between centers, in a's frame.
	local t = {
		tx * A[1] + ty * A[2] + tz * A[3],
		tx * A[4] + ty * A[5] + tz * A[6],
		tx * A[7] + ty * A[8] + tz * A[9],
	}
	local least = math.huge
	for i = 0, 2 do
		local rb = eb[1] * AbsR[i * 3 + 1] + eb[2] * AbsR[i * 3 + 2] + eb[3] * AbsR[i * 3 + 3]
		least = math.min(least, ea[i + 1] + rb - math.abs(t[i + 1]))
		if least <= tolerance then
			return least
		end
	end
	for j = 0, 2 do
		local ra = ea[1] * AbsR[j + 1] + ea[2] * AbsR[3 + j + 1] + ea[3] * AbsR[6 + j + 1]
		local along = t[1] * R[j + 1] + t[2] * R[3 + j + 1] + t[3] * R[6 + j + 1]
		least = math.min(least, ra + eb[j + 1] - math.abs(along))
		if least <= tolerance then
			return least
		end
	end
	for i = 0, 2 do
		local i1, i2 = (i + 1) % 3, (i + 2) % 3
		for j = 0, 2 do
			-- Edges that are parallel give no axis of their own; the face normals cover them.
			local length = math.sqrt(math.max(0, 1 - R[i * 3 + j + 1] ^ 2))
			if length > 1e-6 then
				local j1, j2 = (j + 1) % 3, (j + 2) % 3
				local ra = ea[i1 + 1] * AbsR[i2 * 3 + j + 1] + ea[i2 + 1] * AbsR[i1 * 3 + j + 1]
				local rb = eb[j1 + 1] * AbsR[i * 3 + j2 + 1] + eb[j2 + 1] * AbsR[i * 3 + j1 + 1]
				local distance = math.abs(t[i2 + 1] * R[i1 * 3 + j + 1] - t[i1 + 1] * R[i2 * 3 + j + 1])
				least = math.min(least, (ra + rb - distance) / length)
				if least <= tolerance then
					return least
				end
			end
		end
	end
	return least
end

function Check.overlaps(parts: { Instance }, tolerance: number, betweenModels: boolean?): { Issue }
	local issues = {}
	local boxes: { Box } = {}
	for index, part in parts do
		if collidable(part) then
			local box = boxOf(part, index)
			if betweenModels then
				box.object = objectOf(part)
			end
			table.insert(boxes, box)
		end
	end
	table.sort(boxes, function(a: Box, b: Box): boolean
		if a.minX ~= b.minX then
			return a.minX < b.minX
		end
		return a.index < b.index
	end)
	for i = 1, #boxes do
		local a = boxes[i]
		local reach = a.maxX - tolerance
		for j = i + 1, #boxes do
			local b = boxes[j]
			if b.minX >= reach then
				break
			end
			local sameObject = a.object ~= nil and a.object == b.object
			if
				not sameObject
				and math.min(a.maxX, b.maxX) - b.minX > tolerance
				and math.min(a.maxY, b.maxY) - math.max(a.minY, b.minY) > tolerance
				and math.min(a.maxZ, b.maxZ) - math.max(a.minZ, b.minZ) > tolerance
			then
				local sunk = depth(a, b, tolerance)
				if sunk > tolerance then
					local first, second = a, b
					if b.index < a.index then
						first, second = b, a
					end
					local where = { collectionOf(first.part), collectionOf(second.part) }
					table.sort(where)
					table.insert(issues, {
						kind = "overlap",
						message = string.format("%s intersects %s by %.2f studs", name(first.part), name(second.part), sunk),
						where = where,
					})
				end
			end
		end
	end
	return issues
end

function Check.run(roots: { Instance }, options: Options?): ({ Issue }, { parts: number, instances: number })
	local resolved: Options = options or {}
	local issues: { Issue } = {}
	local parts: { Instance } = {}
	local instanceCount = 0

	for _, root in roots do
		instanceCount += 1 + #root:GetDescendants()
		for _, part in Build.parts(root) do
			-- Terrain is a BasePart whose box spans the whole world; it is not a part to check.
			if part.ClassName ~= "Terrain" then
				table.insert(parts, part)
			end
		end
	end

	if resolved.requireAnchored ~= false then
		for _, part in parts do
			if (part :: any).Anchored ~= true then
				table.insert(issues, { kind = "unanchored", message = `{name(part)} is not anchored`, where = { collectionOf(part) } })
			end
		end
	end

	for _, issue in Check.overlaps(parts, resolved.overlapTolerance or 0.01, resolved.betweenModels) do
		table.insert(issues, issue)
	end

	local maxExtent = resolved.maxExtent
	if maxExtent then
		for _, part in parts do
			local min, max = Place.bounds(part)
			local extent = math.max(math.abs(min.X), math.abs(min.Y), math.abs(min.Z), math.abs(max.X), math.abs(max.Y), math.abs(max.Z))
			if extent > maxExtent then
				table.insert(issues, {
					kind = "extent",
					message = string.format("%s reaches %.1f studs from the origin (limit %.1f)", name(part), extent, maxExtent),
					where = { collectionOf(part) },
				})
			end
		end
	end

	if resolved.maxParts and #parts > resolved.maxParts then
		table.insert(issues, { kind = "budget", message = `{#parts} BaseParts exceeds the budget of {resolved.maxParts}`, where = { "(all)" } })
	end

	return issues, { parts = #parts, instances = instanceCount }
end

return Check
