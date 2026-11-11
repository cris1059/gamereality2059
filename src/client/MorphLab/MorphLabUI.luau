--!strict

-- MORPHLAB screen, laid out like the reference art: the title top left, the
-- identity columns at the screen edges (CUERPO, ROSTRO, CABELLO, ATUENDO,
-- PALETA / CLASE, IMPLANTES, ACCESORIOS, DATOS) with the avatar between them
-- and the action row at the bottom. Every option row ends in a MÁS card that
-- slides a drawer up over its column with all the options. Authored on a
-- 1280x720 canvas scaled to the screen.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local CharacterCatalog = require(root.Catalog.CharacterCatalog)
local FaceArt = require(root.Character.FaceArt)
local CharacterDraft = require(root.Character.CharacterDraft)

local MorphLabUI = {}
MorphLabUI.__index = MorphLabUI

local DESIGN = Vector2.new(1280, 720)
local MARGIN = 40
local TITLE_X = 170
local CLASS_STATS_X = -MARGIN - 300 - 14
local COLUMN_TOP = 118
local COLUMN_BOTTOM = 604
local LEFT_WIDTH = 280
local RIGHT_WIDTH = 300
local ROW_CARD = 56
local ROW_SLOTS = 3
local DRAWER_TIME = 0.28

local TEXT = Color3.fromRGB(236, 232, 255)
local MUTED = Color3.fromRGB(150, 140, 190)
local DIM = Color3.fromRGB(70, 62, 104)
local CARD = Color3.fromRGB(20, 16, 40)
local CARD_SELECTED = Color3.fromRGB(46, 26, 88)
local DONE = Color3.fromRGB(60, 255, 140)
local ERROR = Color3.fromRGB(255, 80, 105)

local IMPLANT_NAMES = table.freeze({
	cyber_eye = "OJO BIÓNICO",
	visor = "VISOR ÓPTICO",
	jaw_plate = "PLACA MANDIBULAR",
	face_circuits = "CIRCUITOS FACIALES",
	neck_ports = "PUERTOS NUCALES",
	cyber_arm = "BRAZO CIBERNÉTICO",
})
local SLOT_NAMES = table.freeze({
	jacket = "CHAQUETA",
	shirt = "CAMISA",
	pants = "PANTALÓN",
	shoes = "TENIS",
})
local CLASS_ROLES = table.freeze({
	runner = "Movilidad extrema: carreras, saltos y escapes.",
	netrunner = "Hackea redes, drones y defensas enemigas.",
	enforcer = "Blindaje pesado para el combate cercano.",
	ghost = "Sigilo y emboscadas sin ser detectado.",
	medtech = "Cura y potencia a su escuadrón.",
})
local STAT_NAMES = table.freeze({
	speed = "VELOCIDAD",
	armor = "BLINDAJE",
	hacking = "HACKEO",
	stealth = "SIGILO",
	support = "SOPORTE",
})
local CLASS_NAMES = table.freeze({
	runner = "CORREDOR",
	netrunner = "NETRUNNER",
	enforcer = "EJECUTOR",
	ghost = "FANTASMA",
	medtech = "MEDTECH",
})
local NEON_NAMES = table.freeze({
	red = "ROJO", cyan = "CIAN", magenta = "MAGENTA", green = "VERDE",
	yellow = "AMARILLO", orange = "NARANJA", violet = "VIOLETA", white = "BLANCO",
})
local METAL_NAMES = table.freeze({
	gunmetal = "GRAFITO", chrome = "CROMO", black = "NEGRO", gold = "ORO", white = "BLANCO",
})
-- Which panels show the check mark of each progress section.
local CATEGORY_PANELS = table.freeze({
	BODY = { "body" },
	FACE = { "face" },
	HAIR = { "hair" },
	OUTFIT = { "outfit", "accessories" },
	IMPLANTS = { "implants" },
	CLASS = { "class" },
	COLOR = { "palette" },
})

-- ------------------------------------------------------------ helpers --

local function corner(parent: Instance, radius: number?, scale: number?)
	local item = Instance.new("UICorner")
	item.CornerRadius = if scale then UDim.new(scale, 0) else UDim.new(0, radius or 4)
	item.Parent = parent
	return item
end

local function stroke(parent: Instance, color: Color3, transparency: number?, thickness: number?): UIStroke
	local item = Instance.new("UIStroke")
	item.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	item.Color = color
	item.Transparency = transparency or 0
	item.Thickness = thickness or 1
	item.Parent = parent
	return item
end

local function gradient(parent: Instance, from: Color3, to: Color3, rotation: number?): UIGradient
	local item = Instance.new("UIGradient")
	item.Color = ColorSequence.new(from, to)
	item.Rotation = rotation or 0
	item.Parent = parent
	return item
end

local function box(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, transparency: number?, anchor: Vector2?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function label(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, font: Enum.Font, textSize: number, color: Color3, alignX: Enum.TextXAlignment?): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundTransparency = 1
	item.Font = font
	item.Text = text
	item.TextColor3 = color
	item.TextSize = textSize
	item.TextXAlignment = alignX or Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Parent = parent
	return item
end

local function spaced(text: string): string
	return (string.gsub(text, "(.)", "%1 "))
end

local function button(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2?): TextButton
	local item = Instance.new("TextButton")
	item.Name = name
	item.AnchorPoint = anchor or Vector2.new(0, 0)
	item.Size = size
	item.Position = position
	item.BackgroundColor3 = CARD
	item.BackgroundTransparency = 0.1
	item.BorderSizePixel = 0
	item.AutoButtonColor = true
	item.Text = ""
	item.Parent = parent
	return item
end

local function ring(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, thickness: number?): Frame
	local item = box(parent, name, size, position, color, 1)
	corner(item, nil, 0.5)
	stroke(item, color, 0, thickness or 1.5)
	return item
end

local function thumbnail(parent: Instance, assetId: number)
	local image = Instance.new("ImageLabel")
	image.Name = "Thumbnail"
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.new(1, -4, 1, -4)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = if assetId > 0 then string.format("rbxthumb://type=Asset&id=%d&w=150&h=150", assetId) else ""
	image.Parent = parent
	return image
end

-- -------------------------------------------------------------- icons --

local function implantArt(parent: Instance, implantId: string, color: Color3)
	if implantId == "cyber_eye" then
		ring(parent, "Lens", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.5), color, 2)
		corner(box(parent, "Pupil", UDim2.fromScale(0.18, 0.18), UDim2.fromScale(0.5, 0.5), color), nil, 0.5)
		box(parent, "Scan", UDim2.fromScale(0.8, 0.04), UDim2.fromScale(0.5, 0.5), color, 0.4)
	elseif implantId == "visor" then
		corner(box(parent, "Visor", UDim2.fromScale(0.72, 0.22), UDim2.fromScale(0.5, 0.5), color, 0.25), nil, 0.5)
		box(parent, "Glint", UDim2.fromScale(0.5, 0.04), UDim2.fromScale(0.46, 0.46), TEXT, 0.3)
	elseif implantId == "jaw_plate" then
		box(parent, "Chin", UDim2.fromScale(0.42, 0.1), UDim2.fromScale(0.5, 0.7), color)
		for _, side in { -1, 1 } do
			box(parent, "Side", UDim2.fromScale(0.09, 0.4), UDim2.fromScale(0.5 + side * 0.25, 0.5), color).Rotation = -side * 25
		end
	elseif implantId == "face_circuits" then
		box(parent, "TraceV", UDim2.fromScale(0.06, 0.5), UDim2.fromScale(0.38, 0.5), color)
		box(parent, "TraceH", UDim2.fromScale(0.3, 0.06), UDim2.fromScale(0.53, 0.32), color)
		box(parent, "TraceH2", UDim2.fromScale(0.22, 0.06), UDim2.fromScale(0.49, 0.72), color)
		for _, point in { Vector2.new(0.68, 0.32), Vector2.new(0.6, 0.72), Vector2.new(0.38, 0.24) } do
			corner(box(parent, "Node", UDim2.fromScale(0.12, 0.12), UDim2.fromScale(point.X, point.Y), color), nil, 0.5)
		end
	elseif implantId == "neck_ports" then
		for _, x in { 0.3, 0.5, 0.7 } do
			ring(parent, "Port", UDim2.fromScale(0.15, 0.15), UDim2.fromScale(x, 0.5), color, 2)
		end
		box(parent, "Bus", UDim2.fromScale(0.6, 0.04), UDim2.fromScale(0.5, 0.68), color, 0.4)
	elseif implantId == "cyber_arm" then
		corner(box(parent, "Arm", UDim2.fromScale(0.24, 0.56), UDim2.fromScale(0.5, 0.44), color, 0.25), nil, 0.3)
		for _, y in { 0.3, 0.45, 0.6 } do
			box(parent, "Segment", UDim2.fromScale(0.26, 0.03), UDim2.fromScale(0.5, y), TEXT, 0.4)
		end
		corner(box(parent, "Hand", UDim2.fromScale(0.2, 0.14), UDim2.fromScale(0.5, 0.8), color), nil, 0.3)
	end
