--!strict

-- Lighting of a multiplayer map: its day or night preset (MapsConfig) while
-- it is played, client-only, with the previous values restored afterwards.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local MapsConfig = require(root.Config.MapsConfig)

local MapLighting = {}
MapLighting.__index = MapLighting

function MapLighting.new()
	return setmetatable({
		_saved = nil :: { [string]: any }?,
		_savedAtmosphere = nil :: { [string]: any }?,
		_atmosphere = nil :: Atmosphere?,
		_createdAtmosphere = false,
	}, MapLighting)
end

-- mapName: a key of MapsConfig.Maps (unknown maps are lit as day).
function MapLighting:Apply(mapName: string)
	self:Restore()
	local info = MapsConfig.Maps[mapName]
	local preset = MapsConfig.Lighting[if info then info.timeOfDay else "day"] or MapsConfig.Lighting.day
	local saved = {}
	for property, value in preset.lighting do
		saved[property] = (Lighting :: any)[property]
		;(Lighting :: any)[property] = value
	end
	self._saved = saved
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "MapAtmosphere"
		atmosphere.Parent = Lighting
		self._createdAtmosphere = true
	end
	local savedAtmosphere = {}
	for property, value in preset.atmosphere do
		savedAtmosphere[property] = (atmosphere :: any)[property]
		;(atmosphere :: any)[property] = value
	end
	self._atmosphere = atmosphere
	self._savedAtmosphere = savedAtmosphere
end

function MapLighting:Restore()
	for property, value in self._saved or {} do
		(Lighting :: any)[property] = value
	end
	self._saved = nil
	local atmosphere = self._atmosphere
	if atmosphere then
		if self._createdAtmosphere then
			atmosphere:Destroy()
		elseif atmosphere.Parent then
			for property, value in self._savedAtmosphere or {} do
				(atmosphere :: any)[property] = value
			end
		end
	end
	self._atmosphere = nil
	self._savedAtmosphere = nil
	self._createdAtmosphere = false
end

return MapLighting
