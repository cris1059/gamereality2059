--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local gameConfig = require(root.Config.GameConfig)
local morphLabConfig = require(root.Config.MorphLabConfig)
local PlayerState = require(root.State.PlayerState)
local DevConfig = require(root.Config.DevConfig)
local CharacterDraft = require(root.Character.CharacterDraft)
local RemoteNames = require(root.Network.RemoteNames)
local MorphLabController = require(script.MorphLab.MorphLabController)
local LobbyController = require(script.Lobby.LobbyController)
local FreeRoamController = require(script.FreeRoam.FreeRoamController)
local CityDressingFX = require(script.FreeRoam.CityDressingFX)
local ModuleLoadingScreen = require(script.Transition.ModuleLoadingScreen)
local BitmapText = require(script.UI.BitmapText)
local PartyController = require(script.Party.PartyController)
local MatchOverlay = require(script.Party.MatchOverlay)
local MatchController = require(script.Match.MatchController)
local PerfOverlay = require(script.Debug.PerfOverlay)
local UserInputService = game:GetService("UserInputService")
local runtime = root:WaitForChild("Runtime")

if runtime:GetAttribute("ServerReady") ~= true then
	runtime:GetAttributeChangedSignal("ServerReady"):Wait()
end

local remotes = runtime:WaitForChild(RemoteNames.Folder)
local stateChanged = remotes:WaitForChild(RemoteNames.PlayerStateChanged) :: RemoteEvent
local getPlayerState = remotes:WaitForChild(RemoteNames.GetPlayerState) :: RemoteFunction
local saveCharacter = remotes:WaitForChild(RemoteNames.SaveCharacter) :: RemoteFunction
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
local morphLab = MorphLabController.new(playerGui, morphLabConfig)
local lobby = LobbyController.new(playerGui, morphLabConfig)
local freeRoam = FreeRoamController.new(playerGui, morphLabConfig)
CityDressingFX.Start()
PerfOverlay.Start(playerGui, morphLabConfig.Typography.Technical)
local moduleLoading = ModuleLoadingScreen.new(playerGui, morphLabConfig)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CyberpunkBootstrapUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 100

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(3, 19, 48)
backdrop.BackgroundTransparency = 0
backdrop.BorderSizePixel = 0
backdrop.Parent = screenGui

local backdropGradient = Instance.new("UIGradient")
backdropGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(2, 10, 30)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(7, 39, 78)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(1, 12, 34)),
})
backdropGradient.Rotation = 90
backdropGradient.Parent = backdrop

local backgroundImage = Instance.new("ImageLabel")
backgroundImage.Name = "NeoEdenBackground"
backgroundImage.Size = UDim2.fromScale(1, 1)
backgroundImage.BackgroundTransparency = 1
backgroundImage.Image = morphLabConfig.StartScreen.BackgroundImageId
backgroundImage.ScaleType = Enum.ScaleType.Crop
backgroundImage.Visible = not morphLabConfig.StartScreen.UseNativeBackground
	and morphLabConfig.StartScreen.BackgroundImageId ~= ""
backgroundImage.ImageTransparency = if backgroundImage.Visible then 1 else 0
backgroundImage.ZIndex = 1
backgroundImage.Parent = backdrop

local mosaic = Instance.new("Frame")
mosaic.Name = "NeoEdenHighResolutionMosaic"
mosaic.Size = UDim2.fromScale(1, 1)
mosaic.BackgroundTransparency = 1
mosaic.ZIndex = 1
mosaic.Visible = morphLabConfig.StartScreen.BackgroundLeftImageId ~= ""
	and morphLabConfig.StartScreen.BackgroundRightImageId ~= ""
	and not morphLabConfig.StartScreen.UseNativeBackground
mosaic.Parent = backdrop
for index, imageId in ipairs({
	morphLabConfig.StartScreen.BackgroundLeftImageId,
	morphLabConfig.StartScreen.BackgroundRightImageId,
}) do
	local tile = Instance.new("ImageLabel")
	tile.Name = if index == 1 then "Left" else "Right"
	tile.Position = UDim2.fromScale((index - 1) * 0.5, 0)
	tile.Size = UDim2.fromScale(0.5, 1)
	tile.BackgroundTransparency = 1
	tile.Image = imageId
	tile.ScaleType = Enum.ScaleType.Stretch
	tile.ZIndex = 1
	tile.Parent = mosaic