end

local function classArt(parent: Instance, classId: string, color: Color3)
	if classId == "runner" then
		for _, x in { 0.38, 0.6 } do
			for _, entry in { { 0.39, 45 }, { 0.61, -45 } } do
				box(parent, "Chevron", UDim2.fromScale(0.32, 0.09), UDim2.fromScale(x, entry[1]), color).Rotation = entry[2]
			end
		end
	elseif classId == "netrunner" then
		local diamond = box(parent, "Diamond", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.5), color, 1)
		diamond.Rotation = 45
		stroke(diamond, color, 0, 2)
		box(parent, "Core", UDim2.fromScale(0.16, 0.16), UDim2.fromScale(0.5, 0.5), color).Rotation = 45
	elseif classId == "enforcer" then
		corner(box(parent, "ShieldTop", UDim2.fromScale(0.5, 0.36), UDim2.fromScale(0.5, 0.4), color, 0.1), 3)
		box(parent, "ShieldTip", UDim2.fromScale(0.36, 0.36), UDim2.fromScale(0.5, 0.56), color, 0.1).Rotation = 45
	elseif classId == "ghost" then
		ring(parent, "Hood", UDim2.fromScale(0.56, 0.56), UDim2.fromScale(0.5, 0.5), color, 2)
		box(parent, "Slit", UDim2.fromScale(0.32, 0.08), UDim2.fromScale(0.5, 0.5), color)
	else
		box(parent, "CrossH", UDim2.fromScale(0.5, 0.15), UDim2.fromScale(0.5, 0.5), color)
		box(parent, "CrossV", UDim2.fromScale(0.15, 0.5), UDim2.fromScale(0.5, 0.5), color)
	end
end

local function bodyArt(parent: Instance, slim: boolean, color: Color3)
	corner(box(parent, "HeadIcon", UDim2.fromScale(0.34, 0.24), UDim2.fromScale(0.5, 0.16), color), nil, 0.5)
	box(parent, "Torso", UDim2.fromScale(if slim then 0.5 else 0.7, 0.36), UDim2.fromScale(0.5, 0.48), color)
	for _, side in { -1, 1 } do
		box(parent, "Leg", UDim2.fromScale(0.2, 0.32), UDim2.fromScale(0.5 + side * 0.13, 0.83), color)
	end
end

-- ------------------------------------------------------------- panels --

local function panel(parent: Instance, name: string, title: string, size: UDim2, position: UDim2, palette)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = palette.Glass
	frame.BackgroundTransparency = 0.18
	frame.BorderSizePixel = 0
	frame.Parent = parent
	corner(frame, 6)
	stroke(frame, palette.Purple, 0.5, 1.2)
	gradient(frame, Color3.fromRGB(34, 24, 66), Color3.fromRGB(10, 8, 22), 115)
	box(frame, "Accent", UDim2.fromOffset(18, 2), UDim2.fromOffset(10, 0), palette.Purple, 0.1, Vector2.new(0, 0))
	-- Section mark: a diamond that fills green once the section is done.
	local mark = box(frame, "Mark", UDim2.fromOffset(8, 8), UDim2.fromOffset(16, 17), palette.Purple, 1)
	mark.Rotation = 45
	local markStroke = stroke(mark, palette.Purple, 0, 1.5)
	local heading = label(frame, "Title", title, UDim2.new(0.6, -30, 0, 22), UDim2.fromOffset(28, 6), Enum.Font.SciFi, 15, TEXT)
	local detail = label(frame, "Detail", "", UDim2.new(0.5, -12, 0, 22), UDim2.new(0.5, 0, 0, 6), Enum.Font.Code, 10, MUTED, Enum.TextXAlignment.Right)
	detail.TextTruncate = Enum.TextTruncate.AtEnd
	return { frame = frame, mark = mark, markStroke = markStroke, title = heading, detail = detail }
end

local function setPanelDone(entry, done: boolean, palette)
	entry.mark.BackgroundTransparency = if done then 0 else 1
	entry.mark.BackgroundColor3 = if done then DONE else palette.Purple
	entry.markStroke.Color = if done then DONE else palette.Purple
end

local function styleCard(card: GuiObject, selected: boolean, accent: Color3)
	local outline = card:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Color = if selected then accent else DIM
		outline.Transparency = if selected then 0 else 0.2
		outline.Thickness = if selected then 2 else 1
	end
	card.BackgroundColor3 = if selected then CARD_SELECTED else CARD
	card:SetAttribute("Selected", selected)
end

-- ----------------------------------------------------------- carousel --

-- A row of option cards ending in MÁS, plus a drawer (all options with their
-- names) that slides up over the column when MÁS is pressed.
local Carousel = {}
Carousel.__index = Carousel

function Carousel.new(options)
	local palette = options.palette
	local holder = Instance.new("Frame")
	holder.Name = options.name .. "Row"
	holder.Position = UDim2.fromOffset(8, options.rowY or 32)
	holder.Size = UDim2.new(1, -16, 0, ROW_CARD)
	holder.BackgroundTransparency = 1
	holder.Parent = options.panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder

	local more = Instance.new("TextButton")
	more.Name = "More"
	more.LayoutOrder = 10000
	more.Size = UDim2.fromOffset(ROW_CARD, ROW_CARD)
	more.BackgroundColor3 = Color3.fromRGB(30, 18, 60)
	more.BorderSizePixel = 0
	more.Text = ""
	corner(more, 5)
	local moreStroke = stroke(more, palette.Purple, 0.1, 1.5)
	moreStroke.LineJoinMode = Enum.LineJoinMode.Round
	label(more, "Plus", "+", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 6), Enum.Font.SciFi, 28, palette.Purple, Enum.TextXAlignment.Center)
	local moreLabel = label(more, "Label", "MÁS", UDim2.new(1, 0, 0, 14), UDim2.fromOffset(0, 36), Enum.Font.Code, 10, TEXT, Enum.TextXAlignment.Center)
	more.Parent = holder

	-- Drawer over the whole column, anchored at its bottom edge.
	local columnHeight = COLUMN_BOTTOM - COLUMN_TOP
	local drawer = Instance.new("Frame")
	drawer.Name = options.name .. "Drawer"
	drawer.AnchorPoint = Vector2.new(0, 1)
	drawer.Position = UDim2.new(options.columnX.Scale, options.columnX.Offset, 0, COLUMN_BOTTOM)
	drawer.Size = UDim2.fromOffset(options.columnWidth, 0)
	drawer.BackgroundTransparency = 1
	drawer.ClipsDescendants = true
	drawer.Visible = false
	drawer.ZIndex = 10
	drawer.Parent = options.canvas
	local sheet = Instance.new("Frame")
	sheet.Name = "Sheet"
	sheet.Size = UDim2.fromOffset(options.columnWidth, columnHeight)
	sheet.BackgroundColor3 = Color3.fromRGB(12, 9, 26)
	sheet.BackgroundTransparency = 0.04
	sheet.BorderSizePixel = 0
	sheet.Parent = drawer
	corner(sheet, 6)
	stroke(sheet, palette.Purple, 0.2, 1.5)
	gradient(sheet, Color3.fromRGB(40, 26, 80), Color3.fromRGB(10, 8, 22), 100)
	box(sheet, "Accent", UDim2.fromOffset(26, 2), UDim2.fromOffset(10, 0), palette.Purple, 0, Vector2.new(0, 0))
	label(sheet, "Title", options.title, UDim2.new(1, -110, 0, 24), UDim2.fromOffset(14, 8), Enum.Font.SciFi, 16, TEXT)
	label(sheet, "Subtitle", "MÁS OPCIONES", UDim2.new(1, -110, 0, 12), UDim2.fromOffset(14, 30), Enum.Font.Code, 9, palette.Purple)
	local close = button(sheet, "Close", UDim2.fromOffset(80, 26), UDim2.new(1, -10, 0, 10), Vector2.new(1, 0))
	corner(close, 5)
	stroke(close, palette.Purple, 0.3, 1)
	close.Font = Enum.Font.Code
	close.Text = "CERRAR  ×"
	close.TextSize = 10
	close.TextColor3 = TEXT
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Options"
	scroller.Position = UDim2.fromOffset(8, 50)
	scroller.Size = UDim2.new(1, -16, 1, -58)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 4
	scroller.ScrollBarImageColor3 = palette.Purple
	scroller.ScrollingDirection = Enum.ScrollingDirection.Y
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.Parent = sheet
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(58, 76)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroller
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = scroller

	return setmetatable({
		options = options,
		holder = holder,
		more = more,
		moreLabel = moreLabel,
		drawer = drawer,
		closeButton = close,
		scroller = scroller,
		height = columnHeight,
		order = {} :: { string },
		rowCards = {} :: { [string]: TextButton },
		gridCards = {} :: { [string]: TextButton },
		selected = {} :: { [string]: boolean },
		filter = nil :: ((string) -> boolean)?,
		isOpen = false,
		tween = nil :: Tween?,
	}, Carousel)
