--!strict

-- Custom inventory window for MODO LIBRE (I / Y, or the INVENTARIO button
-- on touch screens). Shows the server snapshot; equip / unequip are requests
-- the server validates. Replaces the Roblox backpack while enabled.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local InventoryConfig = require(root.Config.InventoryConfig)
local RemoteNames = require(root.Network.RemoteNames)

local InventoryController = {}
InventoryController.__index = InventoryController

local RED = Color3.fromRGB(255, 32, 48)
local PANEL = Color3.fromRGB(6, 9, 15)
local CARD = Color3.fromRGB(14, 20, 30)
local MUTED = Color3.fromRGB(150, 158, 172)
local ERROR = Color3.fromRGB(255, 80, 105)
local SLOT_NAMES = { weapon = "ARMA", body = "CUERPO", gadget = "ACCESORIO" }

local function label(parent: Instance, text: string, font: Enum.Font, size: number, color: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = font
	item.Text = text
	item.TextSize = size
	item.TextColor3 = color
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextWrapped = true
	item.Parent = parent
	return item
end

local function frame(parent: Instance, color: Color3, transparency: number): Frame
	local item = Instance.new("Frame")
	item.BackgroundColor3 = color
	item.BackgroundTransparency = transparency
	item.BorderSizePixel = 0
	item.Parent = parent
	return item
end

local function stroke(parent: Instance, color: Color3, transparency: number): UIStroke
	local item = Instance.new("UIStroke")
	item.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	item.Color = color
	item.Transparency = transparency
	item.Parent = parent
	return item
end

function InventoryController.new(playerGui: PlayerGui, config)
	local self = setmetatable({
		_config = config,
		_enabled = false,
		_open = false,
		_category = "all",
		_selected = nil :: string?,
		_snapshot = nil :: any,
		_busy = false,
		_loadError = nil :: string?,
		_connections = {} :: { RBXScriptConnection },
		_remotes = nil :: Instance?,
	}, InventoryController)
	local fonts = config.Typography

	local screen = Instance.new("ScreenGui")
	screen.Name = "Reality2059Inventory"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 60
	screen.Enabled = false
	screen.Parent = playerGui
	self._screen = screen

	-- Always-visible opener (touch screens have no key).
	local opener = Instance.new("TextButton")
	opener.Name = "Open"
	opener.AnchorPoint = Vector2.new(1, 0)
	opener.Position = UDim2.new(1, -16, 0, 64)
	opener.Size = UDim2.fromOffset(140, 40)
	opener.BackgroundColor3 = CARD
	opener.BorderSizePixel = 0
	opener.Font = fonts.Display
	opener.Text = if UserInputService.TouchEnabled then "INVENTARIO" else "INVENTARIO [I]"
	opener.TextColor3 = config.Palette.Text
	opener.TextSize = 15
	opener.Visible = true
	opener.Parent = screen
	stroke(opener, config.Palette.Cyan, 0.3)
	opener.Activated:Connect(function()
		self:Toggle()
	end)

	local window = frame(screen, PANEL, 0.06)
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromScale(0.92, 0.84)
	window.Visible = false
	window.Active = true
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(860, 520)
	limit.Parent = window
	stroke(window, RED, 0.35)
	local scale = Instance.new("UIScale")
	scale.Parent = window
	self._window = window
	self._scale = scale

	local title = label(window, "INVENTARIO", fonts.Display, 24, config.Palette.Text)
	title.Position = UDim2.fromOffset(20, 12)
	title.Size = UDim2.new(1, -120, 0, 32)
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(84, 32)
	close.BackgroundColor3 = CARD
	close.BorderSizePixel = 0
	close.Font = fonts.Display
	close.Text = "CERRAR"
	close.TextColor3 = config.Palette.Text
	close.TextSize = 14
	close.Parent = window
	stroke(close, RED, 0.4)
	close.Activated:Connect(function()
		self:Close()
	end)

	-- Category tabs.
	local tabs = frame(window, PANEL, 1)
	tabs.Position = UDim2.fromOffset(20, 52)
	tabs.Size = UDim2.new(1, -40, 0, 34)
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabs
	self._tabs = {}
	for index, category in InventoryConfig.Categories do
		local tab = Instance.new("TextButton")
		tab.Name = category.id
		tab.LayoutOrder = index
		tab.Size = UDim2.fromOffset(118, 32)
		tab.BackgroundColor3 = CARD
		tab.BorderSizePixel = 0
		tab.Font = fonts.Display
		tab.Text = category.name
		tab.TextColor3 = MUTED
		tab.TextSize = 13
		tab.Parent = tabs
		local tabStroke = stroke(tab, config.Palette.Cyan, 0.75)
		self._tabs[category.id] = { button = tab, stroke = tabStroke }
		tab.Activated:Connect(function()
			self._category = category.id
			self:_render()
		end)
	end

	-- Item grid (left) and details (right).
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(20, 96)
	grid.Size = UDim2.new(0.6, -30, 1, -116)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.ScrollBarImageColor3 = RED
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = window
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(108, 124)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	self._grid = grid

	local stateText = label(window, "", fonts.Interface, 16, MUTED)
	stateText.Position = UDim2.fromOffset(20, 110)
	stateText.Size = UDim2.new(0.6, -30, 0, 60)
	stateText.TextXAlignment = Enum.TextXAlignment.Center
	self._stateText = stateText

	local details = frame(window, CARD, 0.15)
	details.Name = "Details"
	details.AnchorPoint = Vector2.new(1, 0)
	details.Position = UDim2.new(1, -20, 0, 96)
	details.Size = UDim2.new(0.4, -10, 1, -116)
	stroke(details, config.Palette.Cyan, 0.75)
	local detailGlyph = label(details, "", fonts.Display, 54, config.Palette.Text)
	detailGlyph.Position = UDim2.fromOffset(16, 12)
	detailGlyph.Size = UDim2.fromOffset(72, 72)
	detailGlyph.TextXAlignment = Enum.TextXAlignment.Center
	local detailName = label(details, "", fonts.Display, 18, config.Palette.Text)
	detailName.Position = UDim2.fromOffset(100, 14)
	detailName.Size = UDim2.new(1, -112, 0, 44)
	local detailRarity = label(details, "", fonts.Interface, 14, MUTED)
	detailRarity.Position = UDim2.fromOffset(100, 60)
	detailRarity.Size = UDim2.new(1, -112, 0, 20)
	local detailText = label(details, "", fonts.Interface, 15, config.Palette.Text)
	detailText.Position = UDim2.fromOffset(16, 96)
	detailText.Size = UDim2.new(1, -32, 0, 90)
	detailText.TextYAlignment = Enum.TextYAlignment.Top
	local equippedText = label(details, "", fonts.Interface, 13, MUTED)
	equippedText.AnchorPoint = Vector2.new(0, 1)
	equippedText.Position = UDim2.new(0, 16, 1, -64)
	equippedText.Size = UDim2.new(1, -32, 0, 54)
	equippedText.TextYAlignment = Enum.TextYAlignment.Bottom
	local action = Instance.new("TextButton")
	action.Name = "Action"
	action.AnchorPoint = Vector2.new(0, 1)
	action.Position = UDim2.new(0, 16, 1, -14)
	action.Size = UDim2.new(1, -32, 0, 40)
	action.BackgroundColor3 = RED
	action.BorderSizePixel = 0
	action.Font = fonts.Display
	action.TextColor3 = config.Palette.Text
	action.TextSize = 16
	action.Parent = details
	action.Activated:Connect(function()
		self:_requestAction()
	end)
	self._detail = {
		glyph = detailGlyph,
		name = detailName,
		rarity = detailRarity,
		text = detailText,
		equipped = equippedText,
		action = action,
	}
	return self
end

function InventoryController:_remote(name: string): Instance?
	if not self._remotes then
		local runtime = root:FindFirstChild("Runtime")
		self._remotes = runtime and runtime:FindFirstChild(RemoteNames.Folder)
	end
	return self._remotes and self._remotes:FindFirstChild(name)
end

function InventoryController:_isEquipped(itemId: string): boolean
	local item = InventoryConfig.Items[itemId]
	return item ~= nil and item.slot ~= nil and self._snapshot ~= nil and self._snapshot.equipped[item.slot] == itemId
end

function InventoryController:_card(itemId: string, quantity: number, order: number): TextButton
	local item = InventoryConfig.Items[itemId]
	local rarity = InventoryConfig.Rarities[item.rarity]
	local fonts = self._config.Typography
	local card = Instance.new("TextButton")
	card.Name = itemId
	card.LayoutOrder = order
	card.BackgroundColor3 = CARD
	card.BorderSizePixel = 0
	card.AutoButtonColor = false
	card.Text = ""
	card.Selectable = true
	local selected = self._selected == itemId
	local cardStroke = stroke(card, if selected then RED else rarity.color, if selected then 0 else 0.55)
	cardStroke.Thickness = if selected then 2 else 1
	local band = frame(card, rarity.color, 0)
	band.Size = UDim2.new(1, 0, 0, 3)
	local glyph = label(card, item.glyph, fonts.Display, 40, rarity.color)
	glyph.Position = UDim2.fromOffset(0, 10)
	glyph.Size = UDim2.new(1, 0, 0, 56)
	glyph.TextXAlignment = Enum.TextXAlignment.Center
	if item.icon then
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Image = item.icon
		icon.Size = glyph.Size
		icon.Position = glyph.Position
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = card
		glyph.Visible = false
	end
	local name = label(card, item.name, fonts.Interface, 12, self._config.Palette.Text)
	name.Position = UDim2.fromOffset(6, 70)
	name.Size = UDim2.new(1, -12, 0, 32)
	name.TextXAlignment = Enum.TextXAlignment.Center
	local count = label(card, "x" .. quantity, fonts.Technical, 12, MUTED)
	count.Position = UDim2.new(0, 6, 1, -20)
	count.Size = UDim2.new(1, -12, 0, 16)
	count.TextXAlignment = Enum.TextXAlignment.Right
	if self:_isEquipped(itemId) then
		local badge = label(card, "EQUIPADO", fonts.Technical, 11, Color3.fromRGB(90, 255, 180))
		badge.Position = UDim2.new(0, 6, 1, -20)
		badge.Size = UDim2.new(0.7, 0, 0, 16)
	end
	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(28, 14, 22) }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = CARD }):Play()
	end)
	card.Activated:Connect(function()
		self._selected = itemId
		self:_render()
	end)
	return card
