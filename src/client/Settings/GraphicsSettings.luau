--!strict

-- The current graphics profile, shared by the menu and MODO LIBRE. The
-- choice lasts for the session (Roblox keeps no client storage between
-- sessions without a profile field).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GraphicsConfig = require(ReplicatedStorage:WaitForChild("CyberpunkOnline").Config.GraphicsConfig)

local GraphicsSettings = {}

local choice = GraphicsConfig.Default
local changed = Instance.new("BindableEvent")
GraphicsSettings.Changed = changed.Event

local function autoProfile(): string
	local ok, level = pcall(function()
		return UserSettings().GameSettings.SavedQualityLevel.Value
	end)
	-- 0 = "Automatic" in Roblox: assume a capable device.
	if not ok or level == 0 then
		return "high"
	end
	if level <= GraphicsConfig.AutoThresholds.low then
		return "low"
	elseif level <= GraphicsConfig.AutoThresholds.medium then
		return "medium"
	end
	return "high"
end

-- The chosen option id (auto | low | medium | high).
function GraphicsSettings.GetChoice(): string
	return choice
end

-- The resolved profile table.
function GraphicsSettings.Get()
	local id = if choice == "auto" then autoProfile() else choice
	return GraphicsConfig.Profiles[id]
end

function GraphicsSettings.Label(): string
	if choice == "auto" then
		return "AUTO (" .. GraphicsSettings.Get().name .. ")"
	end
	return GraphicsConfig.Profiles[choice].name
end

-- Moves to the next option and notifies listeners.
function GraphicsSettings.Cycle(): string
	local index = table.find(GraphicsConfig.Order, choice) or 1
	choice = GraphicsConfig.Order[index % #GraphicsConfig.Order + 1]
	changed:Fire(GraphicsSettings.Get())
	return choice
end

return GraphicsSettings