end

-- Adds an option: a row card and a captioned drawer card, both drawn by build.
function Carousel:add(id: string, caption: string)
	local build = self.options.build
	local index = #self.order + 1
	table.insert(self.order, id)
	local row = Instance.new("TextButton")
	row.Name = id
	row.LayoutOrder = index
	row.Size = UDim2.fromOffset(ROW_CARD, ROW_CARD)
	row.BackgroundColor3 = CARD
	row.BorderSizePixel = 0
	row.Text = ""
	row.ClipsDescendants = true
	corner(row, 5)
	stroke(row, DIM, 0.2, 1)
	local rowArt = Instance.new("Frame")
	rowArt.Name = "Art"
	rowArt.Size = UDim2.fromScale(1, 1)
	rowArt.BackgroundTransparency = 1
	rowArt.Parent = row
	build(rowArt, id, ROW_CARD)
	row.Parent = self.holder
	self.rowCards[id] = row

	local cell = Instance.new("TextButton")
	cell.Name = id
	cell.LayoutOrder = index
	cell.BackgroundColor3 = CARD
	cell.BorderSizePixel = 0
	cell.Text = ""
	cell.ClipsDescendants = true
	corner(cell, 5)
	stroke(cell, DIM, 0.2, 1)
	local cellArt = Instance.new("Frame")
	cellArt.Name = "Art"
	cellArt.Size = UDim2.fromOffset(58, 58)
	cellArt.BackgroundTransparency = 1
	cellArt.Parent = cell
	build(cellArt, id, 58)
	local name = label(cell, "Caption", caption, UDim2.new(1, -4, 0, 14), UDim2.fromOffset(2, 60), Enum.Font.Code, 8, TEXT, Enum.TextXAlignment.Center)
	name.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 8
	limit.Parent = name
	cell.Parent = self.scroller
	self.gridCards[id] = cell
end

function Carousel:_visibleIds(): { string }
	local ids = {}
	for _, id in self.order do
		if not self.filter or self.filter(id) then
			table.insert(ids, id)
		end
	end
	return ids
end

