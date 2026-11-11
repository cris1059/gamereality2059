--!strict

-- Team deathmatch played on this server (private rooms; see MatchConfig).
-- Start(players) copies a map into its own slot, splits the players into two
-- balanced teams (Roblox Teams, so friendly fire is off and the player list
-- shows them), and has FreeRoamService spawn each one at their team's spawns
-- with the starting weapons (WeaponService). Kills come from the attacker
-- CombatService marks on the victim (LastAttacker). The match ends at
-- ScoreLimit or when time runs out, shows the results, then the map is
-- removed and everyone goes back to the lobby.
-- Clients follow MatchState (phase: countdown | playing | ended | closed)
-- and can leave with MatchLeave.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local MatchConfig = require(root.Config.MatchConfig)
local MapsConfig = require(root.Config.MapsConfig)
local RemoteNames = require(root.Network.RemoteNames)

local MatchService = {}
MatchService.__index = MatchService

type TeamId = string
type Stats = { kills: number, deaths: number }
type Match = {
	id: number,
	mapName: string,
	model: Model,
	slot: number,
	players: { Player },
	team: { [Player]: TeamId },
	stats: { [Player]: Stats },
	score: { [TeamId]: number },
	phase: string,
	endsAt: number,
	result: any?,
	onEnd: ((any) -> ())?,
	connections: { RBXScriptConnection },
}

local function remote(folder: Instance, className: string, name: string): any
	local existing = folder:FindFirstChild(name)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = folder
	return created
end

-- freeRoam: FreeRoamService (spawning); weapons: WeaponService (loadouts).
function MatchService.new(runtime: Folder, freeRoam: any, weapons: any)
	local remotes = runtime:WaitForChild(RemoteNames.Folder)
	local teams = {}
	for teamId, info in MatchConfig.Teams do
		local team = Teams:FindFirstChild(info.name)
		if not team then
			team = Instance.new("Team")
			team.Name = info.name
			team.TeamColor = info.brick
			team.AutoAssignable = false
			team.Parent = Teams
		end
		teams[teamId] = team
	end
	return setmetatable({
		_freeRoam = freeRoam,
		_weapons = weapons,
		_state = remote(remotes, "RemoteEvent", RemoteNames.MatchState) :: RemoteEvent,
		_leave = remote(remotes, "RemoteEvent", RemoteNames.MatchLeave) :: RemoteEvent,
		_teams = teams :: { [TeamId]: Team },
		_matches = {} :: { [number]: Match },
		_playerMatch = {} :: { [Player]: Match },
		_usedSlots = {} :: { [number]: boolean },
		_nextId = 0,
	}, MatchService)
end

-- The map model to copy: ServerStorage.Maps first, then the map workshop.
local function mapTemplate(name: string): Model?
	local maps = ServerStorage:FindFirstChild("Maps")
	local stored = maps and maps:FindFirstChild(name)
	if stored and stored:IsA("Model") then
		return stored
	end
	local workshop = Workspace:FindFirstChild("MapWorkshop")
	local built = workshop and workshop:FindFirstChild(name)
	return if built and built:IsA("Model") then built else nil
end

local function floorOrigin(model: Model): Vector3?
	local bounds = model:FindFirstChild("Bounds")
	local area = bounds and bounds:FindFirstChild("PlayArea")
	if area and area:IsA("BasePart") then
		return area.Position - Vector3.new(0, area.Size.Y / 2, 0)
	end
	return nil
end

function MatchService:_placeMap(template: Model, slot: number): Model?
	local sourceOrigin = floorOrigin(template)
	if not sourceOrigin then
		return nil
	end
	local copy = template:Clone()
	-- Test-only extras built at runtime on the workshop map.
	for _, name in { "Armory", "PracticeDummies" } do
		local extra = copy:FindFirstChild(name)
		if extra then
			extra:Destroy()
		end
	end
	copy.Name = string.format("%s_Partida%d", template.Name, slot)
	copy.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local target = MatchConfig.SlotOrigin + Vector3.new(slot * MatchConfig.SlotSpacing, 0, 0)
	copy:PivotTo(copy:GetPivot() + (target - sourceOrigin))
	local spawns = copy:FindFirstChild("Spawns")
	if spawns then
		for _, spawn in spawns:GetDescendants() do
			if spawn:IsA("BasePart") then
				spawn.Transparency = 1
			end
		end
	end
	local folder = Workspace:FindFirstChild("Matches")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Matches"
		folder.Parent = Workspace
	end
	copy.Parent = folder
	return copy