end
if mosaic.Visible then
	backgroundImage.Visible = false
	backgroundImage.ImageTransparency = 1
end

local blankaOverlay = Instance.new("ImageLabel")
blankaOverlay.Name = "BlankaStartTypography"
blankaOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
blankaOverlay.Position = UDim2.fromScale(0.5, 0.5)
blankaOverlay.Size = UDim2.fromScale(1, 1)
blankaOverlay.BackgroundTransparency = 1
blankaOverlay.Image = morphLabConfig.StartScreen.BlankaOverlayImageId
blankaOverlay.ScaleType = Enum.ScaleType.Fit
blankaOverlay.Active = false
blankaOverlay.Visible = morphLabConfig.StartScreen.BlankaOverlayImageId ~= ""
blankaOverlay.ImageTransparency = if blankaOverlay.Visible then 1 else 0
blankaOverlay.ZIndex = 4
blankaOverlay.Parent = backdrop

local proceduralLayer = Instance.new("Frame")
proceduralLayer.Name = "ProceduralFallback"
proceduralLayer.Size = UDim2.fromScale(1, 1)
proceduralLayer.BackgroundTransparency = 1
proceduralLayer.Visible = not morphLabConfig.StartScreen.UseNativeBackground
proceduralLayer.Parent = backdrop

local nativeScene = Instance.new("Frame")
nativeScene.Name = "NativeNeoEden"
nativeScene.Size = UDim2.fromScale(1, 1)
nativeScene.BackgroundColor3 = Color3.fromRGB(2, 5, 12)
nativeScene.BorderSizePixel = 0
nativeScene.ClipsDescendants = true
nativeScene.Visible = morphLabConfig.StartScreen.UseNativeBackground
nativeScene.ZIndex = 1
nativeScene.Parent = backdrop
local nativeGradient = Instance.new("UIGradient")
nativeGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(2, 5, 12)),
	ColorSequenceKeypoint.new(0.52, Color3.fromRGB(8, 11, 20)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 4, 18)),
})
nativeGradient.Rotation = 90
nativeGradient.Parent = nativeScene

local function nativeFrame(name: string, size: UDim2, position: UDim2, color: Color3, transparency: number, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	frame.Parent = nativeScene
	return frame
end

local planetGlow = nativeFrame("PlanetGlow", UDim2.new(0.62, 0, 1.1, 0), UDim2.new(0.5, 0, -0.3, 0), Color3.fromRGB(183, 15, 120), 0.68, 1)
planetGlow.AnchorPoint = Vector2.new(0.5, 0)
local planetGlowAspect = Instance.new("UIAspectRatioConstraint")
planetGlowAspect.AspectRatio = 1
planetGlowAspect.Parent = planetGlow
local planetGlowCorner = Instance.new("UICorner")
planetGlowCorner.CornerRadius = UDim.new(1, 0)
planetGlowCorner.Parent = planetGlow
local glowGradient = Instance.new("UIGradient")
glowGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 16, 136)),
	ColorSequenceKeypoint.new(0.48, Color3.fromRGB(18, 10, 28)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 218, 255)),
})
glowGradient.Rotation = 25
glowGradient.Parent = planetGlow

local planet = nativeFrame("Planet", UDim2.new(0.595, 0, 1.055, 0), UDim2.new(0.5, 0, -0.285, 0), Color3.fromRGB(3, 6, 11), 0, 2)
planet.AnchorPoint = Vector2.new(0.5, 0)
local planetAspect = Instance.new("UIAspectRatioConstraint")
planetAspect.AspectRatio = 1
planetAspect.Parent = planet
local planetCorner = Instance.new("UICorner")
planetCorner.CornerRadius = UDim.new(1, 0)
planetCorner.Parent = planet
local planetShade = Instance.new("UIGradient")
planetShade.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 7, 21)),
	ColorSequenceKeypoint.new(0.38, Color3.fromRGB(3, 5, 10)),
	ColorSequenceKeypoint.new(0.76, Color3.fromRGB(2, 5, 10)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 22, 31)),
})
planetShade.Rotation = 20
planetShade.Parent = planet