end

function InventoryController:_render()
	for id, tab in self._tabs do
		local active = id == self._category
		tab.button.TextColor3 = if active then self._config.Palette.Text else MUTED
		tab.stroke.Color = if active then RED else self._config.Palette.Cyan
		tab.stroke.Transparency = if active then 0 else 0.75
	end
	for _, child in self._grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local snapshot = self._snapshot
	if not snapshot then
		self._stateText.Text = if self._loadError then "NO SE PUDO CARGAR EL INVENTARIO // " .. self._loadError else "CARGANDO INVENTARIO..."
		self._stateText.TextColor3 = if self._loadError then ERROR else MUTED
		self._stateText.Visible = true
		self:_renderDetails()
		return
	end
	-- Rarest first, then by name.
	local ids = {}
	for itemId, quantity in snapshot.items do
		local item = InventoryConfig.Items[itemId]
		if item and quantity > 0 and (self._category == "all" or item.category == self._category) then
			table.insert(ids, itemId)
		end
	end
	table.sort(ids, function(a, b)
		local itemA, itemB = InventoryConfig.Items[a], InventoryConfig.Items[b]
		local rankA, rankB = InventoryConfig.Rarities[itemA.rarity].order, InventoryConfig.Rarities[itemB.rarity].order
		if rankA ~= rankB then
			return rankA > rankB
		end
		return itemA.name < itemB.name
	end)
	if self._selected and not table.find(ids, self._selected) then
		self._selected = nil
	end
	self._selected = self._selected or ids[1]
	for index, itemId in ids do
		self:_card(itemId, snapshot.items[itemId], index).Parent = self._grid
	end
	self._stateText.Text = if self._category == "all" then "TU INVENTARIO ESTÁ VACÍO" else "SIN OBJETOS EN ESTA CATEGORÍA"
	self._stateText.TextColor3 = MUTED
	self._stateText.Visible = #ids == 0
	self:_renderDetails()
