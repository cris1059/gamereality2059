--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local LobbyConfig = require(root.Config.LobbyConfig)
local LobbySceneBuilder = require(script.Parent.Parent.Services.LobbySceneBuilder)

local LobbyTests = {}

local function expect(condition: boolean, message: string)
	if not condition then
		error("Lobby test failed: " .. message, 2)
	end
end

function LobbyTests.run(): { passed: number, total: number }
	local scene = LobbySceneBuilder.Build()
	local count = #scene:GetDescendants()
	expect(LobbySceneBuilder.Build() == scene and #scene:GetDescendants() == count, "repeated build must reuse the lobby")
	local platform = scene:FindFirstChild("Platform")
	local spawn = platform and platform:FindFirstChild("CharacterSpawn")
	expect(spawn ~= nil and spawn:IsA("BasePart"), "the player's CharacterSpawn is required")
	local cameras = scene:FindFirstChild("Cameras")
	expect(cameras ~= nil and cameras:FindFirstChild("CinematicCamera") ~= nil, "the lobby camera anchor is required")
	local squad = scene:FindFirstChild("Squad")
	for index = 1, #LobbyConfig.SquadSlots do
		expect(squad ~= nil and squad:FindFirstChild("SquadSlot" .. index) ~= nil, "squad slot " .. index .. " is missing")
	end
	local skyline = LobbySceneBuilder.GetSkyline()
	expect(skyline ~= nil and skyline:FindFirstChild("Portal") ~= nil and skyline:FindFirstChild("CityDressing") ~= nil, "the skyline needs the portal and city dressing")
	expect(skyline ~= nil and skyline:IsDescendantOf(workspace) == false, "the skyline template must stay out of Workspace (MODO LIBRE)")
	return { passed = 6, total = 6 }
end

return LobbyTests