local skylineData = {
	{ 0.02, 0.055, 0.26 }, { 0.075, 0.036, 0.37 }, { 0.12, 0.06, 0.22 },
	{ 0.18, 0.032, 0.48 }, { 0.225, 0.06, 0.3 }, { 0.285, 0.045, 0.42 },
	{ 0.34, 0.055, 0.25 }, { 0.405, 0.038, 0.34 }, { 0.46, 0.055, 0.23 },
	{ 0.515, 0.048, 0.29 }, { 0.575, 0.055, 0.2 }, { 0.63, 0.036, 0.39 },
	{ 0.68, 0.06, 0.28 }, { 0.75, 0.04, 0.47 }, { 0.805, 0.055, 0.34 },
	{ 0.87, 0.038, 0.58 }, { 0.915, 0.07, 0.4 }, { 0.975, 0.04, 0.3 },
}
for index, entry in skylineData do
	local building = nativeFrame(
		"Tower" .. index,
		UDim2.new(entry[2], 0, entry[3], 0),
		UDim2.new(entry[1], 0, 0.86 - entry[3], 0),
		Color3.fromRGB(4 + index % 3, 7, 14 + index % 4),
		0,
		3
	)
	building.AnchorPoint = Vector2.new(0.5, 0)
	local strip = Instance.new("Frame")
	strip.Name = "NeonStrip"
	strip.Size = UDim2.new(0, 2, 0.62, 0)
	strip.Position = UDim2.new(if index % 2 == 0 then 0.18 else 0.78, 0, 0.18, 0)
	strip.BackgroundColor3 = if index % 3 == 0 then Color3.fromRGB(0, 221, 255) else Color3.fromRGB(255, 20, 151)
	strip.BackgroundTransparency = 0.12
	strip.BorderSizePixel = 0
	strip.ZIndex = 4
	strip.Parent = building
	if index % 4 == 0 then
		local antenna = Instance.new("Frame")
		antenna.Name = "Antenna"
		antenna.AnchorPoint = Vector2.new(0.5, 1)
		antenna.Position = UDim2.fromScale(0.5, 0)
		antenna.Size = UDim2.new(0, 2, 0.17, 0)
		antenna.BackgroundColor3 = strip.BackgroundColor3
		antenna.BorderSizePixel = 0
		antenna.ZIndex = 4
		antenna.Parent = building
	end
end

local horizon = nativeFrame("HorizonFog", UDim2.new(1, 0, 0.16, 0), UDim2.new(0, 0, 0.75, 0), Color3.fromRGB(38, 29, 49), 0.45, 4)
local horizonGradient = Instance.new("UIGradient")
horizonGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.45, 0.25),
	NumberSequenceKeypoint.new(1, 1),
})
horizonGradient.Rotation = 90
horizonGradient.Parent = horizon

local reflectiveFloor = nativeFrame("ReflectiveFloor", UDim2.new(1, 0, 0.15, 0), UDim2.new(0, 0, 0.85, 0), Color3.fromRGB(2, 4, 9), 0, 5)
local floorShade = Instance.new("UIGradient")
floorShade.Color = ColorSequence.new(Color3.fromRGB(13, 15, 25), Color3.fromRGB(1, 2, 5))
floorShade.Rotation = 90
floorShade.Parent = reflectiveFloor
for index = 1, 15 do
	local reflection = Instance.new("Frame")
	reflection.Name = "Reflection" .. index
	reflection.AnchorPoint = Vector2.new(0.5, 0)
	reflection.Position = UDim2.new(index / 16, 0, 0, 0)
	reflection.Size = UDim2.new(0, if index % 3 == 0 then 3 else 1, 0.55 + (index % 4) * 0.1, 0)
	reflection.BackgroundColor3 = if index % 2 == 0 then Color3.fromRGB(255, 24, 154) else Color3.fromRGB(0, 214, 255)
	reflection.BackgroundTransparency = 0.35
	reflection.BorderSizePixel = 0
	reflection.ZIndex = 6
	reflection.Parent = reflectiveFloor
	local reflectionGradient = Instance.new("UIGradient")
	reflectionGradient.Transparency = NumberSequence.new(0.15, 1)
	reflectionGradient.Rotation = 90
	reflectionGradient.Parent = reflection
end