-- Row: the first options, with the selection always on show (several
-- selections first, for implants and accessories).
function Carousel:refresh()
	local ids = self:_visibleIds()
	local slots = {}
	if self.options.multi then
		for _, id in ids do
			if self.selected[id] and #slots < ROW_SLOTS then
				table.insert(slots, id)
			end
		end
		for _, id in ids do
			if not self.selected[id] and #slots < ROW_SLOTS then
				table.insert(slots, id)
			end
		end
	else
		for index = 1, math.min(ROW_SLOTS, #ids) do
			slots[index] = ids[index]
		end
		for _, id in ids do
			if self.selected[id] and not table.find(slots, id) and #slots > 0 then
				slots[#slots] = id
			end
		end
	end
	for id, card in self.rowCards do
		local slot = table.find(slots, id)
		card.Visible = slot ~= nil
		card.LayoutOrder = slot or 0
	end
	local visible = {}
	for _, id in ids do
		visible[id] = true
	end
	for id, card in self.gridCards do
		card.Visible = visible[id] == true
	end
	local accent = self.options.palette.Purple
	for id, card in self.rowCards do
		styleCard(card, self.selected[id] == true, accent)
	end
	for id, card in self.gridCards do
		styleCard(card, self.selected[id] == true, accent)
	end
end

function Carousel:setSelected(ids: { string })
	table.clear(self.selected)
	for _, id in ids do
		self.selected[id] = true
	end
	self:refresh()
end

function Carousel:count(): number
	return #self:_visibleIds()
end

function Carousel:open()
	if self.isOpen then
		return
	end
	self.isOpen = true
	self.moreLabel.Text = "MENOS"
	if self.tween then
		self.tween:Cancel()
	end
	self.drawer.Visible = true
	self.tween = TweenService:Create(self.drawer, TweenInfo.new(DRAWER_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(self.options.columnWidth, self.height),
	})
	self.tween:Play()
end

function Carousel:close()
	if not self.isOpen then
		return
	end
	self.isOpen = false
	self.moreLabel.Text = "MÁS"
	if self.tween then
		self.tween:Cancel()
	end
	local tween = TweenService:Create(self.drawer, TweenInfo.new(DRAWER_TIME * 0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
		Size = UDim2.fromOffset(self.options.columnWidth, 0),
	})
	self.tween = tween
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and not self.isOpen then
			self.drawer.Visible = false
		end
	end)
	tween:Play()
end

-- -------------------------------------------------------------- build --

function MorphLabUI.new(playerGui: PlayerGui, config)
	local palette = config.Palette
	local screen = Instance.new("ScreenGui")
	screen.Name = "MorphLabUI"
	screen.IgnoreGuiInset = false
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 90
	screen.Enabled = false
	screen:SetAttribute("Phase", "C.4")
	screen.Parent = playerGui

	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.BackgroundTransparency = 1
	canvas.Parent = screen
	local scale = Instance.new("UIScale")
	scale.Name = "ResponsiveScale"
	scale.Parent = canvas

	-- Soft darkening at the screen edges so the panels read over the city.
	for _, entry in { { 0, 0 }, { 1, 180 } } do
		local shade = box(canvas, "EdgeShade", UDim2.new(0.3, 0, 1, 0), UDim2.fromScale(entry[1], 0), Color3.fromRGB(6, 4, 14), 0, Vector2.new(entry[1], 0))
		local fade = Instance.new("UIGradient")
		fade.Rotation = entry[2]
		fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
		fade.Parent = shade
	end

	-- Title block, right of Roblox's own top-left buttons (menu, chat).
	label(canvas, "Brand", spaced("REALITY 2059"), UDim2.fromOffset(240, 18), UDim2.fromOffset(TITLE_X, 10), Enum.Font.Jura, 15, TEXT)
	label(canvas, "Motto", "LOS MUNDOS SE ROMPEN. TÚ EVOLUCIONAS.", UDim2.fromOffset(260, 12), UDim2.fromOffset(TITLE_X + 1, 29), Enum.Font.Code, 9, MUTED)
	local title = label(canvas, "Title", 'MORPH<font color="#A85CFF">LAB</font>', UDim2.fromOffset(300, 52), UDim2.fromOffset(TITLE_X - 2, 40), Enum.Font.SciFi, 50, TEXT)
	title.RichText = true
	local titleGlow = Instance.new("UIStroke")
	titleGlow.Color = palette.Purple
	titleGlow.Transparency = 0.7
	titleGlow.Parent = title
	label(canvas, "Tagline", spaced("LA IDENTIDAD ES UNA DIMENSIÓN"), UDim2.fromOffset(300, 14), UDim2.fromOffset(TITLE_X + 1, 93), Enum.Font.Jura, 10, palette.Purple)
	box(canvas, "TaglineRule", UDim2.fromOffset(150, 1), UDim2.fromOffset(TITLE_X + 1, 110), palette.Purple, 0.4, Vector2.new(0, 0))

	-- Graffiti and footer, as in the reference art.
	local graffiti = label(canvas, "Graffiti", "CREA\nADAPTA\nTRASCIENDE.", UDim2.fromOffset(160, 84), UDim2.new(0, 34, 1, -96), Enum.Font.PermanentMarker, 18, palette.Purple)
	graffiti.Rotation = -8
	graffiti.TextTransparency = 0.25
	graffiti.TextYAlignment = Enum.TextYAlignment.Top
	graffiti.LineHeight = 0.9
	local footer = label(canvas, "Footer", "UN TÚ SUPERIOR\nEN CADA REALIDAD.", UDim2.fromOffset(220, 28), UDim2.new(1, -MARGIN, 1, -22), Enum.Font.Code, 10, MUTED, Enum.TextXAlignment.Right)
	footer.AnchorPoint = Vector2.new(1, 1)

	local leftX = UDim.new(0, MARGIN)
	local rightX = UDim.new(1, -MARGIN - RIGHT_WIDTH)
	local function at(column: UDim, y: number): UDim2
		return UDim2.new(column.Scale, column.Offset, 0, y)
	end
	local panels = {}
	local carousels = {}
	local faceArts = {}
	local function carousel(key: string, title_: string, column: UDim, width: number, y: number, multi: boolean, build: (Frame, string, number) -> ())
		local entry = panel(canvas, key .. "Panel", title_, UDim2.fromOffset(width, 94), at(column, y), palette)
		panels[key] = entry
		local item = Carousel.new({
			name = key,
			title = title_,
			panel = entry.frame,
			canvas = canvas,
			columnX = column,
			columnWidth = width,
			multi = multi,
			build = build,
			palette = palette,
		})
		carousels[key] = item
		return item
	end

	-- Left column: CUERPO, ROSTRO, CABELLO, ATUENDO, PALETA DE COLOR.
	local bodyPanel = panel(canvas, "BodyPanel", "CUERPO", UDim2.fromOffset(LEFT_WIDTH, 60), at(leftX, COLUMN_TOP), palette)
	panels.body = bodyPanel
	local bodyButtons = {}
	for index, bodyId in CharacterCatalog.BodyBases do
		local info = CharacterCatalog.BodyInfo[bodyId]
		local pill = button(bodyPanel.frame, bodyId, UDim2.new(0.5, -12, 0, 26), UDim2.new((index - 1) * 0.5, if index == 1 then 8 else 4, 0, 28))
		corner(pill, 5)
		stroke(pill, DIM, 0.2, 1)
		local icon = Instance.new("Frame")
		icon.Size = UDim2.fromOffset(16, 22)
		icon.Position = UDim2.fromOffset(10, 3)
		icon.BackgroundTransparency = 1
		icon.Parent = pill
		bodyArt(icon, bodyId == "slim", TEXT)
		label(pill, "Name", info.name, UDim2.new(1, -36, 1, 0), UDim2.fromOffset(32, 0), Enum.Font.SciFi, 13, TEXT)
		bodyButtons[bodyId] = pill
	end

	local faces = carousel("face", "ROSTRO", leftX, LEFT_WIDTH, 184, false, function(art: Frame, faceId: string, pixels: number)
		local head = box(art, "Head", UDim2.fromScale(0.78, 0.78), UDim2.fromScale(0.5, 0.5), CharacterCatalog.SkinToneColors.neutral_medium)
		corner(head, nil, 0.22)
		-- FaceArt clears its canvas on redraw, so the features get their own.
		local features = Instance.new("Frame")
		features.Name = "Features"
		features.Size = UDim2.fromScale(1, 1)
		features.BackgroundTransparency = 1
		features.Parent = head
		FaceArt.Draw(features, faceId, pixels * 0.78, false)
		table.insert(faceArts, { head = head, features = features, faceId = faceId, pixels = pixels * 0.78 })
	end)
	for _, faceId in CharacterCatalog.Faces do
		faces:add(faceId, CharacterCatalog.FaceInfo[faceId].name)
	end

	local hair = carousel("hair", "CABELLO", leftX, LEFT_WIDTH, 284, false, function(art: Frame, hairId: string)
		local info = CharacterCatalog.HairInfo[hairId]
		if info.assetId > 0 then
			thumbnail(art, info.assetId)
		else
			label(art, "None", "—", UDim2.fromScale(1, 1), UDim2.new(), Enum.Font.SciFi, 20, MUTED, Enum.TextXAlignment.Center)
		end
	end)
	for _, hairId in CharacterCatalog.Hair do
		hair:add(hairId, CharacterCatalog.HairInfo[hairId].name)
	end

	-- ATUENDO: one tab per piece (each can be "none"), each with its own row
	-- and MÁS drawer.
	local outfitPanel = panel(canvas, "OutfitPanel", "ATUENDO", UDim2.fromOffset(LEFT_WIDTH, 114), at(leftX, 384), palette)
	panels.outfit = outfitPanel
	local pieceTabs = {}
	local pieceTabWidth = (LEFT_WIDTH - 16 - 12) / 4
	for index, slot in CharacterCatalog.OutfitSlots do
		local tabButton = button(outfitPanel.frame, "PieceTab_" .. slot, UDim2.fromOffset(pieceTabWidth, 18), UDim2.fromOffset(8 + (index - 1) * (pieceTabWidth + 4), 28))
		tabButton.Font = Enum.Font.Code
		tabButton.TextSize = 10
		tabButton.Text = SLOT_NAMES[slot]
		tabButton.TextColor3 = MUTED
		corner(tabButton, 4)
		stroke(tabButton, DIM, 0.2, 1)
		pieceTabs[slot] = tabButton
		local pieceCarousel = Carousel.new({
			name = slot,
			title = SLOT_NAMES[slot],
			panel = outfitPanel.frame,
			rowY = 52,
			canvas = canvas,
			columnX = leftX,
			columnWidth = LEFT_WIDTH,
			multi = false,
			palette = palette,
			build = function(art: Frame, pieceId: string)
				local info = CharacterCatalog.PieceInfo[slot][pieceId]
				if info then
					thumbnail(art, info.assetId or info.left)
				else
					label(art, "None", "—", UDim2.fromScale(1, 1), UDim2.new(), Enum.Font.SciFi, 20, MUTED, Enum.TextXAlignment.Center)
				end
			end,
		})
		pieceCarousel.holder.Visible = index == 1
		for _, pieceId in CharacterCatalog.OutfitPieces[slot] do
			local info = CharacterCatalog.PieceInfo[slot][pieceId]
			pieceCarousel:add(pieceId, if info then info.name else "NINGUNO")
		end
		carousels[slot] = pieceCarousel
	end

	-- PALETA DE COLOR: tabs for skin and the cyberware colours; the bar below
	-- shows the tab's range and can be clicked too.
	local palettePanel = panel(canvas, "PalettePanel", "PALETA DE COLOR", UDim2.fromOffset(LEFT_WIDTH, 96), at(leftX, 504), palette)
	panels.palette = palettePanel
	local tabs = {
		{ id = "skin", label = "PIEL", list = CharacterCatalog.SkinTones, color = function(id) return CharacterCatalog.SkinToneColors[id] end },
		{ id = "neonPrimary", label = "NEÓN 1", list = CharacterCatalog.NeonColors, color = function(id) return CharacterCatalog.NeonColorValues[id] end },
		{ id = "neonSecondary", label = "NEÓN 2", list = CharacterCatalog.NeonColors, color = function(id) return CharacterCatalog.NeonColorValues[id] end },
		{ id = "metal", label = "METAL", list = CharacterCatalog.MetalFinishes, color = function(id) return CharacterCatalog.MetalFinishValues[id].color end },
	}
	local tabButtons, swatchRows, swatches = {}, {}, {}
	local tabWidth = (LEFT_WIDTH - 16 - 12) / 4
	for index, tab in tabs do
		local tabButton = button(palettePanel.frame, "Tab_" .. tab.id, UDim2.fromOffset(tabWidth, 18), UDim2.fromOffset(8 + (index - 1) * (tabWidth + 4), 28))
		tabButton.Font = Enum.Font.Code
		tabButton.TextSize = 10
		tabButton.Text = tab.label
		tabButton.TextColor3 = MUTED
		corner(tabButton, 4)
		stroke(tabButton, DIM, 0.2, 1)
		tabButtons[tab.id] = tabButton
		local row = Instance.new("Frame")
		row.Name = "Swatches_" .. tab.id
		row.Position = UDim2.fromOffset(8, 50)
		row.Size = UDim2.new(1, -16, 0, 22)
		row.BackgroundTransparency = 1
		row.Visible = index == 1
		row.Parent = palettePanel.frame
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = row
		swatchRows[tab.id] = row
		swatches[tab.id] = {}
		for order, colorId in tab.list do
			local swatch = Instance.new("TextButton")
			swatch.Name = colorId
			swatch.LayoutOrder = order
			swatch.Size = UDim2.fromOffset(22, 22)
			swatch.BackgroundColor3 = tab.color(colorId)
			swatch.BorderSizePixel = 0
			swatch.Text = ""
			corner(swatch, nil, 0.5)
			stroke(swatch, DIM, 0.2, 1)
			swatch.Parent = row
			swatches[tab.id][colorId] = swatch
		end
	end
	local bar = button(palettePanel.frame, "Range", UDim2.new(1, -24, 0, 8), UDim2.fromOffset(12, 76))
	bar.AutoButtonColor = false
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.BackgroundTransparency = 0
	corner(bar, nil, 0.5)
	local barGradient = Instance.new("UIGradient")
	barGradient.Parent = bar
	local knob = box(bar, "Knob", UDim2.fromOffset(12, 12), UDim2.fromScale(0, 0.5), TEXT)
	corner(knob, nil, 0.5)
	stroke(knob, palette.Purple, 0, 2)
	local paletteHint = label(palettePanel.frame, "Hint", "", UDim2.new(1, -16, 0, 10), UDim2.fromOffset(8, 84), Enum.Font.Code, 8, MUTED)
	paletteHint.TextTruncate = Enum.TextTruncate.AtEnd

	-- Right column: CLASE, IMPLANTES, ACCESORIOS, VISTA PREVIA // DATOS.
	local classPanel = panel(canvas, "ClassPanel", "CLASE", UDim2.fromOffset(RIGHT_WIDTH, 114), at(rightX, COLUMN_TOP), palette)
	panels.class = classPanel
	local classRow = Instance.new("Frame")
	classRow.Name = "ClassCards"
	classRow.Position = UDim2.fromOffset(8, 32)
	classRow.Size = UDim2.new(1, -16, 0, 74)
	classRow.BackgroundTransparency = 1
	classRow.Parent = classPanel.frame
	local classLayout = Instance.new("UIListLayout")
	classLayout.FillDirection = Enum.FillDirection.Horizontal
	classLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	classLayout.Padding = UDim.new(0, 6)
	classLayout.SortOrder = Enum.SortOrder.LayoutOrder
	classLayout.Parent = classRow
	local classCards = {}
	for index, classId in CharacterCatalog.Classes do
		local card = button(classRow, classId, UDim2.fromOffset(52, 74), UDim2.new())
		card.LayoutOrder = index
		corner(card, 5)
		stroke(card, DIM, 0.2, 1)
		local emblem = Instance.new("Frame")
		emblem.Name = "Emblem"
		emblem.Size = UDim2.fromOffset(34, 34)
		emblem.Position = UDim2.fromOffset(9, 10)
		emblem.BackgroundTransparency = 1
		emblem.Parent = card
		classArt(emblem, classId, CharacterCatalog.ClassInfo[classId].color)
		local name = label(card, "Name", CLASS_NAMES[classId], UDim2.new(1, -4, 0, 12), UDim2.new(0, 2, 1, -18), Enum.Font.Code, 8, TEXT, Enum.TextXAlignment.Center)
		name.TextScaled = true
		local nameSize = Instance.new("UITextSizeConstraint")
		nameSize.MaxTextSize = 8
		nameSize.Parent = name
		classCards[classId] = card
	end

	local implants = carousel("implants", "IMPLANTES", rightX, RIGHT_WIDTH, 240, true, function(art: Frame, implantId: string)
		local inner = Instance.new("Frame")
		inner.Size = UDim2.fromScale(0.8, 0.8)
		inner.Position = UDim2.fromScale(0.1, 0.1)
		inner.BackgroundTransparency = 1
		inner.Parent = art
		implantArt(inner, implantId, palette.Purple)
	end)
	for _, implantId in CharacterCatalog.Implants do
		if IMPLANT_NAMES[implantId] then
			implants:add(implantId, IMPLANT_NAMES[implantId])
		end
	end

	local accessories = carousel("accessories", "ACCESORIOS", rightX, RIGHT_WIDTH, 342, true, function(art: Frame, accessoryId: string)
		thumbnail(art, CharacterCatalog.AccessoryInfo[accessoryId].assetId)
	end)
	for _, accessoryId in CharacterCatalog.Accessories do
		accessories:add(accessoryId, CharacterCatalog.AccessoryInfo[accessoryId].name)
	end

	local statsPanel = panel(canvas, "StatsPanel", "VISTA PREVIA // DATOS", UDim2.fromOffset(RIGHT_WIDTH, 160), at(rightX, 444), palette)
	local portrait = Instance.new("ViewportFrame")
	portrait.Name = "Portrait"
	portrait.Position = UDim2.fromOffset(10, 34)
	portrait.Size = UDim2.fromOffset(104, 116)
	portrait.BackgroundColor3 = Color3.fromRGB(14, 10, 30)
	portrait.Ambient = Color3.fromRGB(150, 140, 185)
	portrait.LightColor = Color3.fromRGB(255, 250, 255)
	portrait.Parent = statsPanel.frame
	corner(portrait, 5)
	stroke(portrait, palette.Purple, 0.4, 1)
	gradient(portrait, Color3.fromRGB(60, 36, 110), Color3.fromRGB(14, 10, 30), 90)
	local portraitWorld = Instance.new("WorldModel")
	portraitWorld.Parent = portrait
	local portraitCamera = Instance.new("Camera")
	portraitCamera.FieldOfView = 30
	portraitCamera.Parent = portrait
	portrait.CurrentCamera = portraitCamera
	local summaryValues = {}
	for index, row in { { "class", "CLASE" }, { "style", "ESTILO" }, { "implants", "IMPLANTES" }, { "palette", "PALETA" } } do
		local y = 34 + (index - 1) * 20
		label(statsPanel.frame, "Key_" .. row[1], row[2], UDim2.fromOffset(70, 16), UDim2.fromOffset(124, y), Enum.Font.Code, 9, MUTED)
		local value = label(statsPanel.frame, "Value_" .. row[1], "—", UDim2.new(1, -204, 0, 16), UDim2.fromOffset(194, y), Enum.Font.Jura, 11, TEXT)
		value.TextTruncate = Enum.TextTruncate.AtEnd
		summaryValues[row[1]] = value
	end
	local quote = label(statsPanel.frame, "Quote", "«MISMO YO.\nDISTINTAS REALIDADES.»", UDim2.new(1, -134, 0, 26), UDim2.fromOffset(124, 114), Enum.Font.Jura, 11, Color3.fromRGB(200, 180, 255))
	quote.TextYAlignment = Enum.TextYAlignment.Top
	local status = label(statsPanel.frame, "DraftStatus", "PREPARANDO VISTA PREVIA", UDim2.new(1, -134, 0, 12), UDim2.fromOffset(124, 142), Enum.Font.Code, 9, palette.Cyan)
	status.TextTruncate = Enum.TextTruncate.AtEnd

	-- Class stats: slide in left of the right column when a class is picked.
	local classStats = Instance.new("CanvasGroup")
	classStats.Name = "ClassStats"
	classStats.AnchorPoint = Vector2.new(1, 0)
	classStats.Position = UDim2.new(1, CLASS_STATS_X, 0, COLUMN_TOP)
	classStats.Size = UDim2.fromOffset(220, 216)
	classStats.BackgroundColor3 = palette.Glass
	classStats.BackgroundTransparency = 0.12
	classStats.BorderSizePixel = 0
	classStats.GroupTransparency = 1
	classStats.Visible = false
	-- Above the drag surface, which covers the middle of the screen.
	classStats.ZIndex = 5
	classStats.Parent = canvas
	corner(classStats, 6)
	local classStatsStroke = stroke(classStats, palette.Purple, 0.3, 1.5)
	gradient(classStats, Color3.fromRGB(40, 26, 80), Color3.fromRGB(10, 8, 22), 115)
	local classEmblem = Instance.new("Frame")
	classEmblem.Name = "Emblem"
	classEmblem.Position = UDim2.fromOffset(12, 12)
	classEmblem.Size = UDim2.fromOffset(44, 44)
	classEmblem.BackgroundTransparency = 1
	classEmblem.Parent = classStats
	local className = label(classStats, "ClassName", "", UDim2.new(1, -96, 0, 22), UDim2.fromOffset(64, 10), Enum.Font.SciFi, 18, TEXT)
	local classRole = label(classStats, "Role", "", UDim2.new(1, -74, 0, 30), UDim2.fromOffset(64, 32), Enum.Font.Jura, 10, MUTED)
	classRole.TextWrapped = true
	classRole.TextYAlignment = Enum.TextYAlignment.Top
	label(classStats, "Heading", "ESTADÍSTICAS DE CLASE", UDim2.new(1, -24, 0, 12), UDim2.fromOffset(12, 66), Enum.Font.Code, 9, palette.Purple)
	local classPips = {}
	for index, statKey in CharacterCatalog.ClassStatKeys do
		local y = 86 + (index - 1) * 25
		label(classStats, "Stat_" .. statKey, STAT_NAMES[statKey] or statKey, UDim2.fromOffset(80, 14), UDim2.fromOffset(12, y), Enum.Font.Code, 9, TEXT)
		local pips = {}
		for pip = 1, 5 do
			local segment = box(classStats, "Pip", UDim2.fromOffset(20, 8), UDim2.fromOffset(94 + (pip - 1) * 23, y + 3), DIM, 0, Vector2.new(0, 0))
			corner(segment, 2)
			table.insert(pips, segment)
		end
		classPips[statKey] = pips
	end
	local classStatsClose = button(classStats, "Close", UDim2.fromOffset(22, 22), UDim2.new(1, -8, 0, 8), Vector2.new(1, 0))
	corner(classStatsClose, 4)
	classStatsClose.Font = Enum.Font.Code
	classStatsClose.Text = "×"
	classStatsClose.TextSize = 14
	classStatsClose.TextColor3 = TEXT

	-- Drag to turn the avatar; the wheel zooms.
	local interaction = Instance.new("Frame")
	interaction.Name = "PreviewInteractionSurface"
	interaction.Position = UDim2.fromOffset(MARGIN + LEFT_WIDTH + 20, 110)
	interaction.Size = UDim2.new(1, -(MARGIN * 2 + LEFT_WIDTH + RIGHT_WIDTH + 40), 1, -230)
	interaction.BackgroundTransparency = 1
	interaction.Active = true
	interaction.Parent = canvas

	-- Bottom row: ALEATORIO, CONFIRMAR (+ INICIAR VIAJE), RESTABLECER.
	local function actionButton(name: string, text: string, size: UDim2, position: UDim2, anchor: Vector2, textSize: number): TextButton
		local item = button(canvas, name, size, position, anchor)
		corner(item, 6)
		stroke(item, palette.Purple, 0.3, 1.5)
		gradient(item, Color3.fromRGB(36, 22, 70), Color3.fromRGB(14, 10, 30), 90)
		label(item, "Label", text, UDim2.new(1, -44, 1, 0), UDim2.fromOffset(40, 0), Enum.Font.SciFi, textSize, TEXT)
		return item
	end
	local randomize = actionButton("Randomize", "ALEATORIO", UDim2.fromOffset(170, 40), UDim2.new(0.5, -168, 1, -54), Vector2.new(1, 1), 15)
	local shuffle = Instance.new("Frame")
	shuffle.Size = UDim2.fromOffset(20, 16)
	shuffle.Position = UDim2.fromOffset(13, 12)
	shuffle.BackgroundTransparency = 1
	shuffle.Parent = randomize
	for _, rotation in { 28, -28 } do
		box(shuffle, "Arrow", UDim2.fromScale(1, 0.14), UDim2.fromScale(0.5, 0.5), TEXT).Rotation = rotation
	end
	local reset = actionButton("ResetDraft", "RESTABLECER", UDim2.fromOffset(170, 40), UDim2.new(0.5, 168, 1, -54), Vector2.new(0, 1), 14)
	local resetIcon = Instance.new("Frame")
	resetIcon.Size = UDim2.fromOffset(18, 18)
	resetIcon.Position = UDim2.fromOffset(13, 11)
	resetIcon.BackgroundTransparency = 1
	resetIcon.Parent = reset
	ring(resetIcon, "Loop", UDim2.fromScale(0.85, 0.85), UDim2.fromScale(0.5, 0.5), TEXT, 2)
	box(resetIcon, "Gap", UDim2.fromScale(0.36, 0.36), UDim2.fromScale(0.8, 0.2), Color3.fromRGB(28, 18, 56))
	box(resetIcon, "Tip", UDim2.fromScale(0.3, 0.3), UDim2.fromScale(0.72, 0.12), TEXT).Rotation = 45

	local confirm = button(canvas, "ConfirmIdentity", UDim2.fromOffset(290, 52), UDim2.new(0.5, 0, 1, -50), Vector2.new(0.5, 1))
	corner(confirm, 6)
	local confirmStroke = stroke(confirm, Color3.fromRGB(200, 150, 255), 0.2, 2)
	gradient(confirm, Color3.fromRGB(120, 60, 220), Color3.fromRGB(56, 22, 118), 90)
	local confirmLabel = label(confirm, "Label", spaced("CONFIRMAR"), UDim2.fromScale(1, 1), UDim2.new(), Enum.Font.SciFi, 22, TEXT, Enum.TextXAlignment.Center)

	return setmetatable({
		_config = config,
		_palette = palette,
		_screen = screen,
		_canvas = canvas,
		_scale = scale,
		_viewportConnection = nil :: RBXScriptConnection?,
		_panels = panels,
		_carousels = carousels,
		_faceArts = faceArts,
		_female = false,
		_bodyButtons = bodyButtons,
		_classCards = classCards,
		_tabs = tabs,
		_tabButtons = tabButtons,
		_swatchRows = swatchRows,
		_swatches = swatches,
		_activeTab = "skin",
		_paletteSelected = {} :: { [string]: string },
		_bar = bar,
		_barGradient = barGradient,
		_knob = knob,
		_paletteHint = paletteHint,
		_hasImplants = false,
		_portrait = portrait,
		_portraitWorld = portraitWorld,
		_portraitCamera = portraitCamera,
		_summary = summaryValues,
		_status = status,
		_interaction = interaction,
		_randomize = randomize,
		_reset = reset,
		_confirm = confirm,
		_confirmStroke = confirmStroke,
		_confirmLabel = confirmLabel,
		_ready = false,
		_pulse = nil :: Tween?,
		_names = {} :: { [string]: string },
		_pieceTabs = pieceTabs,
		_activePiece = "jacket",
		_pieces = {} :: { [string]: string },
		_classStats = classStats,
		_classStatsStroke = classStatsStroke,
		_classEmblem = classEmblem,
		_className = className,
		_classRole = classRole,
		_classPips = classPips,
		_classStatsClose = classStatsClose,
		_classStatsTween = nil :: Tween?,
		_controlsEnabled = false,
		_controlConnections = {} :: { RBXScriptConnection },
		_dragging = false,
		_lastDragX = 0,
	}, MorphLabUI)
end

-- ----------------------------------------------------------- selection --

-- Panel header: the selected name and how many options there are.
function MorphLabUI:_detail(key: string, name: string?)
	if name then
		self._names[key] = name
	end
	local carousel = self._carousels[key]
	self._panels[key].detail.Text = string.format("%s · %d", self._names[key] or "", carousel:count())
end

function MorphLabUI:SetSelectedBodyBase(bodyBaseId: string)
	for id, pill in self._bodyButtons do
		styleCard(pill, id == bodyBaseId, self._palette.Purple)
	end
	self._panels.body.detail.Text = if bodyBaseId == "slim" then "FEMENINO" else "MASCULINO"
end

-- Hair for the body's gender ("m"/"f"; "both" always shows); the face cards
-- get lashes on the slim body, like the avatar.
function MorphLabUI:SetGender(gender: string)
	local hair = self._carousels.hair
	hair.filter = function(hairId: string): boolean
		local info = CharacterCatalog.HairInfo[hairId]
		return not info or info.gender == "both" or info.gender == gender
	end
	hair:refresh()
	self:_detail("hair")
	local female = gender == "f"
	if female ~= self._female then
		self._female = female
		for _, art in self._faceArts do
			FaceArt.Draw(art.features, art.faceId, art.pixels, female)
		end
	end
end

function MorphLabUI:SetSelectedFace(faceId: string)
	self._carousels.face:setSelected({ faceId })
	local info = CharacterCatalog.FaceInfo[faceId]
	self:_detail("face", if info then info.name else "")
end

function MorphLabUI:SetSelectedHair(hairId: string)
	self._carousels.hair:setSelected({ hairId })
	local info = CharacterCatalog.HairInfo[hairId]
	self:_detail("hair", if info then info.name else "")
end

-- Worn pieces by slot ("none" = not worn).
function MorphLabUI:SetSelectedPieces(pieces: { [string]: string })
	self._pieces = table.clone(pieces)
	for _, slot in CharacterCatalog.OutfitSlots do
		self._carousels[slot]:setSelected({ pieces[slot] or "none" })
	end
	self:_refreshPieceTabs()
end

-- Shows the active piece tab's row; the header names what it holds.
function MorphLabUI:_setPieceTab(slot: string)
	self._activePiece = slot
	self:_closeDrawers()
	self:_refreshPieceTabs()
end

function MorphLabUI:_refreshPieceTabs()
	local active = self._activePiece
	for slot, tabButton in self._pieceTabs do
		local selected = slot == active
		styleCard(tabButton, selected, self._palette.Purple)
		tabButton.TextColor3 = if selected then TEXT else MUTED
		self._carousels[slot].holder.Visible = selected
	end
	local info = CharacterCatalog.PieceInfo[active][self._pieces[active] or ""]
	self._panels.outfit.detail.Text = string.format("%s · %d", if info then info.name else "NINGUNO", self._carousels[active]:count())
end

-- Class card: emblem, role and the five stats, sliding in from the right.
function MorphLabUI:ShowClassStats(classId: string)
	local info = CharacterCatalog.ClassInfo[classId]
	if not info then
		return
	end
	self._classEmblem:ClearAllChildren()
	classArt(self._classEmblem, classId, info.color)
	self._className.Text = CLASS_NAMES[classId] or classId
	self._className.TextColor3 = info.color
	self._classRole.Text = CLASS_ROLES[classId] or ""
	self._classStatsStroke.Color = info.color
	for statKey, pips in self._classPips do
		local value = info.stats[statKey] or 0
		for index, pip in pips do
			pip.BackgroundColor3 = if index <= value then info.color else DIM
		end
	end
	local panel = self._classStats
	if self._classStatsTween then
		self._classStatsTween:Cancel()
	end
	if not panel.Visible then
		panel.Visible = true
		panel.GroupTransparency = 1
		panel.Position = UDim2.new(1, CLASS_STATS_X + 24, 0, COLUMN_TOP)
	end
	self._classStatsTween = TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
		Position = UDim2.new(1, CLASS_STATS_X, 0, COLUMN_TOP),
	})
	self._classStatsTween:Play()
