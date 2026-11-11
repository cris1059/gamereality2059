--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Characters only exist in MODO LIBRE (FreeRoamService); set before anyone spawns.
Players.CharacterAutoLoads = false

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local gameConfig = require(root.Config.GameConfig)
local MockDataStore = require(script.Data.MockDataStore)
local RobloxDataStore = require(script.Data.RobloxDataStore)
local PlayerDataService = require(script.Services.PlayerDataService)
local PlayerBootstrapService = require(script.Services.PlayerBootstrapService)
local MorphLabSceneBuilder = require(script.Services.MorphLabSceneBuilder)
local LobbySceneBuilder = require(script.Services.LobbySceneBuilder)
local CityWorldService = require(script.Services.CityWorldService)
local FreeRoamService = require(script.Services.FreeRoamService)
local CityDressingService = require(script.Services.CityDressingService)
local AvatarService = require(script.Services.AvatarService)
local InventoryService = require(script.Services.InventoryService)
local ShopService = require(script.Services.ShopService)
local WeaponService = require(script.Services.WeaponService)
local CombatService = require(script.Services.CombatService)
local MatchService = require(script.Match.MatchService)
local PartyService = require(script.Party.PartyService)
local AccessService = require(script.Services.AccessService)

-- Runtime-only instances belong to the server and are intentionally not mapped
-- by Rojo, so Studio-authored visual content remains untouched.
local runtime = root:FindFirstChild("Runtime")
if not runtime then
	runtime = Instance.new("Folder")
	runtime.Name = "Runtime"
	runtime.Parent = root
end

AccessService.Start()
runtime:SetAttribute("ServerReady", true)
runtime:SetAttribute("ProjectVersion", gameConfig.RojoProjectVersion)
runtime:SetAttribute("PersistenceBackend", gameConfig.Persistence.Backend)

-- The city is scaled and placed first: the lobby stands in front of it, and
-- the MORPHLAB rooftop beside the lobby.
local freeRoamWorld = CityWorldService.Build()
runtime:SetAttribute("CityFound", freeRoamWorld:GetAttribute("CityFound"))
CityDressingService.Build(freeRoamWorld)
local lobby = LobbySceneBuilder.Build()
local morphLab = MorphLabSceneBuilder.Build()
runtime:SetAttribute("LobbySceneVersion", lobby:GetAttribute("SceneVersion"))
runtime:SetAttribute("MorphLabSceneVersion", morphLab:GetAttribute("SceneVersion"))

if RunService:IsStudio() then
	local function runStudioTests(label: string, moduleScript: ModuleScript)
		local ok, result = pcall(function()
			return require(moduleScript).run()
		end)
		if ok then
			print(string.format("[%s] %s tests passed: %d/%d", gameConfig.GameName, label, result.passed, result.total))
		else
			warn(string.format("[%s] %s tests failed (server startup continues): %s", gameConfig.GameName, label, tostring(result)))
		end
	end

	runStudioTests("Phase B", script.Tests.PhaseBTests :: ModuleScript)
	runStudioTests("Phase C.1", script.Tests.PhaseC1Tests :: ModuleScript)
	runStudioTests("Phase C.2", script.Tests.PhaseC2Tests :: ModuleScript)
	runStudioTests("Phase C.3.1", script.Tests.PhaseC31Tests :: ModuleScript)
	runStudioTests("MorphLab variants", script.Tests.MorphLabVariantTests :: ModuleScript)
	runStudioTests("R15 avatar", script.Tests.AvatarTests :: ModuleScript)
	runStudioTests("Lobby", script.Tests.LobbyTests :: ModuleScript)
	runStudioTests("Free roam", script.Tests.FreeRoamTests :: ModuleScript)
	runStudioTests("Inventory", script.Tests.InventoryTests :: ModuleScript)
	runStudioTests("Party", script.Tests.PartyTests :: ModuleScript)
	runStudioTests("City life", script.Tests.CityLifeTests :: ModuleScript)
end

-- "Auto": real DataStores when they answer. Only in Studio without API
-- access does it fall back to the Mock (data lasts one Play session); a live
-- server never silently switches to the Mock, it keeps retrying the real store.
local backend = gameConfig.Persistence.Backend
if backend == "Auto" then
	local reachable, probeError = RobloxDataStore.Probe(gameConfig.Persistence.DataStoreName)
	if reachable or not RunService:IsStudio() then
		backend = "DataStoreService"
	else
		backend = "Mock"
		warn("[REALITY 2059] DataStores unavailable in Studio (" .. tostring(probeError)
			.. "). Using MockDataStore: publish the place and enable Game Settings > Security > "
			.. "Enable Studio Access to API Services to save for real.")
	end
end
runtime:SetAttribute("PersistenceBackend", backend)

local store
if backend == "Mock" then
	store = MockDataStore.new()
elseif backend == "DataStoreService" then
	store = RobloxDataStore.new(
		gameConfig.Persistence.DataStoreName,
		gameConfig.Persistence.MaxAttempts,
		gameConfig.Persistence.RetryBaseSeconds
	)
else
	error("Unsupported persistence backend: " .. tostring(gameConfig.Persistence.Backend))
end

local dataService = PlayerDataService.new(store, {
	leaseSeconds = gameConfig.Persistence.LeaseSeconds,
})
local bootstrapService = PlayerBootstrapService.new(dataService, runtime)
bootstrapService:Start()
-- Standard R15 avatars: preview models for the client and real characters.
local avatarService = AvatarService.new(runtime)
avatarService:Start()
local freeRoamService = FreeRoamService.new(runtime, freeRoamWorld, avatarService)
freeRoamService:Start()
local inventoryService = InventoryService.new(runtime, dataService)
inventoryService:Start()
local shopService = ShopService.new(runtime, dataService)
shopService:Start()
local weaponService = WeaponService.new(runtime)
weaponService:Start()
local combatService = CombatService.new(runtime)
combatService:Start()
-- Matches on this server (private rooms) use the free roam spawner and the
-- weapon loadouts.
local matchService = MatchService.new(runtime, freeRoamService, weaponService)
matchService:Run()
local partyService = PartyService.new(runtime, dataService)
partyService:SetMatchService(matchService)
partyService:Start()

game:BindToClose(function()
	bootstrapService:Shutdown()
end)

print(string.format("[%s] Server infrastructure ready (%s)", gameConfig.GameName, backend))