local function decorationFrame(name: string, size: UDim2, position: UDim2, color: Color3, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.ZIndex = 1
	frame.Parent = proceduralLayer
	return frame
end

-- Stylized laboratory architecture; intentionally built from native UI so the
-- entry screen has no dependency on unlicensed or externally hosted assets.
local ceiling = decorationFrame("LaboratoryCeiling", UDim2.new(1, 0, 0, 76), UDim2.new(), Color3.fromRGB(4, 15, 32), 0.05)
local ceilingStroke = Instance.new("UIStroke")
ceilingStroke.Color = Color3.fromRGB(222, 35, 58)
ceilingStroke.Thickness = 2
ceilingStroke.Transparency = 0.25
ceilingStroke.Parent = ceiling

local ceilingBeams = {}
for index = 0, 7 do
	local beam = decorationFrame(
		"CeilingBeam" .. index,
		UDim2.new(0, 3, 0.34, 0),
		UDim2.new(index / 7, 0, 0, 76),
		Color3.fromRGB(192, 32, 52),
		0.28
	)
	beam.Rotation = if index < 4 then -18 else 18
	table.insert(ceilingBeams, { frame = beam, base = beam.Rotation, phase = index * 0.7 })
end

for index, side in { -1, 1 } do
	local xScale = if side < 0 then 0.055 else 0.945
	local chamber = decorationFrame(
		"ContainmentChamber" .. index,
		UDim2.new(0.19, 0, 0.58, 0),
		UDim2.new(xScale, 0, 0.2, 0),
		Color3.fromRGB(5, 47, 82),
		0.2
	)
	chamber.AnchorPoint = Vector2.new(if side < 0 then 0 else 1, 0)
	local chamberCorner = Instance.new("UICorner")
	chamberCorner.CornerRadius = UDim.new(0, 18)
	chamberCorner.Parent = chamber
	local chamberStroke = Instance.new("UIStroke")
	chamberStroke.Color = Color3.fromRGB(28, 139, 190)
	chamberStroke.Thickness = 2
	chamberStroke.Transparency = 0.18
	chamberStroke.Parent = chamber
	local glass = decorationFrame(
		"ChamberGlass" .. index,
		UDim2.new(0.13, 0, 0.39, 0),
		UDim2.new(if side < 0 then 0.085 else 0.915, 0, 0.285, 0),
		Color3.fromRGB(26, 111, 151),
		0.65
	)
	glass.AnchorPoint = Vector2.new(if side < 0 then 0 else 1, 0)
	local warning = decorationFrame(
		"WarningLight" .. index,
		UDim2.new(0, 9, 0.28, 0),
		UDim2.new(if side < 0 then 0.065 else 0.935, 0, 0.34, 0),
		Color3.fromRGB(255, 38, 62),
		0.05
	)
	warning.AnchorPoint = Vector2.new(0.5, 0)
end

local floor = decorationFrame("LaboratoryFloor", UDim2.new(1, 0, 0.22, 0), UDim2.new(0, 0, 0.78, 0), Color3.fromRGB(2, 12, 27), 0.05)
local floorGradient = Instance.new("UIGradient")
floorGradient.Color = ColorSequence.new(Color3.fromRGB(14, 50, 74), Color3.fromRGB(1, 7, 20))
floorGradient.Rotation = 90
floorGradient.Parent = floor
for index = 1, 5 do
	local line = decorationFrame("FloorGuide" .. index, UDim2.new(0.7, 0, 0, 2), UDim2.new(0.15, 0, 0.79 + index * 0.035, 0), Color3.fromRGB(183, 28, 47), 0.3)
	line.AnchorPoint = Vector2.new(0, 0.5)
end

local accent = Instance.new("Frame")
accent.Name = "NeonAccent"
accent.AnchorPoint = Vector2.new(0.5, 0.5)
accent.Position = UDim2.fromScale(0.5, 0.5)
accent.Size = UDim2.new(0.72, 0, 0, 3)
accent.BorderSizePixel = 0
accent.BackgroundColor3 = Color3.fromRGB(239, 36, 58)
accent.ZIndex = 2
accent.Parent = backdrop

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 1)
title.Position = UDim2.new(0.5, 0, 0.54, 0)
title.Size = UDim2.new(0.64, 0, 0, 210)
title.BackgroundTransparency = 1
title.Font = morphLabConfig.Typography.Display
title.Text = "REALITY\n2059"
title.TextColor3 = morphLabConfig.Palette.Text
title.TextScaled = true
title.ZIndex = 3
title:SetAttribute("BlankaGlow", true)
title.Parent = backdrop

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0)
status.Position = UDim2.new(0.5, 0, 0.59, 0)
status.Size = UDim2.new(0.85, 0, 0, 48)
status.BackgroundTransparency = 1
status.Font = morphLabConfig.Typography.Interface
status.TextColor3 = morphLabConfig.Palette.Cyan
status.TextScaled = true
status.Text = ""
status.ZIndex = 3
status.Parent = backdrop

