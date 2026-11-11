--!strict

-- The hub: REALITY 2059's main menu, drawn over the lobby scene (character
-- on the rooftop, squad on the rings, city behind). One navigation bar
-- (JUGAR / PERSONAJE / ESCUADRÓN / AJUSTES / CRÉDITOS), the game modes in one
-- place, one main button whose label always says what it will do, and the
-- squad always visible at the bottom. Pure view: LobbyController feeds the
-- state and receives the callbacks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CharacterCatalog = require(ReplicatedStorage:WaitForChild("CyberpunkOnline").Catalog.CharacterCatalog)
local CharacterDraft = require(ReplicatedStorage:WaitForChild("CyberpunkOnline").Character.CharacterDraft)
local ShopConfig = require(ReplicatedStorage:WaitForChild("CyberpunkOnline").Config.ShopConfig)

local HubUI = {}
HubUI.__index = HubUI

local CARD = Color3.fromRGB(13, 18, 30)
local MUTED = Color3.fromRGB(135, 148, 172)
local GOOD = Color3.fromRGB(90, 255, 160)
local WARN = Color3.fromRGB(255, 190, 60)
local BAD = Color3.fromRGB(255, 80, 105)
local DARK_TEXT = Color3.fromRGB(12, 6, 14)
local QUICK = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE = TweenInfo.new(0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

-- Left column (pages, main button, location card), in 1280x720 units.
local CONTENT_WIDTH = 340
local CONTENT_TOP = 124
local SQUAD_PANEL_WIDTH = 400

local CLASS_NAMES = { runner = "CORREDOR", netrunner = "NETRUNNER", enforcer = "EJECUTOR", ghost = "FANTASMA", medtech = "MEDTECH" }
local STAT_NAMES = { speed = "VELOCIDAD", armor = "BLINDAJE", hacking = "HACKEO", stealth = "SIGILO", support = "SOPORTE" }
local STAT_ORDER = { "speed", "armor", "hacking", "stealth", "support" }

-- First character of a display name (UTF-8 safe), upper-cased.
local function initialOf(name: string): string
	local second = utf8.offset(name, 2)
	return string.upper(if second then string.sub(name, 1, second - 1) else name)
end

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function stroke(parent: Instance, color: Color3, transparency: number, thickness: number?): UIStroke
	local item = Instance.new("UIStroke")
	item.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	item.Color = color
	item.Transparency = transparency
	item.Thickness = thickness or 1
	item.Parent = parent
	return item
end

local function frame(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, transparency: number): Frame
	local item = Instance.new("Frame")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundColor3 = color
	item.BackgroundTransparency = transparency
	item.BorderSizePixel = 0
	item.Parent = parent
	return item
end

local function label(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, font: Enum.Font, textSize: number, color: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundTransparency = 1
	item.Font = font
	item.Text = text
	item.TextSize = textSize
	item.TextColor3 = color
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextWrapped = true
	item.Parent = parent
	return item
end

local function textButton(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, font: Enum.Font, textSize: number, accent: Color3): TextButton
	local item = Instance.new("TextButton")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundColor3 = CARD
	item.BackgroundTransparency = 0.1
	item.BorderSizePixel = 0
	item.AutoButtonColor = true
	item.Font = font
	item.Text = text
	item.TextSize = textSize
	item.TextColor3 = Color3.fromRGB(234, 244, 255)
	item.Parent = parent
	corner(item, 4)
	stroke(item, accent, 0.35)
	return item
end

-- Small 3D icon scenes (ViewportFrame) for the mode cards.
local function iconPart(world: WorldModel, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?)
	local item = Instance.new("Part")
	item.Anchored = true
	item.Size = size
	item.CFrame = cframe
	item.Color = color
	item.Material = material
	item.Shape = shape or Enum.PartType.Block
	item.Parent = world
end

local METAL = Color3.fromRGB(150, 160, 180)
local ICONS = {
	multiplayer = function(w: WorldModel, accent: Color3)
		iconPart(w, Vector3.new(1.7, 0.16, 0.16), CFrame.new(), accent, Enum.Material.Neon)
		iconPart(w, Vector3.new(0.5, 0.5, 0.5), CFrame.new(-0.8, 0, 0), accent, Enum.Material.Neon, Enum.PartType.Ball)
		iconPart(w, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0.8, 0, 0), accent, Enum.Material.Neon, Enum.PartType.Ball)
		iconPart(w, Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, 0, 0), METAL, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end,
	free = function(w: WorldModel, accent: Color3)
		iconPart(w, Vector3.new(0.2, 2.2, 2.2), CFrame.Angles(0, math.rad(90), 0), accent, Enum.Material.Neon, Enum.PartType.Cylinder)
		iconPart(w, Vector3.new(0.24, 1.8, 1.8), CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(20, 10, 30), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		iconPart(w, Vector3.new(0.28, 1.1, 1.1), CFrame.Angles(0, math.rad(90), 0), accent, Enum.Material.Neon, Enum.PartType.Cylinder)
		iconPart(w, Vector3.new(0.32, 0.75, 0.75), CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(20, 10, 30), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end,
	quick = function(w: WorldModel, accent: Color3)
		iconPart(w, Vector3.new(0.35, 1.4, 0.3), CFrame.new(0.15, 0.55, 0) * CFrame.Angles(0, 0, math.rad(-25)), accent, Enum.Material.Neon)
		iconPart(w, Vector3.new(0.35, 1.4, 0.3), CFrame.new(-0.15, -0.55, 0) * CFrame.Angles(0, 0, math.rad(-25)), accent, Enum.Material.Neon)
		iconPart(w, Vector3.new(0.9, 0.25, 0.3), CFrame.new(), accent, Enum.Material.Neon)
	end,
	ranked = function(w: WorldModel, accent: Color3)
		iconPart(w, Vector3.new(1.2, 1, 1.2), CFrame.new(0, 0.5, 0), METAL, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		iconPart(w, Vector3.new(0.25, 0.7, 0.25), CFrame.new(0, -0.25, 0), METAL, Enum.Material.SmoothPlastic)
		iconPart(w, Vector3.new(1, 0.25, 0.7), CFrame.new(0, -0.65, 0), METAL, Enum.Material.SmoothPlastic)
		iconPart(w, Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 0.6, -0.62), accent, Enum.Material.Neon, Enum.PartType.Ball)
	end,
	private = function(w: WorldModel, accent: Color3)
		iconPart(w, Vector3.new(1.25, 1, 0.35), CFrame.new(0, -0.35, 0), METAL, Enum.Material.SmoothPlastic)
		iconPart(w, Vector3.new(0.22, 1.1, 1.1), CFrame.new(0, 0.45, 0) * CFrame.Angles(0, math.rad(90), 0), accent, Enum.Material.Neon, Enum.PartType.Cylinder)
		iconPart(w, Vector3.new(0.28, 0.55, 0.55), CFrame.new(0, 0.45, 0) * CFrame.Angles(0, math.rad(90), 0), CARD, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end,
	training = function(w: WorldModel, accent: Color3)
		for radius = 1.4, 0.45, -0.48 do
			iconPart(w, Vector3.new(0.18, radius, radius), CFrame.Angles(0, math.rad(90), 0), if radius > 0.9 then METAL else accent, if radius > 0.9 then Enum.Material.SmoothPlastic else Enum.Material.Neon, Enum.PartType.Cylinder)
		end
	end,
}

local function modeIcon(parent: Instance, kind: string, accent: Color3): Camera
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Icon"
	viewport.Size = UDim2.fromOffset(46, 46)
	viewport.Position = UDim2.fromOffset(12, 8)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(150, 155, 180)
	viewport.LightColor = Color3.fromRGB(240, 245, 255)
	viewport.LightDirection = Vector3.new(-0.4, -1, 0.7)
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	ICONS[kind](world, accent)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.3, -3.6), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = parent
	return camera
end

function HubUI.new(playerGui: PlayerGui, config, lobbyConfig)
	local palette = config.Palette
	local fonts = config.Typography
	local screen = Instance.new("ScreenGui")
	screen.Name = "HubUI"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 90
	screen.Enabled = false
	screen.Parent = playerGui

	local self = setmetatable({
		_screen = screen,
		_config = config,
		_lobbyConfig = lobbyConfig,
		_palette = palette,
		_fonts = fonts,
		_callbacks = {} :: any,
		_tab = "play",
		_tabs = {} :: { [string]: any },
		_pages = {} :: { [string]: CanvasGroup },
		_cards = {} :: { [string]: any },
		_selectedMode = "quick",
		_multiplayerOpen = false,
		_privateSetupOpen = false,
		_billboards = {} :: { BillboardGui },
		_connections = {} :: { RBXScriptConnection },
		_pulse = false,
		_accent = palette.Magenta,
		_actionEnabled = true,
		_toastToken = 0,
		_viewportConnection = nil :: RBXScriptConnection?,
		_renderConnection = nil :: RBXScriptConnection?,
	}, HubUI)

	-- Readability: the left side darkens behind the menu column only, so the
	-- line-up on the right stays clean.
	local shade = frame(screen, "Shade", UDim2.fromScale(0.4, 1), UDim2.new(), Color3.fromRGB(2, 3, 8), 0)
	local shadeFade = Instance.new("UIGradient")
	shadeFade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.75, 0.8), NumberSequenceKeypoint.new(1, 1) })
	shadeFade.Parent = shade
	local top = frame(screen, "TopBar", UDim2.new(1, 0, 0, 124), UDim2.new(), Color3.fromRGB(2, 3, 8), 0)
	local topFade = Instance.new("UIGradient")
	topFade.Rotation = 90
	topFade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	topFade.Parent = top

	-- Logo: the big wordmark with the tagline under it.
	-- Below Roblox's top-left buttons (menu, chat).
	local logo = frame(top, "Logo", UDim2.fromOffset(340, 46), UDim2.fromOffset(28, 52), Color3.new(), 1)
	local logoLayout = Instance.new("UIListLayout")
	logoLayout.FillDirection = Enum.FillDirection.Horizontal
	logoLayout.Padding = UDim.new(0, 10)
	logoLayout.SortOrder = Enum.SortOrder.LayoutOrder
	logoLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	logoLayout.Parent = logo
	local word = label(logo, "Word", "REALITY", UDim2.fromScale(0, 1), UDim2.new(), fonts.Display, 40, palette.Text)
	word.AutomaticSize = Enum.AutomaticSize.X
	word.TextWrapped = false
	word.LayoutOrder = 1
	local year = label(logo, "Year", "2059", UDim2.fromScale(0, 1), UDim2.new(), fonts.Display, 40, palette.Magenta)
	year.AutomaticSize = Enum.AutomaticSize.X
	year.TextWrapped = false
	year.LayoutOrder = 2
	self._year = year
	local tagline = label(top, "Tagline", "LA CIUDAD NUNCA DUERME", UDim2.fromOffset(340, 16), UDim2.fromOffset(30, 100), fonts.Technical, 12, MUTED)
	tagline.TextWrapped = false

	-- Navigation: underline grows under the active tab.
	local tabWidth = #lobbyConfig.Tabs * 118
	local tabs = frame(top, "Tabs", UDim2.fromOffset(tabWidth, 48), UDim2.new(0.5, -tabWidth / 2, 0, 22), Color3.new(), 1)
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabs
	for index, tab in lobbyConfig.Tabs do
		local button = Instance.new("TextButton")
		button.Name = tab.id
		button.LayoutOrder = index
		button.Size = UDim2.fromOffset(118, 48)
		button.BackgroundTransparency = 1
		button.Font = fonts.Display
		button.Text = tab.label
		button.TextSize = 16
		button.TextColor3 = MUTED
		button.Parent = tabs
		local underline = frame(button, "Underline", UDim2.new(0, 0, 0, 3), UDim2.new(0.5, 0, 1, -6), palette.Magenta, 0)
		underline.AnchorPoint = Vector2.new(0.5, 0)
		self._tabs[tab.id] = { button = button, underline = underline }
		button.Activated:Connect(function()
			self:_selectTab(tab.id)
		end)
		button.MouseEnter:Connect(function()
			if self._tab ~= tab.id then
				TweenService:Create(button, QUICK, { TextColor3 = palette.Text }):Play()
			end
		end)
		button.MouseLeave:Connect(function()
			if self._tab ~= tab.id then
				TweenService:Create(button, QUICK, { TextColor3 = MUTED }):Play()
			end
		end)
	end

	-- Player card (top right): name and a level / credits pill.
	local player = frame(top, "Player", UDim2.fromOffset(280, 56), UDim2.new(1, -308, 0, 18), Color3.new(), 1)
	local playerName = label(player, "Name", "", UDim2.new(1, 0, 0, 22), UDim2.new(), fonts.Interface, 17, palette.Text)
	playerName.TextXAlignment = Enum.TextXAlignment.Right
	playerName.TextWrapped = false
	playerName.TextTruncate = Enum.TextTruncate.AtEnd
	local pill = frame(player, "Pill", UDim2.fromOffset(220, 24), UDim2.new(1, -220, 0, 28), CARD, 0.2)
	corner(pill, 12)
	stroke(pill, palette.Cyan, 0.6)
	local playerStats = label(pill, "Stats", "", UDim2.new(1, -20, 1, 0), UDim2.fromOffset(10, 0), fonts.Technical, 12, palette.Text)
	playerStats.TextXAlignment = Enum.TextXAlignment.Center
	playerStats.TextWrapped = false
	self._playerName = playerName
	self._playerStats = playerStats

	-- Pages: the left column, above the main button.
	local content = frame(screen, "Content", UDim2.fromOffset(CONTENT_WIDTH, 376), UDim2.fromOffset(28, CONTENT_TOP), Color3.new(), 1)
	self._content = content
	local function page(id: string): CanvasGroup
		local group = Instance.new("CanvasGroup")
		group.Name = id
		group.Size = UDim2.fromScale(1, 1)
		group.BackgroundTransparency = 1
		group.Visible = false
		group.Parent = content
		self._pages[id] = group
		return group
	end
	local function heading(parent: Instance, title: string, subtitle: string)
		label(parent, "Title", title, UDim2.new(1, 0, 0, 34), UDim2.new(), fonts.Display, 30, palette.Text)
		label(parent, "Subtitle", subtitle, UDim2.new(1, 0, 0, 18), UDim2.fromOffset(0, 34), fonts.Interface, 13, MUTED)
	end

	-- JUGAR opens with one MULTIJUGADOR gateway. The queues live one level
	-- deeper so the main menu stays simple as more modes are added.
	local play = page("play")
	local multiplayerLanding = frame(play, "MultiplayerLanding", UDim2.fromScale(1, 1), UDim2.new(), Color3.new(), 1)
	heading(multiplayerLanding, "JUGAR", "Elige cómo quieres entrar a NEO-EDEN")
	local freeAccent = Color3.fromRGB(170, 90, 255)
	local free = Instance.new("TextButton")
	free.Name = "FreeRoam"
	free.Size = UDim2.new(1, 0, 0, 104)
	free.Position = UDim2.fromOffset(0, 62)
	free.BackgroundColor3 = Color3.new(1, 1, 1)
	free.BackgroundTransparency = 0.55
	free.AutoButtonColor = false
	free.Text = ""
	free.ClipsDescendants = true
	free.Parent = multiplayerLanding
	corner(free, 7)
	local freeWash = Instance.new("UIGradient")
	freeWash.Color = ColorSequence.new(CARD, CARD:Lerp(freeAccent, 0.3))
	freeWash.Parent = free
	stroke(free, MUTED, 0.6, 1.5)
	frame(free, "Accent", UDim2.new(0, 4, 1, 0), UDim2.new(), freeAccent, 0)
	modeIcon(free, "free", freeAccent)
	local freeName = label(free, "Name", "MODO LIBRE", UDim2.new(1, -180, 0, 24), UDim2.fromOffset(68, 12), fonts.Display, 19, palette.Text)
	freeName.TextWrapped = false
	local freeDescription = label(free, "Description", "Explora NEO-EDEN a tu ritmo, solo o con tu escuadrón.", UDim2.new(1, -82, 0, 42), UDim2.fromOffset(68, 40), fonts.Interface, 12, MUTED)
	freeDescription.TextYAlignment = Enum.TextYAlignment.Top
	local freeTag = frame(free, "Tag", UDim2.fromOffset(90, 20), UDim2.new(1, -100, 0, 13), MUTED, 0.8)
	corner(freeTag, 4)
	local freeTagText = label(freeTag, "Text", "BLOQUEADO", UDim2.fromScale(1, 1), UDim2.new(), fonts.Technical, 10, MUTED)
	freeTagText.TextXAlignment = Enum.TextXAlignment.Center
	free.Activated:Connect(function()
		self:Toast("MODO LIBRE ESTÁ BLOQUEADO // PRÓXIMAMENTE", WARN)
	end)

	local multiplayer = Instance.new("TextButton")
	multiplayer.Name = "Multiplayer"
	multiplayer.Size = UDim2.new(1, 0, 0, 146)
	multiplayer.Position = UDim2.fromOffset(0, 176)
	multiplayer.BackgroundColor3 = Color3.new(1, 1, 1)
	multiplayer.BackgroundTransparency = 0.05
	multiplayer.AutoButtonColor = false
	multiplayer.Text = ""
	multiplayer.ClipsDescendants = true
	multiplayer.Parent = multiplayerLanding
	corner(multiplayer, 7)
	local multiplayerWash = Instance.new("UIGradient")
	multiplayerWash.Color = ColorSequence.new(CARD, CARD:Lerp(palette.Cyan, 0.38))
	multiplayerWash.Parent = multiplayer
	stroke(multiplayer, palette.Cyan, 0.15, 2)
	frame(multiplayer, "Accent", UDim2.new(0, 7, 1, 0), UDim2.new(), palette.Cyan, 0)
	modeIcon(multiplayer, "multiplayer", palette.Cyan)
	label(multiplayer, "Name", "MULTIJUGADOR", UDim2.new(1, -88, 0, 30), UDim2.fromOffset(68, 18), fonts.Display, 25, palette.Text)
	local multiplayerDescription = label(multiplayer, "Description", "Compite, juega con amigos o perfecciona tu puntería.", UDim2.new(1, -86, 0, 42), UDim2.fromOffset(68, 54), fonts.Interface, 13, MUTED)
	multiplayerDescription.TextYAlignment = Enum.TextYAlignment.Top
	local multiplayerEnter = label(multiplayer, "Enter", "ENTRAR  ›", UDim2.new(1, -36, 0, 24), UDim2.new(0, 18, 1, -36), fonts.Technical, 14, palette.Cyan)
	multiplayerEnter.TextXAlignment = Enum.TextXAlignment.Right
	local multiplayerScale = Instance.new("UIScale")
	multiplayerScale.Parent = multiplayer
	multiplayer.MouseEnter:Connect(function()
		TweenService:Create(multiplayerScale, QUICK, { Scale = 1.02 }):Play()
	end)
	multiplayer.MouseLeave:Connect(function()
		TweenService:Create(multiplayerScale, QUICK, { Scale = 1 }):Play()
	end)
	multiplayer.Activated:Connect(function()
		self:_setMultiplayerOpen(true)
	end)
	self._multiplayerLanding = multiplayerLanding

	local modesPanel = frame(play, "MultiplayerModes", UDim2.fromScale(1, 1), UDim2.new(), Color3.new(), 1)
	modesPanel.Visible = false
	local back = textButton(modesPanel, "Back", "‹  MULTIJUGADOR", UDim2.new(1, 0, 0, 24), UDim2.new(), fonts.Technical, 12, palette.Cyan)
	back.BackgroundTransparency = 1
	back.TextXAlignment = Enum.TextXAlignment.Left
	back.Activated:Connect(function()
		self:_setMultiplayerOpen(false)
	end)
	self._multiplayerModes = modesPanel

	local list = frame(modesPanel, "Modes", UDim2.new(1, 0, 0, 266), UDim2.fromOffset(0, 28), Color3.new(), 1)
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list
	for index, mode in lobbyConfig.Modes do
		local card = Instance.new("TextButton")
		card.Name = mode.id
		card.LayoutOrder = index
		card.Size = UDim2.new(1, 0, 0, 62)
		-- White base so the gradient shows its own colours: dark on the
		-- left, the mode's accent bleeding in on the right.
		card.BackgroundColor3 = Color3.new(1, 1, 1)
		card.BackgroundTransparency = 0.12
		card.AutoButtonColor = false
		card.Text = ""
		card.ClipsDescendants = true
		card.Parent = list
		corner(card, 6)
		local wash = Instance.new("UIGradient")
		wash.Color = ColorSequence.new(CARD, CARD:Lerp(mode.accent, 0.32))
		wash.Parent = card
		local outline = stroke(card, MUTED, 0.7, 1.5)
		local bar = frame(card, "Accent", UDim2.new(0, 4, 1, 0), UDim2.new(), mode.accent, 0)
		local camera = modeIcon(card, mode.id, mode.accent)
		local name = label(card, "Name", mode.name, UDim2.new(1, -174, 0, 20), UDim2.fromOffset(68, 6), fonts.Display, 16, palette.Text)
		name.TextWrapped = false
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local description = label(card, "Description", mode.description, UDim2.new(1, -80, 0, 30), UDim2.fromOffset(68, 28), fonts.Interface, 11, MUTED)
		description.TextYAlignment = Enum.TextYAlignment.Top
		local tag = frame(card, "Tag", UDim2.fromOffset(90, 18), UDim2.new(1, -98, 0, 7), GOOD, 0.85)
		corner(tag, 4)
		local tagText = label(tag, "Text", "", UDim2.fromScale(1, 1), UDim2.new(), fonts.Technical, 10, GOOD)
		tagText.TextXAlignment = Enum.TextXAlignment.Center
		local scale = Instance.new("UIScale")
		scale.Parent = card
		self._cards[mode.id] = { card = card, outline = outline, bar = bar, camera = camera, tag = tag, tagText = tagText, scale = scale, accent = mode.accent }
		card.MouseEnter:Connect(function()
			TweenService:Create(scale, QUICK, { Scale = 1.02 }):Play()
		end)
		card.MouseLeave:Connect(function()
			TweenService:Create(scale, QUICK, { Scale = 1 }):Play()
		end)
		card.Activated:Connect(function()
			if mode.id == "private" then
				self:_setPrivateSetupOpen(true)
			elseif self._callbacks.mode then
				self._callbacks.mode(mode.id)
			end
		end)
	end
	local detail = frame(modesPanel, "Detail", UDim2.new(1, 0, 0, 76), UDim2.fromOffset(0, 300), CARD, 0.25)
	corner(detail, 6)
	local detailTitle = label(detail, "Title", "", UDim2.new(1, -28, 0, 16), UDim2.fromOffset(14, 6), fonts.Technical, 11, palette.Magenta)
	local detailText = label(detail, "Text", "", UDim2.new(1, -28, 0, 32), UDim2.fromOffset(14, 22), fonts.Interface, 11, palette.Text)
	detailText.TextYAlignment = Enum.TextYAlignment.Top
	local detailRules = label(detail, "Rules", "", UDim2.new(1, -28, 0, 12), UDim2.fromOffset(14, 58), fonts.Technical, 9, palette.Cyan)
	detailRules.TextWrapped = false
	detailRules.TextTruncate = Enum.TextTruncate.AtEnd
	local detailNote = label(detail, "Note", "", UDim2.new(1, -28, 0, 14), UDim2.new(0, 14, 1, -18), fonts.Technical, 11, WARN)
	detailNote.Visible = false
	detailNote.TextWrapped = false
	detailNote.TextTruncate = Enum.TextTruncate.AtEnd
	self._detailRules = detailRules
	self._detailTitle = detailTitle
	self._detailText = detailText
	self._detailNote = detailNote

	-- PARTIDA PRIVADA: create a coded room or enter an existing room code.
	local privateSetup = frame(play, "PrivateSetup", UDim2.fromScale(1, 1), UDim2.new(), Color3.new(), 1)
	privateSetup.Visible = false
	local privateBack = textButton(privateSetup, "Back", "‹  MULTIJUGADOR", UDim2.new(1, 0, 0, 24), UDim2.new(), fonts.Technical, 12, Color3.fromRGB(170, 90, 255))
	privateBack.BackgroundTransparency = 1
	privateBack.TextXAlignment = Enum.TextXAlignment.Left
	privateBack.Activated:Connect(function()
		self:_setPrivateSetupOpen(false)
	end)
	label(privateSetup, "Title", "PARTIDA PRIVADA", UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, 38), fonts.Display, 28, palette.Text)
	label(privateSetup, "Subtitle", "Crea una sala de hasta 10 jugadores o únete con un código.", UDim2.new(1, 0, 0, 36), UDim2.fromOffset(0, 72), fonts.Interface, 13, MUTED)

	local createPrivate = textButton(privateSetup, "Create", "CREAR PARTIDA", UDim2.new(1, 0, 0, 64), UDim2.fromOffset(0, 120), fonts.Display, 21, Color3.fromRGB(170, 90, 255))
	local createHint = label(createPrivate, "Hint", "GENERA UN CÓDIGO PARA COMPARTIR", UDim2.new(1, -24, 0, 16), UDim2.new(0, 12, 1, -20), fonts.Technical, 10, MUTED)
	createHint.TextXAlignment = Enum.TextXAlignment.Center
	createPrivate.Activated:Connect(function()
		if self._callbacks.privateCreate then
			self._callbacks.privateCreate()
		end
	end)

	label(privateSetup, "Or", "—  O COLOCA UN CÓDIGO  —", UDim2.new(1, 0, 0, 18), UDim2.fromOffset(0, 204), fonts.Technical, 11, MUTED).TextXAlignment = Enum.TextXAlignment.Center
	local codeInput = Instance.new("TextBox")
	codeInput.Name = "Code"
	codeInput.Size = UDim2.new(1, 0, 0, 54)
	codeInput.Position = UDim2.fromOffset(0, 232)
	codeInput.BackgroundColor3 = CARD
	codeInput.BackgroundTransparency = 0.08
	codeInput.BorderSizePixel = 0
	codeInput.ClearTextOnFocus = false
	codeInput.Font = fonts.Display
	codeInput.PlaceholderText = "CÓDIGO DE 6 CARACTERES"
	codeInput.PlaceholderColor3 = MUTED
	codeInput.Text = ""
	codeInput.TextColor3 = palette.Text
	codeInput.TextSize = 22
	codeInput.TextXAlignment = Enum.TextXAlignment.Center
	codeInput.Parent = privateSetup
	corner(codeInput, 6)
	stroke(codeInput, Color3.fromRGB(170, 90, 255), 0.35, 1.5)
	self._privateCodeInput = codeInput
	codeInput:GetPropertyChangedSignal("Text"):Connect(function()
		local cleaned = string.upper(codeInput.Text):gsub("[^A-Z0-9]", ""):sub(1, 6)
		if cleaned ~= codeInput.Text then
			codeInput.Text = cleaned
		end
	end)
	local joinPrivate = textButton(privateSetup, "Join", "COLOCAR CÓDIGO", UDim2.new(1, 0, 0, 52), UDim2.fromOffset(0, 300), fonts.Display, 18, palette.Cyan)
	local function submitPrivateCode()
		if self._callbacks.privateJoin then
			self._callbacks.privateJoin(codeInput.Text)
		end
	end
	joinPrivate.Activated:Connect(submitPrivateCode)
	codeInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitPrivateCode()
		end
	end)
	self._privateSetup = privateSetup

	-- PERSONAJE: summary, class stats and the editor.
	local character = page("character")
	heading(character, "PERSONAJE", "Tu identidad en NEO-EDEN")
	local sheet = frame(character, "Sheet", UDim2.new(1, 0, 0, 228), UDim2.fromOffset(0, 60), CARD, 0.15)
	corner(sheet, 6)
	local className = label(sheet, "Class", "", UDim2.new(1, -28, 0, 28), UDim2.fromOffset(14, 10), fonts.Display, 24, palette.Text)
	local facts = label(sheet, "Facts", "", UDim2.new(1, -28, 0, 52), UDim2.fromOffset(14, 40), fonts.Interface, 13, MUTED)
	facts.TextYAlignment = Enum.TextYAlignment.Top
	local bars = {}
	for index, key in STAT_ORDER do
		local y = 98 + (index - 1) * 24
		label(sheet, "Stat" .. key, STAT_NAMES[key], UDim2.fromOffset(110, 18), UDim2.fromOffset(14, y), fonts.Technical, 11, MUTED)
		local track = frame(sheet, "Track" .. key, UDim2.new(1, -144, 0, 8), UDim2.fromOffset(124, y + 5), Color3.fromRGB(30, 36, 52), 0)
		corner(track, 4)
		local fill = frame(track, "Fill", UDim2.fromScale(0, 1), UDim2.new(), palette.Cyan, 0)
		corner(fill, 4)
		bars[key] = fill
	end
	self._className = className
	self._facts = facts
	self._bars = bars
	local edit = textButton(character, "Edit", "EDITAR EN MORPHLAB", UDim2.new(1, 0, 0, 48), UDim2.fromOffset(0, 298), fonts.Display, 19, palette.Magenta)
	edit.Activated:Connect(function()
		if self._callbacks.editCharacter then
			self._callbacks.editCharacter()
		end
	end)

	-- ESCUADRÓN: members, invitations, leave.
	local squad = page("squad")
	heading(squad, "ESCUADRÓN", "Juega con tus amigos: entran y buscan partida juntos")
	self._squadTitle = squad:FindFirstChild("Title") :: TextLabel
	self._squadSubtitle = squad:FindFirstChild("Subtitle") :: TextLabel
	local count = label(squad, "Count", "", UDim2.fromOffset(100, 34), UDim2.new(1, -100, 0, 0), fonts.Display, 26, palette.Cyan)
	count.TextXAlignment = Enum.TextXAlignment.Right
	self._squadCount = count
	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Members"
	rows.Size = UDim2.new(1, 0, 0, 4 * 45)
	rows.Position = UDim2.fromOffset(0, 60)
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.ScrollBarThickness = 4
	rows.ScrollBarImageColor3 = palette.Cyan
	rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rows.CanvasSize = UDim2.new()
	rows.Parent = squad
	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.Padding = UDim.new(0, 5)
	rowsLayout.Parent = rows
	self._memberRows = rows
	label(squad, "InviteTitle", "INVITAR JUGADORES DE ESTE SERVIDOR", UDim2.new(1, 0, 0, 16), UDim2.fromOffset(0, 242), fonts.Technical, 11, MUTED)
	local invites = Instance.new("ScrollingFrame")
	invites.Name = "Invites"
	invites.Size = UDim2.new(1, 0, 0, 72)
	invites.Position = UDim2.fromOffset(0, 262)
	invites.BackgroundTransparency = 1
	invites.BorderSizePixel = 0
	invites.ScrollBarThickness = 4
	invites.AutomaticCanvasSize = Enum.AutomaticSize.Y
	invites.CanvasSize = UDim2.new()
	invites.Parent = squad
	local invitesLayout = Instance.new("UIListLayout")
	invitesLayout.Padding = UDim.new(0, 6)
	invitesLayout.Parent = invites
	self._inviteList = invites
	local leave = textButton(squad, "Leave", "SALIR DEL ESCUADRÓN", UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, 340), fonts.Display, 15, BAD)
	leave.Activated:Connect(function()
		if self._callbacks.leave then
			self._callbacks.leave()
		end
	end)
	self._leave = leave

	-- TIENDA: items by category (bought with NEOCRÉDITOS) and, behind
	-- "+ OBTENER", the NEOCRÉDITOS packs sold for Robux (ShopConfig).
	local currency = ShopConfig.CurrencyName
	local shop = page("shop")
	heading(shop, "TIENDA", "Equipo y estilo para NEO-EDEN")
	local wallet = frame(shop, "Wallet", UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 58), CARD, 0.15)
	corner(wallet, 6)
	stroke(wallet, palette.Cyan, 0.6)
	label(wallet, "Caption", currency, UDim2.fromOffset(120, 14), UDim2.fromOffset(12, 4), fonts.Technical, 10, MUTED)
	local balance = label(wallet, "Balance", "0", UDim2.fromOffset(160, 20), UDim2.fromOffset(12, 17), fonts.Display, 18, palette.Cyan)
	balance.TextWrapped = false
	self._shopBalance = balance
	local getCredits = textButton(wallet, "GetCredits", "+ OBTENER", UDim2.fromOffset(110, 28), UDim2.new(1, -118, 0, 6), fonts.Display, 14, GOOD)

	-- Category chips.
	local chips = Instance.new("ScrollingFrame")
	chips.Name = "Categories"
	chips.Size = UDim2.new(1, 0, 0, 30)
	chips.Position = UDim2.fromOffset(0, 106)
	chips.BackgroundTransparency = 1
	chips.BorderSizePixel = 0
	chips.ScrollBarThickness = 0
	chips.ScrollingDirection = Enum.ScrollingDirection.X
	chips.AutomaticCanvasSize = Enum.AutomaticSize.X
	chips.CanvasSize = UDim2.new()
	chips.Parent = shop
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, 6)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chips
	local chipButtons = {}
	for index, category in ShopConfig.Categories do
		local chip = Instance.new("TextButton")
		chip.Name = category.id
		chip.LayoutOrder = index
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.Size = UDim2.fromOffset(0, 26)
		chip.BackgroundColor3 = CARD
		chip.BackgroundTransparency = 0.15
		chip.Font = fonts.Technical
		chip.Text = category.name
		chip.TextSize = 11
		chip.TextColor3 = MUTED
		chip.Parent = chips
		corner(chip, 13)
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 12)
		padding.PaddingRight = UDim.new(0, 12)
		padding.Parent = chip
		local chipStroke = stroke(chip, palette.Cyan, 0.75)
		chipButtons[category.id] = { button = chip, stroke = chipStroke }
		chip.Activated:Connect(function()
			self:_setShopCategory(category.id)
		end)
	end
	self._shopChips = chipButtons

	-- Item grid, with an empty state while a category has nothing for sale.
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Items"
	grid.Size = UDim2.new(1, 0, 0, 232)
	grid.Position = UDim2.fromOffset(0, 144)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.ScrollBarImageColor3 = palette.Cyan
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = shop
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(106, 116)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	self._shopGrid = grid
	local empty = frame(shop, "Empty", UDim2.new(1, 0, 0, 140), UDim2.fromOffset(0, 150), CARD, 0.35)
	corner(empty, 6)
	local emptyIcon = frame(empty, "Icon", UDim2.fromOffset(30, 30), UDim2.new(0.5, -15, 0, 24), palette.Cyan, 1)
	emptyIcon.Rotation = 45
	stroke(emptyIcon, palette.Cyan, 0.2, 2)
	local emptyText = label(empty, "Text", "", UDim2.new(1, -28, 0, 50), UDim2.fromOffset(14, 70), fonts.Technical, 12, MUTED)
	emptyText.TextXAlignment = Enum.TextXAlignment.Center
	emptyText.TextYAlignment = Enum.TextYAlignment.Top
	self._shopEmpty = empty
	self._shopEmptyText = emptyText

	-- NEOCRÉDITOS packs, over the store when "+ OBTENER" is pressed.
	local packs = frame(shop, "CreditPacks", UDim2.new(1, 0, 0, 318), UDim2.fromOffset(0, 58), Color3.fromRGB(8, 11, 20), 0.04)
	packs.Visible = false
	packs.ZIndex = 5
	corner(packs, 6)
	stroke(packs, GOOD, 0.5)
	local packsTitle = label(packs, "Title", "OBTENER " .. currency, UDim2.new(1, -120, 0, 22), UDim2.fromOffset(12, 10), fonts.Display, 18, palette.Text)
	packsTitle.TextWrapped = false
	local back = textButton(packs, "Back", "< VOLVER", UDim2.fromOffset(96, 26), UDim2.new(1, -104, 0, 8), fonts.Technical, 12, palette.Cyan)
	local packList = frame(packs, "List", UDim2.new(1, -16, 0, #ShopConfig.CreditPacks * 58), UDim2.fromOffset(8, 42), Color3.new(), 1)
	local packLayout = Instance.new("UIListLayout")
	packLayout.Padding = UDim.new(0, 6)
	packLayout.SortOrder = Enum.SortOrder.LayoutOrder
	packLayout.Parent = packList
	for index, pack in ShopConfig.CreditPacks do
		local card = frame(packList, pack.id, UDim2.new(1, 0, 0, 52), UDim2.new(), CARD, 0.1)
		card.LayoutOrder = index
		corner(card, 6)
		stroke(card, palette.Cyan, 0.7)
		frame(card, "Accent", UDim2.new(0, 3, 1, -14), UDim2.fromOffset(0, 7), GOOD, 0)
		label(card, "Name", pack.name, UDim2.fromOffset(150, 14), UDim2.fromOffset(12, 6), fonts.Technical, 10, MUTED)
		local amount = label(card, "Credits", string.format("%d %s", pack.credits, currency), UDim2.fromOffset(190, 22), UDim2.fromOffset(12, 22), fonts.Display, 15, palette.Text)
		amount.TextWrapped = false
		if pack.bonus ~= "" then
			local bonus = label(card, "Bonus", pack.bonus, UDim2.fromOffset(44, 14), UDim2.fromOffset(150, 6), fonts.Technical, 10, GOOD)
			bonus.TextWrapped = false
		end
		local buy = textButton(card, "Buy", string.format("R$ %d", pack.robux), UDim2.fromOffset(92, 34), UDim2.new(1, -100, 0, 9), fonts.Display, 15, if pack.productId > 0 then GOOD else MUTED)
		buy.Activated:Connect(function()
			if self._callbacks.buyCredits then
				self._callbacks.buyCredits(pack.id)
			end
		end)
	end
	local robuxNote = label(packs, "Note", "Se pagan con Robux en la ventana de compra de Roblox.", UDim2.new(1, -24, 0, 16), UDim2.new(0, 12, 1, -24), fonts.Interface, 11, MUTED)
	robuxNote.TextWrapped = false
	self._shopPacks = packs
	getCredits.Activated:Connect(function()
		packs.Visible = true
	end)
	back.Activated:Connect(function()
		packs.Visible = false
	end)
	self._shopCategory = ""
	self:_setShopCategory(ShopConfig.Categories[1].id)

	-- AJUSTES.
	local settings = page("settings")
	heading(settings, "AJUSTES", "Gráficos y controles")
	local qualityRow = frame(settings, "Quality", UDim2.new(1, 0, 0, 60), UDim2.fromOffset(0, 60), CARD, 0.15)
	corner(qualityRow, 6)
	label(qualityRow, "Name", "CALIDAD GRÁFICA", UDim2.fromOffset(180, 20), UDim2.fromOffset(14, 8), fonts.Technical, 12, MUTED)
	local qualityValue = label(qualityRow, "Value", "", UDim2.fromOffset(180, 24), UDim2.fromOffset(14, 28), fonts.Display, 18, palette.Text)
	self._qualityValue = qualityValue
	local change = textButton(qualityRow, "Change", "CAMBIAR", UDim2.fromOffset(110, 38), UDim2.new(1, -122, 0, 11), fonts.Display, 15, palette.Cyan)
	change.Activated:Connect(function()
		if self._callbacks.quality then
			self._callbacks.quality()
		end
	end)
	label(settings, "QualityHint", "Sombras, brillo, niebla y cuánta gente y tráfico hay en la ciudad.", UDim2.new(1, 0, 0, 32), UDim2.fromOffset(0, 126), fonts.Interface, 12, MUTED)
	local controls = frame(settings, "Controls", UDim2.new(1, 0, 0, 208), UDim2.fromOffset(0, 164), CARD, 0.15)
	corner(controls, 6)
	local controlsText = label(controls, "Text",
		"CONTROLES\n\nWASD · Moverse          Shift · Correr\nEspacio · Saltar          Mouse · Cámara\nV · Primera / tercera persona\nQ · Cambiar de hombro\nI · Inventario          F3 · Rendimiento\n\nEn el menú: Q / E cambian de pestaña",
		UDim2.new(1, -28, 1, -20), UDim2.fromOffset(14, 10), fonts.Interface, 13, palette.Text)
	controlsText.TextYAlignment = Enum.TextYAlignment.Top

	-- CRÉDITOS.
	local credits = page("credits")
	heading(credits, "CRÉDITOS", "REALITY 2059")
	local creditsCard = frame(credits, "Card", UDim2.new(1, 0, 0, 220), UDim2.fromOffset(0, 60), CARD, 0.15)
	corner(creditsCard, 6)
	local creditsText = label(creditsCard, "Text",
		"Dirección y desarrollo · Equipo REALITY 2059\n\nAvatares · Roblox R15 y creadores del catálogo\nFachadas · KitBash3D Neo City\n\nHecho con Roblox Studio, Rojo y Luau.",
		UDim2.new(1, -28, 1, -24), UDim2.fromOffset(14, 12), fonts.Interface, 14, palette.Text)
	creditsText.TextYAlignment = Enum.TextYAlignment.Top

	-- Main button (left column, under the pages, as in the reference art):
	-- what it does depends on mode and squad.
	local action = frame(screen, "Action", UDim2.fromOffset(CONTENT_WIDTH, 120), UDim2.new(0, 28, 1, -108), Color3.new(), 1)
	action.AnchorPoint = Vector2.new(0, 1)
	local actionMode = label(action, "Mode", "", UDim2.new(1, 0, 0, 16), UDim2.new(), fonts.Technical, 12, palette.Magenta)
	actionMode.TextWrapped = false
	local actionStatus = label(action, "Status", "", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 16), fonts.Interface, 13, palette.Text)
	actionStatus.TextYAlignment = Enum.TextYAlignment.Top
	local primary = Instance.new("TextButton")
	primary.Name = "Primary"
	primary.AnchorPoint = Vector2.new(0, 1)
	primary.Size = UDim2.new(1, 0, 0, 72)
	primary.Position = UDim2.fromScale(0, 1)
	primary.BackgroundColor3 = Color3.new(1, 1, 1)
	primary.AutoButtonColor = true
	primary.Text = ""
	primary.Parent = action
	corner(primary, 6)
	local primaryGradient = Instance.new("UIGradient")
	primaryGradient.Parent = primary
	local primaryStroke = stroke(primary, Color3.new(1, 1, 1), 0.4, 2)
	local primaryLabel = label(primary, "Label", "", UDim2.new(1, -32, 0, 36), UDim2.fromOffset(16, 8), Enum.Font.GothamBlack, 30, DARK_TEXT)
	primaryLabel.TextXAlignment = Enum.TextXAlignment.Center
	primaryLabel.TextWrapped = false
	local primarySub = label(primary, "Sub", "", UDim2.new(1, -32, 0, 16), UDim2.fromOffset(16, 46), fonts.Technical, 11, DARK_TEXT)
	primarySub.TextXAlignment = Enum.TextXAlignment.Center
	primarySub.TextWrapped = false
	primarySub.TextTruncate = Enum.TextTruncate.AtEnd
	primary.Activated:Connect(function()
		if self._actionEnabled and self._callbacks.primary then
			self._callbacks.primary()
		end
	end)
	self._actionMode = actionMode
	self._actionStatus = actionStatus
	self._action = action
	action.Visible = false
	self._primary = primary
	self._primaryGradient = primaryGradient
	self._primaryStroke = primaryStroke
	self._primaryLabel = primaryLabel
	self._primarySub = primarySub

	-- Location card (bottom left).
	local location = frame(screen, "Location", UDim2.fromOffset(CONTENT_WIDTH, 72), UDim2.new(0, 28, 1, -28), CARD, 0.2)
	location.AnchorPoint = Vector2.new(0, 1)
	corner(location, 6)
	stroke(location, palette.Cyan, 0.7)
	frame(location, "Accent", UDim2.new(0, 3, 1, -16), UDim2.fromOffset(0, 8), palette.Cyan, 0)
	label(location, "Caption", "UBICACIÓN", UDim2.fromOffset(200, 14), UDim2.fromOffset(16, 8), fonts.Technical, 11, MUTED)
	label(location, "Place", "NEO-EDEN", UDim2.fromOffset(240, 26), UDim2.fromOffset(16, 22), fonts.Display, 24, palette.Text)
	label(location, "Detail", "SECTOR 7  ·  AZOTEA  ·  LLUVIA", UDim2.new(1, -32, 0, 14), UDim2.fromOffset(16, 50), fonts.Technical, 11, palette.Cyan)

	-- Squad panel (bottom right): one portrait per slot, always visible.
	local squadPanel = frame(screen, "SquadPanel", UDim2.fromOffset(SQUAD_PANEL_WIDTH, 102), UDim2.new(1, -28, 1, -28), Color3.new(), 1)
	squadPanel.AnchorPoint = Vector2.new(1, 1)
	local stripTitle = label(squadPanel, "Title", "ESCUADRÓN", UDim2.fromOffset(200, 16), UDim2.new(), fonts.Technical, 12, MUTED)
	self._stripTitle = stripTitle
	local stripCount = label(squadPanel, "Count", "", UDim2.fromOffset(120, 16), UDim2.new(1, -120, 0, 0), fonts.Technical, 12, palette.Cyan)
	stripCount.TextXAlignment = Enum.TextXAlignment.Right
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "Slots"
	strip.Size = UDim2.new(1, 0, 0, 80)
	strip.Position = UDim2.fromOffset(0, 22)
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.ScrollBarThickness = 3
	strip.ScrollBarImageColor3 = palette.Cyan
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.CanvasSize = UDim2.new()
	strip.Parent = squadPanel
	local stripLayout = Instance.new("UIListLayout")
	stripLayout.FillDirection = Enum.FillDirection.Horizontal
	stripLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	stripLayout.Padding = UDim.new(0, 8)
	stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stripLayout.Parent = strip
	self._strip = strip
	self._stripCount = stripCount

	local toast = label(screen, "Toast", "", UDim2.fromOffset(560, 30), UDim2.new(0.5, -280, 0, 96), fonts.Technical, 14, palette.Cyan)
	toast.TextXAlignment = Enum.TextXAlignment.Center
	toast.Visible = false
	self._toast = toast

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = screen
	self._scale = uiScale

	-- Q / E (or the shoulder buttons) move between tabs.
	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not screen.Enabled or UserInputService:GetFocusedTextBox() then
			return
		end
		local step = 0
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonR1 then
			step = 1
		elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonL1 then
			step = -1
		end
		if step ~= 0 then
			local order = {}
			for _, tab in lobbyConfig.Tabs do
				table.insert(order, tab.id)
			end
			local index = table.find(order, self._tab) or 1
			self:_selectTab(order[(index - 1 + step) % #order + 1])
		end
	end))

	self:_showTab("play", true)
	return self
end

-- callbacks: tab(id), mode(id), primary(), privateCreate(), privateJoin(code), editCharacter(), invite(userId),
-- kick(userId), leave(), quality(), openSquad().
function HubUI:BindControls(callbacks)
	self._callbacks = callbacks
end

function HubUI:_setMultiplayerOpen(open: boolean)
	self._multiplayerOpen = open
	self._privateSetupOpen = false
	self._multiplayerLanding.Visible = not open
	self._multiplayerModes.Visible = open
	self._privateSetup.Visible = false
	if self._tab == "play" then
		self._action.Visible = open
	end
end

function HubUI:_setPrivateSetupOpen(open: boolean)
	self._privateSetupOpen = open
	self._multiplayerLanding.Visible = false
	self._multiplayerModes.Visible = not open
	self._privateSetup.Visible = open
	if self._tab == "play" then
		self._action.Visible = not open
	end
	if open then
		self._privateCodeInput.Text = ""
	end
end

function HubUI:ClosePrivateSetup()
	self:_setPrivateSetupOpen(false)
end

function HubUI:_selectTab(id: string)
	if id == self._tab then
		return
	end
	self:_showTab(id, false)
	if self._callbacks.tab then
		self._callbacks.tab(id)
	end
end

-- Page transition: the new page slides in and fades up; the old one fades out.
function HubUI:_showTab(id: string, instant: boolean)
	local previous = self._pages[self._tab]
	self._tab = id
	if self._action then
		self._action.Visible = id ~= "play" or (self._multiplayerOpen and not self._privateSetupOpen)
	end
	for tabId, tab in self._tabs do
		local active = tabId == id
		TweenService:Create(tab.button, QUICK, { TextColor3 = if active then self._palette.Text else MUTED }):Play()
		TweenService:Create(tab.underline, SLIDE, { Size = UDim2.new(if active then 0.7 else 0, 0, 0, 3) }):Play()
	end
	local nextPage = self._pages[id]
	if previous and previous ~= nextPage then
		if instant then
			previous.Visible = false
		else
			local fade = TweenService:Create(previous, QUICK, { GroupTransparency = 1 })
			fade.Completed:Once(function()
				if self._pages[self._tab] ~= previous then
					previous.Visible = false
				end
			end)
			fade:Play()
		end
	end
	if nextPage then
		nextPage.Visible = true
		if instant then
			nextPage.GroupTransparency = 0
			nextPage.Position = UDim2.new()
		else
			nextPage.GroupTransparency = 1
			nextPage.Position = UDim2.fromOffset(-36, 0)
			TweenService:Create(nextPage, SLIDE, { GroupTransparency = 0, Position = UDim2.new() }):Play()
		end
	end
end

-- Switches tab from code (e.g. the "+" chips open ESCUADRÓN).
function HubUI:OpenTab(id: string)
	self:_selectTab(id)
end

function HubUI:GetTab(): string
	return self._tab
end

-- state: { selected, locked (only the leader picks), note?, availability = { [id] = { ok, reason } } }
function HubUI:SetModes(state)
	self._selectedMode = state.selected
	local selectedInfo = nil
	for _, mode in self._lobbyConfig.Modes do
		local card = self._cards[mode.id]
		local selected = mode.id == state.selected
		local availability = state.availability[mode.id] or { ok = true }
		if selected then
			selectedInfo = mode
		end
		TweenService:Create(card.bar, SLIDE, { Size = UDim2.new(0, if selected then 8 else 4, 1, 0) }):Play()
		TweenService:Create(card.outline, QUICK, {
			Color = if selected then mode.accent else MUTED,
			Transparency = if selected then 0 else 0.7,
		}):Play()
		card.card.BackgroundTransparency = if mode.locked then 0.55 elseif selected then 0.02 else 0.12
		if mode.locked then
			card.tagText.Text = "BLOQUEADO"
			card.tagText.TextColor3 = MUTED
			card.tag.BackgroundColor3 = MUTED
		else
			card.tagText.Text = if not availability.ok then "SIN SERVIDOR" elseif availability.simulated then "SIMULADO" else "DISPONIBLE"
			card.tagText.TextColor3 = if availability.ok then GOOD else WARN
			card.tag.BackgroundColor3 = if availability.ok then GOOD else WARN
		end
	end
	if selectedInfo then
		self._accent = selectedInfo.accent
		self._detailTitle.Text = selectedInfo.name
		self._detailTitle.TextColor3 = selectedInfo.accent
		self._detailText.Text = selectedInfo.detail
		self._detailRules.Text = (selectedInfo.rules or "") .. (if selectedInfo.rank then "  ·  " .. selectedInfo.rank else "")
		local availability = state.availability[selectedInfo.id] or { ok = true }
		self._detailNote.Text = if state.note then state.note
			elseif not availability.ok then "NO DISPONIBLE: " .. string.upper(tostring(availability.reason))
			elseif availability.simulated then "BÚSQUEDA SIMULADA: SOLO PARA PROBAR EL FLUJO EN STUDIO"
			else ""
		TweenService:Create(self._year, SLIDE, { TextColor3 = selectedInfo.accent }):Play()
		for _, tab in self._tabs do
			TweenService:Create(tab.underline, SLIDE, { BackgroundColor3 = selectedInfo.accent }):Play()
		end
	end
end

-- character: the saved draft (summary sheet).
function HubUI:SetCharacter(character, classColor: Color3?)
	if not character then
		return
	end
	local classId = character.classId or ""
	self._className.Text = CLASS_NAMES[classId] or string.upper(classId)
	self._className.TextColor3 = classColor or self._palette.Text
	local implants = 0
	for _, implantId in character.cyberwareIds or {} do
		if implantId ~= "none" then
			implants += 1
		end
	end
	local body = CharacterCatalog.BodyInfo[character.appearance.bodyBaseId]
	-- The outermost piece worn names the look.
	local style = "ROPA INTERIOR"
	if character.outfit then
		local pieces = CharacterDraft.pieces(character)
		for _, slot in { "jacket", "shirt", "pants" } do
			local info = CharacterCatalog.PieceInfo[slot][pieces[slot] or ""]
			if info then
				style = info.name
				break
			end
		end
	end
	self._facts.Text = string.format("CUERPO  %s\nATUENDO  %s\nIMPLANTES  %d",
		if body then body.name else "—",
		style,
		implants)
	self._characterClass = classId
end

-- stats: { [key] = 0..5 } of the character's class.
function HubUI:SetClassStats(stats: { [string]: number }?, color: Color3?)
	for key, fill in self._bars do
		local value = if stats then (stats[key] or 0) / 5 else 0
		fill.BackgroundColor3 = color or self._palette.Cyan
		TweenService:Create(fill, SLIDE, { Size = UDim2.fromScale(value, 1) }):Play()
	end
end

-- playerData: profile (credits, level).
function HubUI:SetProfile(name: string, playerData)
	self._playerName.Text = string.upper(name)
	local inventory = playerData and playerData.inventory
	local progression = playerData and playerData.progression
	self._level = if progression then progression.level else 1
	self:SetCredits(if inventory then inventory.currency else 0)
end

-- Balance in the player pill and the TIENDA page (after a purchase too).
function HubUI:SetCredits(credits: number)
	self._playerStats.Text = string.format("NIVEL %d  ·  %d %s", self._level or 1, credits, ShopConfig.CurrencyName)
	if self._shopBalance then
		self._shopBalance.Text = tostring(credits)
	end
end

-- TIENDA: shows one category's items (or the empty state).
function HubUI:_setShopCategory(categoryId: string)
	if categoryId == self._shopCategory then
		return
	end
	self._shopCategory = categoryId
	for id, chip in self._shopChips do
		local active = id == categoryId
		chip.button.TextColor3 = if active then self._palette.Text else MUTED
		chip.button.BackgroundColor3 = if active then Color3.fromRGB(20, 40, 60) else CARD
		chip.stroke.Transparency = if active then 0.1 else 0.75
	end
	for _, child in self._shopGrid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local fonts, palette = self._fonts, self._palette
	local count = 0
	for _, item in ShopConfig.Items do
		if item.category == categoryId or (categoryId == "featured" and item.featured) then
			count += 1
			local card = Instance.new("TextButton")
			card.Name = item.id
			card.LayoutOrder = count
			card.BackgroundColor3 = CARD
			card.BackgroundTransparency = 0.1
			card.Text = ""
			card.Parent = self._shopGrid
			corner(card, 6)
			stroke(card, palette.Cyan, 0.7)
			if item.icon then
				local icon = Instance.new("ImageLabel")
				icon.Size = UDim2.fromOffset(64, 64)
				icon.Position = UDim2.new(0.5, -32, 0, 8)
				icon.BackgroundTransparency = 1
				icon.Image = item.icon
				icon.Parent = card
			end
			local name = label(card, "Name", item.name, UDim2.new(1, -12, 0, 16), UDim2.fromOffset(6, 74), fonts.Technical, 10, palette.Text)
			name.TextXAlignment = Enum.TextXAlignment.Center
			local price = label(card, "Price", string.format("%d", item.price), UDim2.new(1, -12, 0, 18), UDim2.fromOffset(6, 92), fonts.Display, 14, palette.Cyan)
			price.TextXAlignment = Enum.TextXAlignment.Center
			card.Activated:Connect(function()
				if self._callbacks.buyItem then
					self._callbacks.buyItem(item.id)
				end
			end)
		end
	end
	self._shopEmpty.Visible = count == 0
	self._shopGrid.Visible = count > 0
	local categoryName = categoryId
	for _, category in ShopConfig.Categories do
		if category.id == categoryId then
			categoryName = category.name
		end
	end
	self._shopEmptyText.Text = string.format("%s\nAÚN NO HAY ARTÍCULOS AQUÍ  ·  VUELVE PRONTO", categoryName)
end

-- view: { count, max, members = { { userId, name, isLeader, ready, isYou, canKick } },
--         inviteable = { { userId, name } }, canLeave }
function HubUI:SetSquad(view)
	local palette, fonts = self._palette, self._fonts
	local isPrivate = view.max > 5
	self._squadTitle.Text = if isPrivate then "SALA PRIVADA" else "ESCUADRÓN"
	self._squadSubtitle.Text = if isPrivate then "Invita hasta 10 jugadores y forma dos equipos" else "Juega con tus amigos: entran y buscan partida juntos"
	self._stripTitle.Text = if isPrivate then "SALA PRIVADA" else "ESCUADRÓN"
	self._squadCount.Text = string.format("%d/%d", view.count, view.max)
	for _, child in self._memberRows:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index = 1, view.max do
		local member = view.members[index]
		local row = frame(self._memberRows, "Row" .. index, UDim2.new(1, 0, 0, 40), UDim2.new(), CARD, if member then 0.1 else 0.6)
		row.LayoutOrder = index
		corner(row, 4)
		if member then
			local name = label(row, "Name", (if member.isLeader then "★  " else "") .. member.name .. (if member.isYou then "  (TÚ)" else ""),
				UDim2.new(1, -170, 1, 0), UDim2.fromOffset(14, 0), fonts.Interface, 14, palette.Text)
			name.TextWrapped = false
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local state = label(row, "State", if member.isLeader then "LÍDER" elseif member.ready then "LISTO" else "NO LISTO",
				UDim2.fromOffset(90, 40), UDim2.new(1, -150, 0, 0), fonts.Technical, 11,
				if member.isLeader then WARN elseif member.ready then GOOD else MUTED)
			state.TextXAlignment = Enum.TextXAlignment.Right
			if member.canKick then
				local kick = textButton(row, "Kick", "SACAR", UDim2.fromOffset(52, 28), UDim2.new(1, -60, 0, 6), fonts.Technical, 11, BAD)
				kick.Activated:Connect(function()
					if self._callbacks.kick then
						self._callbacks.kick(member.userId)
					end
				end)
			end
		else
			label(row, "Empty", "+  Espacio libre", UDim2.new(1, -28, 1, 0), UDim2.fromOffset(14, 0), fonts.Interface, 14, MUTED)
		end
	end
	for _, child in self._inviteList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if #view.inviteable == 0 then
		label(self._inviteList, "Empty", "No hay otros jugadores en este servidor.", UDim2.new(1, -8, 0, 36), UDim2.new(), fonts.Interface, 14, MUTED)
	end
	for _, candidate in view.inviteable do
		local row = frame(self._inviteList, "Candidate", UDim2.new(1, -8, 0, 40), UDim2.new(), CARD, 0.1)
		corner(row, 4)
		label(row, "Name", candidate.name, UDim2.new(1, -140, 1, 0), UDim2.fromOffset(14, 0), fonts.Interface, 15, palette.Text)
		local invite = textButton(row, "Invite", "INVITAR", UDim2.fromOffset(104, 30), UDim2.new(1, -112, 0, 5), fonts.Display, 13, palette.Cyan)
		invite.Activated:Connect(function()
			if self._callbacks.invite then
				self._callbacks.invite(candidate.userId)
			end
		end)
	end
	self._leave.Visible = view.canLeave

	-- Squad panel: one portrait per slot (members first, then free slots
	-- that open ESCUADRÓN to invite).
	for _, child in self._strip:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self._stripCount.Text = string.format("%d/%d", view.count, view.max)
	local slotWidth = if view.max > 5 then 68 else math.floor((SQUAD_PANEL_WIDTH - (view.max - 1) * 8) / view.max)
	for index = 1, view.max do
		local member = view.members[index]
		local slot = Instance.new("TextButton")
		slot.Name = "Slot" .. index
		slot.LayoutOrder = index
		slot.Size = UDim2.fromOffset(slotWidth, 80)
		slot.BackgroundColor3 = CARD
		slot.BackgroundTransparency = if member then 0.1 else 0.55
		slot.AutoButtonColor = true
		slot.Text = ""
		slot.Parent = self._strip
		corner(slot, 6)
		slot.Activated:Connect(function()
			self:_selectTab("squad")
		end)
		if member then
			local ready = member.ready or member.isLeader
			local color = member.color or palette.Magenta
			stroke(slot, if ready then GOOD else MUTED, 0.4)
			-- Portrait: the initial over the class colour.
			local portrait = frame(slot, "Portrait", UDim2.fromOffset(32, 32), UDim2.new(0.5, -16, 0, 6), color, 0.2)
			corner(portrait, 16)
			stroke(portrait, color, 0)
			local initial = label(portrait, "Initial", initialOf(member.name), UDim2.fromScale(1, 1), UDim2.new(), fonts.Display, 18, palette.Text)
			initial.TextXAlignment = Enum.TextXAlignment.Center
			local name = label(slot, "Name", (if member.isLeader then "★ " else "") .. member.name, UDim2.new(1, -10, 0, 16), UDim2.fromOffset(5, 40), fonts.Interface, 12, palette.Text)
			name.TextXAlignment = Enum.TextXAlignment.Center
			name.TextWrapped = false
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local state = label(slot, "State", if member.isLeader then "LÍDER" elseif member.ready then "LISTO" else "NO LISTO",
				UDim2.new(1, -10, 0, 14), UDim2.fromOffset(5, 56), fonts.Technical, 10, if member.isLeader then WARN elseif ready then GOOD else MUTED)
			state.TextXAlignment = Enum.TextXAlignment.Center
			local slotScale = Instance.new("UIScale")
			slotScale.Scale = 0.85
			slotScale.Parent = slot
			TweenService:Create(slotScale, QUICK, { Scale = 1 }):Play()
		else
			stroke(slot, palette.Cyan, 0.75)
			local plus = label(slot, "Plus", "+", UDim2.new(1, 0, 0, 32), UDim2.fromOffset(0, 10), fonts.Display, 28, palette.Cyan)
			plus.TextXAlignment = Enum.TextXAlignment.Center
			local invite = label(slot, "Invite", "INVITAR", UDim2.new(1, 0, 0, 14), UDim2.fromOffset(0, 52), fonts.Technical, 10, MUTED)
			invite.TextXAlignment = Enum.TextXAlignment.Center
		end
	end
end

-- view: { mode, status, statusColor?, label, sublabel, enabled, pulse }
function HubUI:SetAction(view)
	self._actionMode.Text = view.mode
	self._actionMode.TextColor3 = self._accent
	self._actionStatus.Text = view.status
	self._actionStatus.TextColor3 = view.statusColor or self._palette.Text
	self._primaryLabel.Text = view.label
	self._primarySub.Text = view.sublabel or ""
	self._actionEnabled = view.enabled
	self._pulse = view.pulse and view.enabled
	self._primary.AutoButtonColor = view.enabled
	local accent = self._accent
	if view.enabled then
		self._primaryGradient.Color = ColorSequence.new(accent:Lerp(Color3.new(1, 1, 1), 0.35), accent)
		self._primaryLabel.TextColor3 = DARK_TEXT
		self._primarySub.TextColor3 = DARK_TEXT
	else
		self._primaryGradient.Color = ColorSequence.new(Color3.fromRGB(70, 74, 88), Color3.fromRGB(44, 48, 60))
		self._primaryLabel.TextColor3 = Color3.fromRGB(180, 186, 200)
		self._primarySub.TextColor3 = Color3.fromRGB(180, 186, 200)
	end
end

function HubUI:SetQuality(text: string)
	self._qualityValue.Text = text
end

function HubUI:Toast(text: string, color: Color3?)
	self._toastToken += 1
	local token = self._toastToken
	self._toast.Text = text
	self._toast.TextColor3 = color or self._palette.Cyan
	self._toast.Visible = true
	task.delay(3, function()
		if self._toastToken == token then
			self._toast.Visible = false
		end
	end)
end

-- 3D name tags over the squad in the scene, and "+ INVITAR" over free rings.
-- members: { { name, model, color, isPlayer, ready, isLeader } }; freeRings: { BasePart }
function HubUI:SetSquad3D(members, freeRings: { BasePart })
	self:_clearBillboards()
	local palette, fonts = self._palette, self._fonts
	for _, member in members do
		local head = member.model and member.model:FindFirstChild("Head", true)
		if head then
			local gui = Instance.new("BillboardGui")
			gui.Name = "HubTag"
			gui.Adornee = head
			-- Compact: the line-up stands close, tags must not overlap.
			gui.Size = UDim2.fromOffset(124, 40)
			gui.StudsOffset = Vector3.new(0, 1.6, 0)
			gui.AlwaysOnTop = true
			gui.LightInfluence = 0
			gui.ResetOnSpawn = false
			local box = frame(gui, "Tag", UDim2.fromScale(1, 1), UDim2.new(), Color3.fromRGB(8, 12, 22), 0.2)
			corner(box, 4)
			stroke(box, if member.isPlayer then self._accent else member.color, 0.25, 1.4)
			local name = label(box, "Name", (if member.isLeader then "★ " else "") .. member.name, UDim2.new(1, -12, 0, 20), UDim2.fromOffset(6, 2), fonts.Interface, 14, palette.Text)
			name.TextWrapped = false
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.TextXAlignment = Enum.TextXAlignment.Center
			local ready = member.ready ~= false
			local state = label(box, "State", if member.isLeader then "LÍDER" elseif ready then "LISTO" else "NO LISTO", UDim2.new(1, -12, 0, 14), UDim2.fromOffset(6, 22), fonts.Technical, 10, if ready then GOOD else MUTED)
			state.TextXAlignment = Enum.TextXAlignment.Center
			gui.Parent = self._screen.Parent
			table.insert(self._billboards, gui)
		end
	end
	for _, ring in freeRings do
		local gui = Instance.new("BillboardGui")
		gui.Name = "HubInvite"
		gui.Adornee = ring
		gui.Size = UDim2.fromOffset(104, 34)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		gui.Active = true
		local invite = Instance.new("TextButton")
		invite.Size = UDim2.fromScale(1, 1)
		invite.BackgroundColor3 = Color3.fromRGB(8, 12, 22)
		invite.BackgroundTransparency = 0.3
		invite.Font = fonts.Display
		invite.Text = "+ INVITAR"
		invite.TextSize = 14
		invite.TextColor3 = palette.Text
		invite.Parent = gui
		corner(invite, 4)
		stroke(invite, palette.Cyan, 0.4)
		invite.Activated:Connect(function()
			self:_selectTab("squad")
		end)
		gui.Parent = self._screen.Parent
		table.insert(self._billboards, gui)
	end
end

function HubUI:_clearBillboards()
	for _, gui in self._billboards do
		gui:Destroy()
	end
	table.clear(self._billboards)
end

function HubUI:Show()
	self._screen.Enabled = true
	local camera = workspace.CurrentCamera
	if camera then
		local function updateScale()
			local viewport = camera.ViewportSize
			self._scale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.6, 1.4)
		end
		updateScale()
		self._viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	-- Living details: the selected mode's icon turns, the main button breathes.
	self._renderConnection = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local card = self._cards[self._selectedMode]
		if card then
			card.camera.CFrame = CFrame.Angles(0, t * 0.9, 0) * CFrame.lookAt(Vector3.new(0, 0.3, -3.6), Vector3.zero)
		end
		self._primaryStroke.Transparency = if self._pulse then 0.35 + 0.35 * math.sin(t * 3.2) else 0.6
	end)
	-- Entrance: the panels slide in.
	self._content.Position = UDim2.fromOffset(-40, CONTENT_TOP)
	TweenService:Create(self._content, SLIDE, { Position = UDim2.fromOffset(28, CONTENT_TOP) }):Play()
end

function HubUI:Hide()
	if self._viewportConnection then
		self._viewportConnection:Disconnect()
		self._viewportConnection = nil
	end
	if self._renderConnection then
		self._renderConnection:Disconnect()
		self._renderConnection = nil
	end
	self:_clearBillboards()
	self._screen.Enabled = false
end

function HubUI:Destroy()
	self:Hide()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._screen:Destroy()
end

return HubUI
