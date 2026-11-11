--!strict

-- MODO LIBRE overlay: location tag, the shared clock (DÍA / NOCHE), control
-- hints, a MENÚ button and, on touch screens, a CORRER toggle.

local UserInputService = game:GetService("UserInputService")

local BitmapText = require(script.Parent.Parent.UI.BitmapText)

local FreeRoamHUD = {}
FreeRoamHUD.__index = FreeRoamHUD

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
	item.Parent = parent
	return item
end

local function panel(parent: Instance, name: string, size: UDim2, position: UDim2, accent: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Color3.fromRGB(6, 12, 24)
	frame.BackgroundTransparency = 0.3
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Transparency = 0.35
	stroke.Parent = frame
	return frame
end

local function button(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, accent: Color3, font: Enum.Font): TextButton
	local item = Instance.new("TextButton")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundColor3 = Color3.fromRGB(8, 20, 36)
	item.BackgroundTransparency = 0.15
	item.Font = font
	item.Text = text
	item.TextSize = 16
	item.TextColor3 = Color3.fromRGB(230, 240, 255)
	item.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = item
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = accent
	stroke.Thickness = 1.5
	stroke.Parent = item
	return item
end

function FreeRoamHUD.new(playerGui: PlayerGui, config)
	local palette = config.Palette
	local typography = config.Typography
	local screen = Instance.new("ScreenGui")
	screen.Name = "FreeRoamHUD"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 40
	screen.Enabled = false
	screen.Parent = playerGui

	local location = panel(screen, "Location", UDim2.fromOffset(250, 58), UDim2.fromOffset(16, 12), palette.Magenta)
	label(location, "Mode", "MODO LIBRE", UDim2.new(1, -24, 0, 26), UDim2.fromOffset(12, 6), typography.Display, 20, palette.Text)
	label(location, "Place", "NEO-EDEN // SECTOR 7", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 32), typography.Technical, 12, palette.Cyan)

	local clock = panel(screen, "Clock", UDim2.fromOffset(170, 50), UDim2.new(0.5, -85, 0, 12), palette.Cyan)
	local time = label(clock, "Time", "08:30", UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 4), typography.Display, 24, palette.Text)
	time.TextXAlignment = Enum.TextXAlignment.Center
	local phase = label(clock, "Phase", "DÍA", UDim2.new(1, -16, 0, 14), UDim2.fromOffset(8, 32), typography.Technical, 11, palette.Cyan)
	phase.TextXAlignment = Enum.TextXAlignment.Center

	local exit = button(screen, "Lobby", "MENÚ", UDim2.fromOffset(120, 40), UDim2.new(1, -136, 0, 16), palette.Magenta, typography.Display)

	local hints = label(screen, "Hints", "WASD  MOVERSE   ·   ESPACIO  SALTAR   ·   SHIFT  CORRER", UDim2.fromOffset(520, 20), UDim2.new(0, 16, 1, -34), typography.Technical, 13, Color3.fromRGB(190, 200, 220))
	hints.Visible = not UserInputService.TouchEnabled

	-- Touch: sprint toggle above the jump button.
	local sprint = button(screen, "Sprint", "CORRER", UDim2.fromOffset(96, 44), UDim2.new(1, -200, 1, -150), palette.Cyan, typography.Display)
	sprint.Visible = UserInputService.TouchEnabled

	BitmapText.BindTree(screen, typography)
	return setmetatable({
		_screen = screen,
		_time = time,
		_phase = phase,
		_exit = exit,
		_sprint = sprint,
		_palette = palette,
		_connections = {},
	}, FreeRoamHUD)
end

function FreeRoamHUD:Bind(callbacks)
	table.insert(self._connections, self._exit.Activated:Connect(function()
		if callbacks.exit then
			callbacks.exit()
		end
	end))
	table.insert(self._connections, self._sprint.Activated:Connect(function()
		if callbacks.toggleSprint then
			callbacks.toggleSprint()
		end
	end))
end

function FreeRoamHUD:SetClock(hour: number, night: boolean)
	local whole = math.floor(hour)
	local minutes = math.floor((hour - whole) * 60 / 5) * 5
	self._time.Text = string.format("%02d:%02d", whole, minutes)
	self._phase.Text = if night then "NOCHE" else "DÍA"
	self._phase.TextColor3 = if night then self._palette.Magenta else self._palette.Cyan
end

function FreeRoamHUD:SetSprinting(sprinting: boolean)
	local stroke = self._sprint:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if sprinting then self._palette.Magenta else self._palette.Cyan
	end
end

function FreeRoamHUD:Show()
	self._screen.Enabled = true
end

function FreeRoamHUD:Hide()
	self._screen.Enabled = false
end

function FreeRoamHUD:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._screen:Destroy()
end

return FreeRoamHUD