local constraint = Instance.new("UITextSizeConstraint")
constraint.MaxTextSize = 28
constraint.MinTextSize = 14
constraint.Parent = status

local startButton = Instance.new("TextButton")
startButton.Name = "Start"
startButton.AnchorPoint = Vector2.new(0.5, 0)
startButton.Position = UDim2.new(0.5, 0, 0.67, 0)
startButton.Size = UDim2.fromOffset(320, 58)
startButton.BackgroundColor3 = Color3.fromRGB(10, 28, 40)
startButton.BackgroundTransparency = 0.12
startButton.BorderSizePixel = 0
startButton.AutoButtonColor = true
startButton.Font = morphLabConfig.Typography.Display
startButton.Text = "INICIAR"
startButton.TextColor3 = morphLabConfig.Palette.Text
startButton.TextSize = 20
startButton.ZIndex = 3
startButton:SetAttribute("BlankaGlow", false)
startButton.Parent = backdrop
local startCorner = Instance.new("UICorner")
startCorner.CornerRadius = UDim.new(0, 6)
startCorner.Parent = startButton
local startStroke = Instance.new("UIStroke")
startStroke.Color = morphLabConfig.Palette.Cyan
startStroke.Thickness = 1.5
startStroke.Transparency = 0.15
startStroke.Parent = startButton

-- The title screen breathes while it is on screen: the planet's glow turns,
-- the ceiling beams sweep, the neon accent and INICIAR pulse.
RunService.RenderStepped:Connect(function()
	if not backdrop.Visible then
		return
	end
	local t = os.clock()
	glowGradient.Rotation = 25 + math.sin(t * 0.25) * 20
	planetGlow.BackgroundTransparency = 0.62 + 0.08 * math.sin(t * 0.8)
	for _, beam in ceilingBeams do
		beam.frame.Rotation = beam.base + math.sin(t * 0.6 + beam.phase) * 6
	end
	accent.BackgroundTransparency = 0.1 + 0.3 * (0.5 + 0.5 * math.sin(t * 2.2))
	startStroke.Transparency = 0.05 + 0.55 * (0.5 + 0.5 * math.sin(t * 3))
end)


screenGui.Parent = playerGui
BitmapText.BindTree(screenGui, morphLabConfig.Typography)
if blankaOverlay.Visible then
	task.spawn(function()
		local overlayOk, overlayError = pcall(function()
			ContentProvider:PreloadAsync({ blankaOverlay })
		end)
		if overlayOk and blankaOverlay.Parent then
			blankaOverlay.ImageTransparency = 0
			title.Visible = false
			startButton.TextTransparency = 1
		else
			blankaOverlay.Visible = false
			warn("[REALITY 2059] BLANKA overlay failed; using native typography: " .. tostring(overlayError))
		end
	end)
end
if mosaic.Visible then
	task.spawn(function()
		local preloadOk, preloadError = pcall(function()
			ContentProvider:PreloadAsync({ mosaic, blankaOverlay })
		end)
		if preloadOk and mosaic.Parent then
			proceduralLayer.Visible = false
		elseif not preloadOk then
			warn("[REALITY 2059] High resolution START assets failed; using procedural fallback: " .. tostring(preloadError))
			mosaic.Visible = false
			backgroundImage.Visible = morphLabConfig.StartScreen.BackgroundImageId ~= ""
		end
	end)
elseif backgroundImage.Visible then
	task.spawn(function()
		local preloadOk, preloadError = pcall(function()
			ContentProvider:PreloadAsync({ backgroundImage })
		end)
		if preloadOk and backgroundImage.Parent then
			backgroundImage.ImageTransparency = 0
			proceduralLayer.Visible = false
		elseif not preloadOk then
			warn("[REALITY 2059] Start background preload failed; using procedural fallback: " .. tostring(preloadError))
		end
	end)
