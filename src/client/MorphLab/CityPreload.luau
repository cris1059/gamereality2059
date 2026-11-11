--!strict

-- Downloads City2059's meshes and textures (and the generated city dressing)
-- before the first menu shows, so the skyline does not pop in piece by piece.
-- Runs once per session; gives up after `timeout` seconds and lets the rest
-- load in the background.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local LobbyConfig = require(root.Config.LobbyConfig)
local MorphLabConfig = require(root.Config.MorphLabConfig)

local CityPreload = {}

local finished = false
local running = false

local function collect(): { Instance }
	local assets = {}
	local sources = {
		Workspace:FindFirstChild(LobbyConfig.CityModelName, true),
		Workspace:FindFirstChild(MorphLabConfig.RuntimeFolderName),
	}
	for _, source in sources do
		if source then
			for _, descendant in source:GetDescendants() do
				if descendant:IsA("MeshPart") or descendant:IsA("Decal") or descendant:IsA("Texture")
					or descendant:IsA("SurfaceAppearance") or descendant:IsA("SpecialMesh") then
					table.insert(assets, descendant)
				end
			end
		end
	end
	return assets
end

-- Yields until the city is downloaded or `timeout` passes. `report` gets 0..1.
function CityPreload.Run(report: ((number) -> ())?, timeout: number?)
	if finished then
		return
	end
	local assets = collect()
	if #assets == 0 then
		return
	end
	local total = #assets
	local loaded = 0
	if not running then
		running = true
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(assets, function()
					loaded += 1
				end)
			end)
			finished = true
			running = false
		end)
	end
	local deadline = os.clock() + (timeout or 10)
	while not finished and os.clock() < deadline do
		if report then
			report(math.clamp(loaded / total, 0, 1))
		end
		task.wait(0.1)
	end
end

return CityPreload