end

local function spawnPoints(model: Model, teamId: TeamId): { BasePart }
	local spawns = model:FindFirstChild("Spawns")
	local folder = spawns and spawns:FindFirstChild("Team" .. teamId)
	local list = {}
	if folder then
		for _, spawn in folder:GetChildren() do
			if spawn:IsA("BasePart") then
				table.insert(list, spawn)
			end
		end
	end
	return list
end

-- What every client of the match is told (and the results at the end).
function MatchService:_view(match: Match, viewer: Player?)
	local roster = {}
	for _, player in match.players do
		local stats = match.stats[player]
		table.insert(roster, {
			userId = player.UserId,
			name = player.DisplayName,
			team = match.team[player],
			kills = if stats then stats.kills else 0,
			deaths = if stats then stats.deaths else 0,
		})
	end
	local info = MapsConfig.Maps[match.mapName]
	return {
		id = match.id,
		phase = match.phase,
		map = match.mapName,
		mapName = if info then info.name else string.upper(match.mapName),
		endsAt = match.endsAt,
		scoreLimit = MatchConfig.ScoreLimit,
		score = { A = match.score.A, B = match.score.B },
		team = if viewer then match.team[viewer] else nil,
		roster = roster,
		result = match.result,
	}
end

function MatchService:_broadcast(match: Match, event: any?)
	for _, player in match.players do
		local view = self:_view(match, player)
		view.event = event
		self._state:FireClient(player, view)
	end
end

function MatchService:_leaderstats(player: Player, stats: Stats?)
	local folder = player:FindFirstChild("leaderstats")
	if not stats then
		if folder then
			folder:Destroy()
		end
		return
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end
	for _, entry in { { "Bajas", stats.kills }, { "Muertes", stats.deaths } } do
		local value: any = folder:FindFirstChild(entry[1])
		if not value then
			value = Instance.new("IntValue")
			value.Name = entry[1]
			value.Parent = folder
		end
		value.Value = entry[2]
	end
end