end

function InventoryController:_renderDetails()
	local detail = self._detail
	local itemId = self._selected
	local item = itemId and InventoryConfig.Items[itemId]
	local equippedLines = {}
	for _, slot in InventoryConfig.Slots do
		local equippedId = self._snapshot and self._snapshot.equipped[slot]
		local equippedItem = equippedId and InventoryConfig.Items[equippedId]
		table.insert(equippedLines, SLOT_NAMES[slot] .. ": " .. (if equippedItem then equippedItem.name else "—"))
	end
	detail.equipped.Text = table.concat(equippedLines, "\n")
	if not item or not itemId then
		detail.glyph.Text = ""
		detail.name.Text = "SELECCIONA UN OBJETO"
		detail.rarity.Text = ""
		detail.text.Text = ""
		detail.action.Visible = false
		return
	end
	local rarity = InventoryConfig.Rarities[item.rarity]
	detail.glyph.Text = item.glyph
	detail.glyph.TextColor3 = rarity.color
	detail.name.Text = item.name
	detail.rarity.Text = rarity.name .. "  ·  CANTIDAD " .. tostring(self._snapshot.items[itemId] or 0)
	detail.rarity.TextColor3 = rarity.color
	detail.text.Text = item.description
	detail.action.Visible = item.slot ~= nil
	detail.action.Text = if self._busy then "PROCESANDO..." elseif self:_isEquipped(itemId) then "DESEQUIPAR" else "EQUIPAR"
	detail.action.AutoButtonColor = not self._busy