end

local hasStarted = false
-- Once the player has been routed (MORPHLAB or the hub), later state pushes
-- (e.g. after saving the character) only refresh latestResult.
local sessionRouted = false
local requestInFlight = false
local latestResult: any = { state = PlayerState.LOADING }
-- The saved character every destination uses.
local currentCharacter: any = nil
-- MORPHLAB opened from PERSONAJE: Esc goes back to the hub without saving.
local editingFromHub = false
local party = PartyController.new(playerGui, morphLabConfig)
lobby:SetParty(party)
local matchOverlay = MatchOverlay.new(playerGui, morphLabConfig, party)

local function showRetry(message: string)
	status.Text = message
	status.TextColor3 = Color3.fromRGB(255, 80, 105)
	backdrop.Visible = true
	startButton.Visible = true
	startButton.Text = "REINTENTAR"
	startButton.Active = true
	startButton.AutoButtonColor = true
end

-- The hub (the lobby with the main menu) is home: after logging in, after
-- MORPHLAB and after free roam.
local function showHub()
	editingFromHub = false
	morphLab:Deactivate()
	if lobby:IsActive() then
		backdrop.Visible = false
		return
	end
	moduleLoading:Show("ENTRANDO AL LOBBY")
	moduleLoading:SetStage("CARGANDO PLATAFORMA CENTRAL", 0.6)
	-- Any error inside the lobby is reported instead of freezing the loading screen.
	local started = os.clock()
	local callOk, entered, lobbyError = xpcall(function()
		return lobby:Activate(currentCharacter, latestResult and latestResult.data)
	end, debug.traceback)
	moduleLoading:Finish()
	if not callOk then
		warn("[REALITY 2059] Lobby error: " .. tostring(entered))
		lobbyError = "ERROR_INTERNO (ver consola F9)"
		entered = false
		lobby:Deactivate()
	end
	print(string.format("[REALITY 2059] Lobby %s en %.1f s", if entered then "listo" else "falló", os.clock() - started))
	if entered then
		backdrop.Visible = false
	else
		warn("[REALITY 2059] Lobby unavailable: " .. tostring(lobbyError))
		showRetry("NO SE PUDO ABRIR EL LOBBY // " .. tostring(lobbyError))
	end
end

local function render(result: any)
	local state = result.state
	if state == PlayerState.LOADING then
		morphLab:Deactivate()
		moduleLoading:SetStage("CARGANDO PERFIL SEGURO", 0.24)
		status.Text = "CONECTANDO // CARGANDO PERFIL"
		status.TextColor3 = morphLabConfig.Palette.Cyan
		backdrop.Visible = true
	elseif state == PlayerState.NEW_PLAYER then
		startButton.Visible = false
		status.Text = "INICIALIZANDO MORPHLAB // 2059"
		status.TextColor3 = morphLabConfig.Palette.Magenta
		backdrop.Visible = true
		moduleLoading:SetStage("DIRIGIENDO A MORPHLAB", 0.34)
		local activated, activationError = morphLab:Activate(function(stage: string, progress: number)
			moduleLoading:SetStage(stage, progress)
		end)
		moduleLoading:Finish()
		if activated then
			sessionRouted = true
			backdrop.Visible = false
		else
			showRetry("FALLÓ LA CONEXIÓN CON MORPHLAB // " .. tostring(activationError or "REINTENTA LA SESIÓN"))
		end
	elseif state == PlayerState.EXISTING_PLAYER then
		moduleLoading:SetStage("PREPARANDO NEO-EDEN", 0.88)
		morphLab:Deactivate()
		status.Text = "IDENTIDAD RESTAURADA // ACCESO CONCEDIDO"
		status.TextColor3 = Color3.fromRGB(90, 255, 180)
		startButton.Visible = false
		local character = result.data and result.data.character
		moduleLoading:Finish()
		if character ~= nil then
			currentCharacter = character
			sessionRouted = true
			showHub()
		else
			showRetry("PERFIL SIN PERSONAJE // REINTENTA")
		end
	elseif state == PlayerState.DATA_ERROR then
		morphLab:Deactivate()
		lobby:Deactivate()
		moduleLoading:Finish()
		showRetry("FALLÓ LA CARGA DE DATOS // NO SE SOBRESCRIBIÓ NADA")
	else
		morphLab:Deactivate()
		status.Text = "ESTADO DE SESIÓN DESCONOCIDO"
		status.TextColor3 = Color3.fromRGB(255, 80, 105)
		backdrop.Visible = true
	end