end

function MorphLabUI:HideClassStats()
	local panel = self._classStats
	if not panel.Visible then
		return
	end
	if self._classStatsTween then
		self._classStatsTween:Cancel()
	end
	local tween = TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
		GroupTransparency = 1,
		Position = UDim2.new(1, CLASS_STATS_X + 24, 0, COLUMN_TOP),
	})
	self._classStatsTween = tween
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			panel.Visible = false
		end
	end)
	tween:Play()
end

function MorphLabUI:SetSelectedAccessories(accessoryIds: { string })
	self._carousels.accessories:setSelected(accessoryIds)
	self._panels.accessories.detail.Text = string.format("%d / %d", #accessoryIds, CharacterCatalog.MaxAccessories)
end

function MorphLabUI:SetSelectedImplants(implantIds: { string })
	local installed = {}
	for _, implantId in implantIds do
		if implantId ~= "none" then
			table.insert(installed, implantId)
		end
	end
	self._carousels.implants:setSelected(installed)
	self._panels.implants.detail.Text = string.format("%d / %d", #installed, CharacterCatalog.MaxImplants)
end

function MorphLabUI:SetSelectedClass(classId: string?)
	for id, card in self._classCards do
		styleCard(card, id == classId, CharacterCatalog.ClassInfo[id].color)
	end
	self._panels.class.detail.Text = if classId then CLASS_NAMES[classId] or "" else ""
end

-- Skin tone: palette PIEL tab, and the face cards take the same colour.
function MorphLabUI:SetSelectedSkinTone(skinToneId: string)
	self._paletteSelected.skin = skinToneId
	local color = CharacterCatalog.SkinToneColors[skinToneId]
	if color then
		for _, art in self._faceArts do
			art.head.BackgroundColor3 = color
		end
	end
	self:_refreshPalette()
end

function MorphLabUI:SetSelectedColors(colors: { [string]: string }?)
	local selected = colors or CharacterCatalog.DefaultColors
	for _, slot in CharacterCatalog.ColorSlots do
		self._paletteSelected[slot] = selected[slot] or CharacterCatalog.DefaultColors[slot]
	end
	self:_refreshPalette()
end

-- The cyberware colours only show on installed implants; say so.
function MorphLabUI:SetColorHint(hasImplants: boolean)
	self._hasImplants = hasImplants
	self:_refreshPalette()
end

function MorphLabUI:_tab(tabId: string)
	for _, entry in self._tabs do
		if entry.id == tabId then
			return entry
		end
	end
	return self._tabs[1]
end

function MorphLabUI:_refreshPalette()
	local tabId = self._activeTab
	local tab = self:_tab(tabId)
	for id, tabButton in self._tabButtons do
		local active = id == tabId
		styleCard(tabButton, active, self._palette.Purple)
		tabButton.TextColor3 = if active then TEXT else MUTED
		self._swatchRows[id].Visible = active
	end
	local selectedId = self._paletteSelected[tabId]
	for id, swatch in self._swatches[tabId] do
		local selected = id == selectedId
		local outline = swatch:FindFirstChildOfClass("UIStroke")
		if outline then
			outline.Color = if selected then TEXT else DIM
			outline.Transparency = if selected then 0 else 0.2
			outline.Thickness = if selected then 2.5 else 1
		end
	end
	-- Range bar: the tab's colours in order, knob on the selected one.
	local keypoints = {}
	local count = #tab.list
	for index, id in tab.list do
		table.insert(keypoints, ColorSequenceKeypoint.new(if count > 1 then (index - 1) / (count - 1) else 0, tab.color(id)))
	end
	if count == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, tab.color(tab.list[1])))
	end
	self._barGradient.Color = ColorSequence.new(keypoints)
	local index = table.find(tab.list, selectedId) or 1
	self._knob.Position = UDim2.fromScale(if count > 1 then (index - 1) / (count - 1) else 0, 0.5)
	self._paletteHint.Text = if tabId == "skin" then "TONO DE PIEL"
		elseif self._hasImplants then "SE APLICA A TUS IMPLANTES"
		else "INSTALA IMPLANTES PARA VER ESTOS COLORES"
	self._panels.palette.detail.Text = if tabId == "skin" then "PIEL"
		elseif tabId == "metal" then METAL_NAMES[selectedId or ""] or ""
		else NEON_NAMES[selectedId or ""] or ""