function MatchService:_watchDeaths(match: Match, player: Player)
	local function hook(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		humanoid.Died:Once(function()
			self:_onDeath(match, player, humanoid)
		end)
	end
	table.insert(match.connections, player.CharacterAdded:Connect(hook))
	if player.Character then
		task.spawn(hook, player.Character)
	end
end

function MatchService:_onDeath(match: Match, victim: Player, humanoid: Humanoid)
	if match.phase ~= "playing" or self._playerMatch[victim] ~= match then
		return
	end
	local victimStats = match.stats[victim]
	victimStats.deaths += 1
	self:_leaderstats(victim, victimStats)
	local attackerId = humanoid:GetAttribute("LastAttacker")
	local killer = if type(attackerId) == "number" then Players:GetPlayerByUserId(attackerId) else nil
	local event = { kind = "kill", victim = victim.DisplayName, victimTeam = match.team[victim] }
	if killer and killer ~= victim and self._playerMatch[killer] == match and match.team[killer] ~= match.team[victim] then
		local killerStats = match.stats[killer]
		killerStats.kills += 1
		self:_leaderstats(killer, killerStats)
		local teamId = match.team[killer]
		match.score[teamId] += 1
		event.killer = killer.DisplayName
		event.killerTeam = teamId
	end
	self:_broadcast(match, event)
	if match.score.A >= MatchConfig.ScoreLimit or match.score.B >= MatchConfig.ScoreLimit then
		self:_finish(match)
	end
end

-- Starts a match for these players (all on this server). Returns ok, error.
function MatchService:Start(players: { Player }, onEnd: ((any) -> ())?): (boolean, string?)
	if #players == 0 then
		return false, "NO_PLAYERS"
	end
	for _, player in players do
		if self._playerMatch[player] then
			return false, "ALREADY_IN_MATCH"
		end
	end
	local mapName = MatchConfig.Maps[math.random(1, #MatchConfig.Maps)]
	local template = mapTemplate(mapName)
	if not template then
		warn("[REALITY 2059] Partida: no existe el mapa " .. mapName .. " (constrúyelo en Studio y guarda el place)")
		return false, "MAP_NOT_FOUND"
	end
	local slot = 0
	while self._usedSlots[slot] do
		slot += 1
	end
	local model = self:_placeMap(template, slot)
	if not model then
		return false, "MAP_NOT_FOUND"
	end
	self._usedSlots[slot] = true
	self._nextId += 1
	local match: Match = {
		id = self._nextId,
		mapName = mapName,
		model = model,
		slot = slot,
		players = table.clone(players),
		team = {},
		stats = {},
		score = { A = 0, B = 0 },
		phase = "countdown",
		endsAt = Workspace:GetServerTimeNow() + MatchConfig.CountdownSeconds,
		result = nil,
		onEnd = onEnd,
		connections = {},
	}
	self._matches[match.id] = match
	-- Balanced teams in roster order: the first half A, the rest B.
	local half = math.ceil(#players / 2)
	local weapons = MatchConfig.StartingWeapons
	if #weapons == 0 then
		weapons = self._weapons:DefaultWeapons()
	end
	for index, player in players do
		local teamId = if index <= half then "A" else "B"
		match.team[player] = teamId
		match.stats[player] = { kills = 0, deaths = 0 }
		self._playerMatch[player] = match
		player.Team = self._teams[teamId]
		player.Neutral = false
		self:_leaderstats(player, match.stats[player])
		local points = spawnPoints(model, teamId)
		self._freeRoam:SetSpawnProvider(player, function(): CFrame?
			if #points == 0 then
				return nil
			end
			return points[math.random(1, #points)].CFrame
		end)
		self._weapons:SetLoadout(player, weapons)
		self:_watchDeaths(match, player)
	end
	print(string.format("[REALITY 2059] Partida %d: %s, %d jugadores", match.id, mapName, #players))
	self:_broadcast(match)
	task.delay(MatchConfig.CountdownSeconds, function()
		if match.phase == "countdown" then
			match.phase = "playing"
			match.endsAt = Workspace:GetServerTimeNow() + MatchConfig.TimeLimitSeconds
			self:_broadcast(match)
		end
	end)
	return true, nil
end

-- Score limit or time: results for everyone, then the map closes.
function MatchService:_finish(match: Match)
	if match.phase == "ended" or match.phase == "closed" then
		return
	end
	match.phase = "ended"
	local winner = if match.score.A > match.score.B then "A" elseif match.score.B > match.score.A then "B" else "draw"
	match.result = { winner = winner }
	match.endsAt = Workspace:GetServerTimeNow() + MatchConfig.ResultsSeconds
	for _, player in match.players do
		self._weapons:ClearLoadout(player)
		self._freeRoam:SetSpawnProvider(player, nil)
		self._freeRoam:Remove(player)
	end
	self:_broadcast(match)
	if match.onEnd then
		task.spawn(match.onEnd, match.result)
	end
	task.delay(MatchConfig.ResultsSeconds, function()
		self:_close(match)
	end)
end

function MatchService:_release(match: Match, player: Player)
	if self._playerMatch[player] ~= match then
		return
	end
	self._playerMatch[player] = nil
	if player.Parent == Players then
		player.Team = nil
		player.Neutral = true
		self:_leaderstats(player, nil)
		self._weapons:ClearLoadout(player)
		self._freeRoam:SetSpawnProvider(player, nil)
		self._freeRoam:Remove(player)
		self._state:FireClient(player, { id = match.id, phase = "closed" })
	end
end

function MatchService:_close(match: Match)
	if match.phase == "closed" then
		return
	end
	match.phase = "closed"
	for _, player in table.clone(match.players) do
		self:_release(match, player)
	end
	for _, connection in match.connections do
		connection:Disconnect()
	end
	if match.model.Parent then
		match.model:Destroy()
	end
	self._usedSlots[match.slot] = nil
	self._matches[match.id] = nil
end

-- A player leaves during the match (MatchLeave, or leaving the game).
function MatchService:_removePlayer(player: Player)
	local match = self._playerMatch[player]
	if not match then
		return
	end
	self:_release(match, player)
	local index = table.find(match.players, player)
	if index then
		table.remove(match.players, index)
	end
	if #match.players == 0 then
		self:_close(match)
	elseif match.phase ~= "ended" then
		self:_broadcast(match, { kind = "left", victim = player.DisplayName })
	end
end

function MatchService:IsInMatch(player: Player): boolean
	return self._playerMatch[player] ~= nil
end

function MatchService:Run()
	self._leave.OnServerEvent:Connect(function(player: Player)
		self:_removePlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:_removePlayer(player)
	end)
	-- The clock: end matches whose time ran out.
	RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for _, match in self._matches do
			if match.phase == "playing" and now >= match.endsAt then
				self:_finish(match)
			end
		end
	end)
end

return MatchService