end

stateChanged.OnClientEvent:Connect(function(result)
	latestResult = result
	if hasStarted and not sessionRouted then
		render(result)
	end
end)
local ok, initialResult = pcall(function()
	return getPlayerState:InvokeServer()
end)
if ok then
	latestResult = initialResult
else
	latestResult = { state = PlayerState.DATA_ERROR }
end

local function beginSession()
	if requestInFlight then
		return
	end
	hasStarted = true
	requestInFlight = true
	startButton.Active = false
	startButton.AutoButtonColor = false
	startButton.Text = "CONECTANDO..."
	status.Text = "VERIFICANDO IDENTIDAD // 2059"
	status.TextColor3 = morphLabConfig.Palette.Cyan
	moduleLoading:Show("PREPARANDO DESTINO")
	moduleLoading:SetStage("VERIFICANDO IDENTIDAD", 0.12)
	task.defer(function()
		local stateOk, result = pcall(function()
			return getPlayerState:InvokeServer()
		end)
		requestInFlight = false
		if stateOk then
			latestResult = result
			render(result)
		else
			latestResult = { state = PlayerState.DATA_ERROR }
			render(latestResult)
		end
	end)
end

-- INICIAR starts the session; after a failed hub load it retries the hub.
startButton.Activated:Connect(function()
	if sessionRouted and currentCharacter then
		startButton.Visible = false
		showHub()
	else
		beginSession()
	end
end)

-- MORPHLAB -> hub when the character is finished. The character is saved
-- on the server first; if that fails the player stays in MORPHLAB with the
-- draft intact instead of entering with nothing saved.
morphLab:SetConfirmHandler(function(character)
	character.creationComplete = true
	moduleLoading:Show("GUARDANDO IDENTIDAD")
	moduleLoading:SetStage("SINCRONIZANDO CON EL SERVIDOR", 0.3)
	local invokeOk, saveResult = pcall(function()
		return saveCharacter:InvokeServer(character)
	end)
	if not invokeOk or type(saveResult) ~= "table" or not saveResult.ok then
		moduleLoading:Finish()
		local reason = if invokeOk and type(saveResult) == "table" then saveResult.errorCode else saveResult
		warn("[REALITY 2059] No se pudo guardar el personaje: " .. tostring(reason))
		party:Toast("NO SE PUDO GUARDAR TU PERSONAJE // INTÉNTALO DE NUEVO", Color3.fromRGB(255, 80, 105))
		return
	end
	currentCharacter = character
	moduleLoading:Finish()
	showHub()
end)

-- Destinations. Each one comes back to the hub when it ends or fails.
-- options.shooter: the third-person shooter setup (map tests, later matches).
local function enterFreeRoam(character, options: { shooter: boolean?, map: string? }?)
	if freeRoam:IsActive() then
		return
	end
	lobby:Deactivate()
	morphLab:Deactivate()
	moduleLoading:Show("ENTRANDO A NEO-EDEN")
	moduleLoading:SetStage(if options and options.shooter then "CARGANDO MAPA" else "CARGANDO MODO LIBRE", 0.5)
	local entered, roamError = freeRoam:Activate(character, options)
	moduleLoading:Finish()
	if entered then
		backdrop.Visible = false
	else
		warn("[REALITY 2059] Free roam unavailable: " .. tostring(roamError))
		showHub()
	end
end
local function enterMorphLab()
	lobby:Deactivate()
	morphLab:LoadDraft(currentCharacter)
	local reopened, reopenError = morphLab:Activate()
	if reopened then
		editingFromHub = true
		backdrop.Visible = false
		party:Toast("ESC  ·  VOLVER AL LOBBY SIN GUARDAR")
	else
		warn("[REALITY 2059] MORPHLAB could not reopen: " .. tostring(reopenError))
		showHub()
	end
end