end

function InventoryController:_requestAction()
	local itemId = self._selected
	local remote = self:_remote(RemoteNames.InventoryAction)
	if self._busy or not itemId or not remote or not remote:IsA("RemoteFunction") then
		return
	end
	local action = if self:_isEquipped(itemId) then "unequip" else "equip"
	self._busy = true
	self:_renderDetails()
	task.spawn(function()
		local ok, result = pcall(function()
			return remote:InvokeServer(action, itemId)
		end)
		self._busy = false
		if not ok or type(result) ~= "table" or not result.ok then
			local reason = if ok and type(result) == "table" then tostring(result.errorCode) else "SIN CONEXIÓN"
			self._detail.action.Text = "ERROR // " .. reason
			task.delay(1.5, function()
				if not self._busy then
					self:_renderDetails()
				end
			end)
			return
		end
		-- The InventoryChanged event brings the new snapshot.
		self:_renderDetails()
	end)
end

function InventoryController:_refresh()
	local remote = self:_remote(RemoteNames.GetInventory)
	if not remote or not remote:IsA("RemoteFunction") then
		self._loadError = "SERVICIO NO DISPONIBLE"
		self:_render()
		return
	end
	self._loadError = nil
	task.spawn(function()
		local ok, result = pcall(function()
			return remote:InvokeServer()
		end)
		if ok and type(result) == "table" then
			self._snapshot = result
		else
			self._loadError = "REINTENTA"
		end
		self:_render()
	end)
end

function InventoryController:Open()
	if not self._enabled or self._open then
		return
	end
	self._open = true
	self._window.Visible = true
	self._scale.Scale = 0.94
	TweenService:Create(self._scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	self:_render()
	self:_refresh()
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = self._tabs.all.button
	end
end

function InventoryController:Close()
	if not self._open then
		return
	end
	self._open = false
	self._window.Visible = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self._window) then
		GuiService.SelectedObject = nil
	end
end

function InventoryController:Toggle()
	if self._open then
		self:Close()
	else
		self:Open()
	end
end

-- MODO LIBRE turns it on and off.
function InventoryController:Enable()
	if self._enabled then
		return
	end
	self._enabled = true
	self._screen.Enabled = true
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
	-- Read the keys straight from UserInputService: the default camera claims
	-- I (zoom) through ContextActionService and kept winning over our action,
	-- which also marks the key as gameProcessed. Only typing in a TextBox
	-- (e.g. chat) is ignored.
	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input)
		if table.find(InventoryConfig.ToggleKeys, input.KeyCode) and not UserInputService:GetFocusedTextBox() then
			self:Toggle()
		end
	end))
	local changed = self:_remote(RemoteNames.InventoryChanged)
	if changed and changed:IsA("RemoteEvent") then
		table.insert(self._connections, changed.OnClientEvent:Connect(function(snapshot)
			self._snapshot = snapshot
			if self._open then
				self:_render()
			end
		end))
	end
	self:_refresh()
end

function InventoryController:Disable()
	if not self._enabled then
		return
	end
	self:Close()
	self._enabled = false
	self._screen.Enabled = false
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._connections = {}
end

function InventoryController:Destroy()
	self:Disable()
	self._screen:Destroy()
end

return InventoryController
