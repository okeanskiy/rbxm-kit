--!strict

--[[
	Offline sanity checks for built or edited models.

	These catch the mistakes that are otherwise only visible in Studio: parts sunk into each other,
	parts left unanchored, geometry drifting outside the intended area. They are heuristics over
	axis-aligned bounds, not physics; a human playtest remains the final check.
]]

local Build = require("./build")
local Place = require("./place")

export type Issue = { kind: string, message: string }

export type Options = {
	-- Overlap depth, in studs, tolerated on every axis before two parts count as intersecting.
	-- Parts that merely touch or share a face are always fine.
	overlapTolerance: number?,
	-- Maximum distance from the origin on any axis; omitted means unbounded.
	maxExtent: number?,
	-- Maximum number of BaseParts; omitted means unbounded.
	maxParts: number?,
	-- Report unanchored parts. Defaults to true, since built world geometry is normally anchored.
	requireAnchored: boolean?,
}

local Check = {}

local function name(part: Instance): string
	return part:GetFullName()
end

local function collidable(part: Instance): boolean
	return (part :: any).CanCollide == true and (part :: any).Transparency < 1
end

function Check.overlaps(parts: { Instance }, tolerance: number): { Issue }
	local issues = {}
	local boxes = {}
	for index, part in parts do
		if collidable(part) then
			local min, max = Place.bounds(part)
			table.insert(boxes, { part = part, min = min, max = max, index = index })
		end
	end
	for i = 1, #boxes do
		local a = boxes[i]
		for j = i + 1, #boxes do
			local b = boxes[j]
			local depthX = math.min(a.max.X, b.max.X) - math.max(a.min.X, b.min.X)
			local depthY = math.min(a.max.Y, b.max.Y) - math.max(a.min.Y, b.min.Y)
			local depthZ = math.min(a.max.Z, b.max.Z) - math.max(a.min.Z, b.min.Z)
			if depthX > tolerance and depthY > tolerance and depthZ > tolerance then
				table.insert(issues, {
					kind = "overlap",
					message = string.format("%s intersects %s by %.2f x %.2f x %.2f studs", name(a.part), name(b.part), depthX, depthY, depthZ),
				})
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
			table.insert(parts, part)
		end
	end

	if resolved.requireAnchored ~= false then
		for _, part in parts do
			if (part :: any).Anchored ~= true then
				table.insert(issues, { kind = "unanchored", message = `{name(part)} is not anchored` })
			end
		end
	end

	for _, issue in Check.overlaps(parts, resolved.overlapTolerance or 0.01) do
		table.insert(issues, issue)
	end

	local maxExtent = resolved.maxExtent
	if maxExtent then
		for _, part in parts do
			local min, max = Place.bounds(part)
			local extent = math.max(math.abs(min.X), math.abs(min.Y), math.abs(min.Z), math.abs(max.X), math.abs(max.Y), math.abs(max.Z))
			if extent > maxExtent then
				table.insert(issues, { kind = "extent", message = string.format("%s reaches %.1f studs from the origin (limit %.1f)", name(part), extent, maxExtent) })
			end
		end
	end

	if resolved.maxParts and #parts > resolved.maxParts then
		table.insert(issues, { kind = "budget", message = `{#parts} BaseParts exceeds the budget of {resolved.maxParts}` })
	end

	return issues, { parts = #parts, instances = instanceCount }
end

return Check