-- JUGAR goes through the squad: the leader (or a solo player) starts —
-- MODO LIBRE launches everyone, the other modes search a match — and
-- members toggle LISTO.
lobby:SetPlayHandler(function(mode: string)
	party:Play(mode)
end)
lobby:SetOperatorHandler(enterMorphLab)
party:SetLaunchHandler(function(mode)
	if mode == "free" and currentCharacter then
		enterFreeRoam(currentCharacter)
	end
end)
party:SetChangedHandler(function(snapshot)
	lobby:OnPartyChanged(snapshot)
	matchOverlay:OnPartyChanged(snapshot)
end)
-- Matches on this server (private rooms): the server says when to enter the
-- map (shooter mode) and when it is over (back to the hub, results on top).
local matchController = MatchController.new(playerGui, function(mapKey: string)
	if not currentCharacter then
		warn("[REALITY 2059] Partida: no hay personaje guardado")
		return
	end
	enterFreeRoam(currentCharacter, { shooter = true, map = mapKey })
end, function()
	if freeRoam:IsActive() then
		freeRoam:Deactivate()
	end
	showHub()
end)
-- MENÚ in the free-roam HUD returns to the hub.
freeRoam:SetExitHandler(function()
	freeRoam:Deactivate()
	showHub()
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not editingFromHub or not morphLab:IsActive() then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
		showHub()
	end
end)

-- STUDIO QUICK START (Config/DevConfig.QuickStart): skips the INICIAR menu.
-- Lobby / free roam use DevConfig.Character through the validated setters.
local function devCharacter()
	local draft = CharacterDraft.createDefault()
	local spec = DevConfig.Character or {}
	local function apply(label: string, ok: boolean, problem: string?)
		if not ok then
			warn(string.format("[REALITY 2059] DevConfig.Character.%s rechazado: %s", label, tostring(problem)))
		end
	end
	if spec.bodyBaseId then apply("bodyBaseId", CharacterDraft.setBodyBase(draft, spec.bodyBaseId)) end
	if spec.skinToneId then apply("skinToneId", CharacterDraft.setSkinTone(draft, spec.skinToneId)) end
	if spec.faceId then apply("faceId", CharacterDraft.setFace(draft, spec.faceId)) end
	if spec.hairId then apply("hairId", CharacterDraft.setHair(draft, spec.hairId)) end
	if spec.outfitId then apply("outfitId", CharacterDraft.setOutfit(draft, spec.outfitId)) end
	for _, accessoryId in spec.accessories or {} do
		apply("accessories", CharacterDraft.toggleAccessory(draft, accessoryId))
	end
	if spec.classId then apply("classId", CharacterDraft.setClass(draft, spec.classId)) end
	for _, implantId in spec.implants or {} do
		apply("implants", CharacterDraft.toggleImplant(draft, implantId))
	end
	for slot, colorId in spec.colors or {} do
		apply("colors." .. slot, CharacterDraft.setColor(draft, slot, colorId))
	end
	draft.creationComplete = true
	return draft
end

local quickStart = if RunService:IsStudio() then DevConfig.QuickStart else false
if quickStart then
	print("[REALITY 2059] Inicio rápido de Studio: " .. tostring(quickStart) .. " (Config/DevConfig.QuickStart)")
	task.defer(function()
		if quickStart == "MorphLab" then
			beginSession()
			return
		end
		currentCharacter = devCharacter()
		sessionRouted = true
		startButton.Visible = false
		if quickStart == "FreeRoam" then
			enterFreeRoam(currentCharacter)
		elseif quickStart == "MapTest" then
			-- Free roam on the server, spawning on the map, in shooter mode.
			enterFreeRoam(currentCharacter, { shooter = true, map = DevConfig.MapTest })
		elseif quickStart == "Lobby" then
			showHub()
		else
			warn("[REALITY 2059] Inicio rápido desconocido (" .. tostring(quickStart) .. "); usa el menú")
			startButton.Visible = true
		end
	end)
end

script.Destroying:Connect(function()
	morphLab:Destroy()
	lobby:Destroy()
	freeRoam:Destroy()
	matchOverlay:Destroy()
	party:Destroy()
	moduleLoading:Destroy()
end)

print(string.format("[%s] Client infrastructure ready; lobby: %s", gameConfig.GameName, gameConfig.LobbyName))