end

-- VISTA PREVIA // DATOS rows.
function MorphLabUI:SetSummary(draft)
	local values = self._summary
	values.class.Text = CLASS_NAMES[draft.classId or ""] or "—"
	-- The outermost piece worn names the style.
	local style = "ROPA INTERIOR"
	local pieces = CharacterDraft.pieces(draft)
	for _, slot in { "jacket", "shirt", "pants", "shoes" } do
		local info = CharacterCatalog.PieceInfo[slot][pieces[slot] or ""]
		if info then
			style = info.name
			break
		end
	end
	values.style.Text = style
	local implants = 0
	for _, implantId in draft.cyberwareIds do
		implants += if implantId ~= "none" then 1 else 0
	end
	values.implants.Text = if implants > 0 then string.format("%d EQUIPADO%s", implants, if implants == 1 then "" else "S") else "NINGUNO"
	local colors = draft.colors or CharacterCatalog.DefaultColors
	values.palette.Text = string.format("%s / %s", NEON_NAMES[colors.neonPrimary] or "—", METAL_NAMES[colors.metal] or "—")
end

-- Head-and-shoulders copy of the avatar in the stats panel (nil clears it).
function MorphLabUI:SetPortrait(model: Model?)
	self._portraitWorld:ClearAllChildren()
	if not model then
		return
	end
	local copy = model:Clone()
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	-- SurfaceGuis do not render here: the face is copied as thin parts.
	FaceArt.ToParts(copy)
	copy.Parent = self._portraitWorld
	local head = copy:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	-- Head and shoulders, three-quarter, lit from the front.
	local frame = head.CFrame
	local target = head.Position - Vector3.new(0, 0.55, 0)
	local eye = target + frame.LookVector * 4.6 - frame.RightVector * 1.3 + Vector3.new(0, 0.3, 0)
	self._portraitCamera.CFrame = CFrame.lookAt(eye, target)
	self._portrait.LightDirection = (-frame.LookVector + frame.RightVector * 0.5 - Vector3.new(0, 0.7, 0)).Unit
