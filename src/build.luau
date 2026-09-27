--!strict

--[[
	Declarative instance construction.

		local part = Build.new("Part", { Name = "Floor", Size = Vector3.new(20, 1, 20) }, {
			Build.new("Decal", { Texture = "rbxassetid://..." }),
		})

	`Attributes` and `Tags` in the property table set attributes and CollectionService tags instead
	of properties. `Position` on a BasePart sets its CFrame's position. `Build.part` and friends only
	add defaults; every default can be overridden.
]]

local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Enum = roblox.Enum

export type Props = { [string]: any }

local Build = {}

local function apply(instance: Instance, props: Props)
	for key, value in props do
		if key == "Attributes" then
			for name, attribute in value do
				instance:SetAttribute(name, attribute)
			end
		elseif key == "Tags" then
			for _, tag in value do
				instance:AddTag(tag)
			end
		elseif key ~= "Parent" and not (key == "Position" and instance:IsA("BasePart")) then
			(instance :: any)[key] = value
		end
	end

	-- `Position` is derived from `CFrame` in the engine and is not a stored property, so move the
	-- CFrame instead. It is applied last because table iteration order is undefined, and a `CFrame`
	-- applied afterwards would otherwise discard it.
	if props.Position ~= nil and instance:IsA("BasePart") then
		local cframe = (instance :: any).CFrame;
		(instance :: any).CFrame = cframe - cframe.Position + props.Position
	end
end

--- Create an instance, apply `props`, and parent `children` to it. `Parent` is ignored in `props`
--- so trees are always assembled bottom-up.
function Build.new(className: string, props: Props?, children: { Instance }?): Instance
	local instance = Instance.new(className)
	if props then
		apply(instance, props)
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	return instance
end

local PART_DEFAULTS: Props = {
	Anchored = true,
	TopSurface = Enum.SurfaceType.Smooth,
	BottomSurface = Enum.SurfaceType.Smooth,
}

local function withDefaults(defaults: Props, props: Props?): Props
	local merged = table.clone(defaults)
	if props then
		for key, value in props do
			merged[key] = value
		end
	end
	return merged
end

--- An anchored, smooth-surfaced Part. World-built geometry is anchored unless it opts out.
function Build.part(props: Props?, children: { Instance }?): Instance
	return Build.new("Part", withDefaults(PART_DEFAULTS, props), children)
end

--- An anchored, smooth-surfaced WedgePart.
function Build.wedge(props: Props?, children: { Instance }?): Instance
	return Build.new("WedgePart", withDefaults(PART_DEFAULTS, props), children)
end

function Build.model(name: string, children: { Instance }?, props: Props?): Instance
	return Build.new("Model", withDefaults({ Name = name }, props), children)
end

function Build.folder(name: string, children: { Instance }?): Instance
	return Build.new("Folder", { Name = name }, children)
end

--- Every BasePart under `root`, including `root` itself.
function Build.parts(root: Instance): { Instance }
	local parts = {}
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

return Build
