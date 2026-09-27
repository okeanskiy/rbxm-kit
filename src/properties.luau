--!strict

--[[
	Which properties the kit reads when it describes, diffs, or dumps an instance.

	Lune exposes every serialized property, but printing all of them buries the changes a reviewer
	cares about. These lists name the properties worth surfacing per class; attributes, tags, and
	script source are always included.
]]

local Properties = {}

Properties.SCRIPT_CLASSES = {
	LocalScript = true,
	ModuleScript = true,
	Script = true,
}

Properties.BASE_PART_PROPERTIES = {
	"Anchored",
	"CanCollide",
	"CanQuery",
	"CanTouch",
	"CastShadow",
	"CFrame",
	"CollisionGroup",
	"Color",
	"Material",
	"MaterialVariant",
	"Massless",
	"PivotOffset",
	"Reflectance",
	"RootPriority",
	"Size",
	"Transparency",
}

Properties.CLASS_PROPERTIES = {
	Attachment = { "Axis", "CFrame", "SecondaryAxis", "Visible" },
	Beam = {
		"Brightness",
		"Color",
		"CurveSize0",
		"CurveSize1",
		"Enabled",
		"FaceCamera",
		"LightEmission",
		"LightInfluence",
		"Segments",
		"Texture",
		"TextureLength",
		"TextureMode",
		"TextureSpeed",
		"Transparency",
		"Width0",
		"Width1",
	},
	ClickDetector = { "CursorIcon", "MaxActivationDistance" },
	Decal = { "Color3", "Face", "Texture", "Transparency", "ZIndex" },
	Highlight = { "DepthMode", "Enabled", "FillColor", "FillTransparency", "OutlineColor", "OutlineTransparency" },
	Light = { "Brightness", "Color", "Enabled", "Shadows" },
	MeshPart = { "DoubleSided", "MeshId", "RenderFidelity", "TextureID" },
	Model = { "LevelOfDetail", "ModelStreamingMode", "WorldPivot" },
	ParticleEmitter = {
		"Acceleration",
		"Brightness",
		"Color",
		"Drag",
		"EmissionDirection",
		"Enabled",
		"Lifetime",
		"LightEmission",
		"LightInfluence",
		"LockedToPart",
		"Orientation",
		"Rate",
		"RotSpeed",
		"Rotation",
		"Size",
		"Speed",
		"SpreadAngle",
		"Texture",
		"Transparency",
		"VelocityInheritance",
		"ZOffset",
	},
	Part = { "Shape" },
	ProximityPrompt = {
		"ActionText",
		"ClickablePrompt",
		"Enabled",
		"Exclusivity",
		"GamepadKeyCode",
		"HoldDuration",
		"KeyboardKeyCode",
		"MaxActivationDistance",
		"ObjectText",
		"RequiresLineOfSight",
		"Style",
		"UIOffset",
	},
	Sound = {
		"EmitterSize",
		"Looped",
		"MaxDistance",
		"MinDistance",
		"PlaybackSpeed",
		"Playing",
		"RollOffMode",
		"SoundGroup",
		"SoundId",
		"TimePosition",
		"Volume",
	},
	SpawnLocation = { "AllowTeamChangeOnTouch", "Duration", "Enabled", "Neutral", "TeamColor" },
	SurfaceAppearance = { "AlphaMode", "ColorMap", "MetalnessMap", "NormalMap", "RoughnessMap" },
	Texture = {
		"Color3",
		"Face",
		"OffsetStudsU",
		"OffsetStudsV",
		"StudsPerTileU",
		"StudsPerTileV",
		"Texture",
		"Transparency",
		"ZIndex",
	},
	Trail = {
		"Brightness",
		"Color",
		"Enabled",
		"FaceCamera",
		"Lifetime",
		"LightEmission",
		"LightInfluence",
		"MaxLength",
		"MinLength",
		"Texture",
		"TextureLength",
		"TextureMode",
		"Transparency",
		"WidthScale",
	},
}

Properties.SUMMARY_PROPERTIES = {
	Anchored = true,
	CanCollide = true,
	CanQuery = true,
	CanTouch = true,
	CFrame = true,
	Color = true,
	Material = true,
	MeshId = true,
	Size = true,
	Tags = true,
	Texture = true,
	TextureID = true,
	Transparency = true,
}

function Properties.formatValue(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

function Properties.readProperty(instance: Instance, property: string): string?
	local success, value = pcall(function()
		return (instance :: any)[property]
	end)
	if not success then
		return nil
	end
	if typeof(value) == "Instance" then
		return if value then `{value.ClassName} {string.format("%q", value.Name)}` else "nil"
	end
	return Properties.formatValue(value)
end

local function addProperties(instance: Instance, properties: { [string]: string }, names: { string })
	for _, name in names do
		local value = Properties.readProperty(instance, name)
		if value ~= nil then
			properties[name] = value
		end
	end
end

function Properties.createProperties(instance: Instance): { [string]: string }
	local properties: { [string]: string } = {}

	local tags = instance:GetTags()
	table.sort(tags)
	if #tags > 0 then
		properties.Tags = table.concat(tags, ", ")
	end

	for name, value in instance:GetAttributes() do
		properties[`Attribute.{name}`] = Properties.formatValue(value)
	end

	if instance:IsA("BasePart") then
		addProperties(instance, properties, Properties.BASE_PART_PROPERTIES)
	end
	if instance:IsA("ValueBase") then
		addProperties(instance, properties, { "Value" })
	end
	if Properties.SCRIPT_CLASSES[instance.ClassName] then
		addProperties(instance, properties, { "Disabled", "RunContext", "Source" })
	end

	for className, names in Properties.CLASS_PROPERTIES do
		if instance:IsA(className) then
			addProperties(instance, properties, names)
		end
	end

	return properties
end

function Properties.sortedKeys(values: { [string]: any }): { string }
	local keys = {}
	for key in values do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

function Properties.createFingerprint(properties: { [string]: string }): string
	local parts = {}
	for _, key in Properties.sortedKeys(properties) do
		local value = properties[key]
		table.insert(parts, `{#key}:{key}{#value}:{value}`)
	end
	return table.concat(parts, "|")
end

function Properties.describe(instance: Instance): string
	return `{instance.ClassName} {string.format("%q", instance.Name)}`
end

return Properties