end

function MorphLabUI:SetCategoryCompleted(categoryId: string, completed: boolean)
	for _, panelId in CATEGORY_PANELS[categoryId] or {} do
		local entry = self._panels[panelId]
		if entry then
			setPanelDone(entry, completed, self._palette)
		end
	end
end

-- CONFIRMAR is always available; the sections only get their check marks.
function MorphLabUI:SetProgress(_completed: number, _total: number)
	local ready = true
	self._confirmLabel.TextTransparency = 0
	self._confirm.BackgroundTransparency = 0
	if ready == self._ready then
		return
	end
	self._ready = ready
	if self._pulse then
		self._pulse:Cancel()
		self._pulse = nil
	end
	self._confirmStroke.Transparency = if ready then 0 else 0.6
	if ready then
		self._pulse = TweenService:Create(self._confirmStroke, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.55 })
		self._pulse:Play()
	end
end

function MorphLabUI:SetAvatarStatus(text: string, isError: boolean?)
	self._status.Text = text
	self._status.TextColor3 = if isError then ERROR else self._palette.Cyan
end

function MorphLabUI:SetControlsEnabled(enabled: boolean)
	self._controlsEnabled = enabled
	self._interaction.Active = enabled
	if not enabled then
		self:_closeDrawers()
	end
end

function MorphLabUI:_closeDrawers(except: any?)
	for _, carousel in self._carousels do
		if carousel ~= except then
			carousel:close()
		end
	end
end

-- ------------------------------------------------------------- input --

function MorphLabUI:BindControls(callbacks)
	local connections = self._controlConnections
	local function on(target: GuiButton, action: () -> ())
		table.insert(connections, target.Activated:Connect(function()
			if self._controlsEnabled then
				action()
			end
		end))
	end
	for bodyId, pill in self._bodyButtons do
		on(pill, function()
			callbacks.bodyBase(bodyId)
		end)
	end
	local picks = {
		face = callbacks.face,
		hair = callbacks.hairStyle,
		implants = callbacks.implant,
		accessories = callbacks.accessory,
	}
	for _, slot in CharacterCatalog.OutfitSlots do
		picks[slot] = function(pieceId: string)
			callbacks.piece(slot, pieceId)
		end
	end
	for slot, tabButton in self._pieceTabs do
		-- Tabs only switch the view, so they work while controls are locked too.
		table.insert(connections, tabButton.Activated:Connect(function()
			self:_setPieceTab(slot)
		end))
	end
	on(self._classStatsClose, callbacks.closeClassStats)
	for key, carousel in self._carousels do
		local pick = picks[key]
		carousel:refresh()
		on(carousel.more, function()
			if carousel.isOpen then
				carousel:close()
			else
				self:_closeDrawers(carousel)
				carousel:open()
			end
		end)
		on(carousel.closeButton, function()
			carousel:close()
		end)
		for id, card in carousel.rowCards do
			on(card, function()
				pick(id)
			end)
		end
		for id, card in carousel.gridCards do
			on(card, function()
				pick(id)
			end)
		end
	end
	for classId, card in self._classCards do
		on(card, function()
			callbacks.class(classId)
		end)
	end
	local function pickColor(tabId: string, colorId: string)
		if tabId == "skin" then
			callbacks.skinTone(colorId)
		else
			callbacks.color(tabId, colorId)
		end
	end
	for tabId, tabButton in self._tabButtons do
		-- Tabs only switch the view, so they work while controls are locked too.
		table.insert(connections, tabButton.Activated:Connect(function()
			self._activeTab = tabId
			self:_refreshPalette()
		end))
		for colorId, swatch in self._swatches[tabId] do
			on(swatch, function()
				pickColor(tabId, colorId)
			end)
		end
	end
	-- Clicking the range bar picks the nearest colour of the active tab.
	table.insert(connections, self._bar.InputBegan:Connect(function(input)
		if not self._controlsEnabled then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local tab = self:_tab(self._activeTab)
		local ratio = math.clamp((input.Position.X - self._bar.AbsolutePosition.X) / math.max(self._bar.AbsoluteSize.X, 1), 0, 1)
		pickColor(tab.id, tab.list[math.floor(ratio * (#tab.list - 1) + 0.5) + 1])
	end))
	on(self._randomize, callbacks.randomize)
	on(self._reset, callbacks.resetDraft)
	on(self._confirm, function()
		if self._ready then
			callbacks.confirm()
		end
	end)
	table.insert(connections, self._interaction.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self._dragging = true
			self._lastDragX = input.Position.X
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if self._dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local deltaX = input.Position.X - self._lastDragX
			self._lastDragX = input.Position.X
			callbacks.drag(deltaX)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and self._screen.Enabled and self._controlsEnabled then
			-- The wheel scrolls an open drawer instead of zooming.
			for _, carousel in self._carousels do
				if carousel.isOpen then
					return
				end
			end
			callbacks.zoom(-input.Position.Z)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self._dragging = false
		end
	end))
	self:_refreshPalette()
end

-- --------------------------------------------------------- lifecycle --

function MorphLabUI:Show()
	self._screen.Enabled = true
	local camera = workspace.CurrentCamera
	if camera then
		local function updateScale()
			local viewport = camera.ViewportSize
			local inset = GuiService:GetGuiInset()
			local scale = math.clamp(math.min(viewport.X / DESIGN.X, (viewport.Y - inset.Y) / DESIGN.Y), 0.5, 2)
			self._scale.Scale = scale
			-- The canvas fills the screen after scaling.
			self._canvas.Size = UDim2.fromScale(1 / scale, 1 / scale)
		end
		updateScale()
		if self._viewportConnection then
			self._viewportConnection:Disconnect()
		end
		self._viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end

function MorphLabUI:Hide()
	if self._viewportConnection then
		self._viewportConnection:Disconnect()
		self._viewportConnection = nil
	end
	self._dragging = false
	self:_closeDrawers()
	self._screen.Enabled = false
end

function MorphLabUI:Destroy()
	self:Hide()
	for _, connection in self._controlConnections do
		connection:Disconnect()
	end
	table.clear(self._controlConnections)
	if self._pulse then
		self._pulse:Cancel()
		self._pulse = nil
	end
	self._screen:Destroy()
end

function MorphLabUI:IsVisible(): boolean
	return self._screen.Enabled
end

return MorphLabUI
