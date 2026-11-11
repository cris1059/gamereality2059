--!strict

local TweenService = game:GetService("TweenService")
local BitmapText = require(script.Parent.Parent.UI.BitmapText)

local ModuleLoadingScreen = {}
ModuleLoadingScreen.__index = ModuleLoadingScreen

local MINIMUM_VISIBLE_TIME = 0.7

local function addCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

function ModuleLoadingScreen.new(playerGui: PlayerGui, config)
	local palette = config.Palette
	local typography = config.Typography
	local screen = Instance.new("ScreenGui")
	screen.Name = "ModuleLoadingUI"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 200
	screen.Enabled = false
	screen.Parent = playerGui

	local overlay = Instance.new("CanvasGroup")
	overlay.Name = "LoadingOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(2, 8, 22)
	overlay.BorderSizePixel = 0
	overlay.Parent = screen

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(2, 9, 25)),
		ColorSequenceKeypoint.new(0.52, Color3.fromRGB(7, 30, 58)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(28, 4, 37)),
	})
	gradient.Rotation = 110
	gradient.Parent = overlay

	local protocol = Instance.new("TextLabel")
	protocol.Name = "Protocol"
	protocol.Size = UDim2.new(0, 360, 0, 24)
	protocol.Position = UDim2.fromOffset(28, 28)
	protocol.BackgroundTransparency = 1
	protocol.Font = typography.Technical
	protocol.Text = "REALITY 2059 // PROTOCOLO DE TRANSFERENCIA"
	protocol.TextColor3 = palette.Cyan
	protocol.TextSize = 14
	protocol.TextXAlignment = Enum.TextXAlignment.Left
	protocol.Parent = overlay

	local destination = Instance.new("TextLabel")
	destination.Name = "Destination"
	destination.AnchorPoint = Vector2.new(0.5, 1)
	destination.Position = UDim2.new(0.5, 0, 0.46, 0)
	destination.Size = UDim2.new(0.8, 0, 0, 58)
	destination.BackgroundTransparency = 1
	destination.Font = typography.Display
	destination.Text = "PREPARANDO MÓDULO"
	destination.TextColor3 = palette.Text
	destination.TextScaled = true
	destination.Parent = overlay
	local destinationSize = Instance.new("UITextSizeConstraint")
	destinationSize.MinTextSize = 20
	destinationSize.MaxTextSize = 38
	destinationSize.Parent = destination

	local stage = Instance.new("TextLabel")
	stage.Name = "Stage"
	stage.AnchorPoint = Vector2.new(0.5, 0)
	stage.Position = UDim2.new(0.5, 0, 0.49, 0)
	stage.Size = UDim2.new(0.8, 0, 0, 34)
	stage.BackgroundTransparency = 1
	stage.Font = typography.Technical
	stage.Text = "ESTABLECIENDO ENLACE SEGURO"
	stage.TextColor3 = palette.Cyan
	stage.TextSize = 15
	stage.Parent = overlay

	local rail = Instance.new("Frame")
	rail.Name = "ProgressRail"
	rail.AnchorPoint = Vector2.new(0.5, 0)
	rail.Position = UDim2.new(0.5, 0, 0.56, 0)
	rail.Size = UDim2.new(0.46, 0, 0, 8)
	rail.BackgroundColor3 = Color3.fromRGB(13, 24, 42)
	rail.BorderSizePixel = 0
	addCorner(rail, 4)
	rail.Parent = overlay
	local railStroke = Instance.new("UIStroke")
	railStroke.Color = palette.Cyan
	railStroke.Transparency = 0.42
	railStroke.Parent = rail

	local fill = Instance.new("Frame")
	fill.Name = "Progress"
	fill.Size = UDim2.fromScale(0.04, 1)
	fill.BackgroundColor3 = palette.Cyan
	fill.BorderSizePixel = 0
	addCorner(fill, 4)
	fill.Parent = rail
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new(palette.Cyan, palette.Magenta)
	fillGradient.Parent = fill

	local percentage = Instance.new("TextLabel")
	percentage.Name = "Percentage"
	percentage.AnchorPoint = Vector2.new(0.5, 0)
	percentage.Position = UDim2.new(0.5, 0, 0.585, 0)
	percentage.Size = UDim2.fromOffset(120, 24)
	percentage.BackgroundTransparency = 1
	percentage.Font = typography.Technical
	percentage.Text = "04%"
	percentage.TextColor3 = palette.Magenta
	percentage.TextSize = 13
	percentage.Parent = overlay

	local scan = Instance.new("Frame")
	scan.Name = "ScanLine"
	scan.Size = UDim2.new(1, 0, 0, 2)
	scan.BackgroundColor3 = palette.Cyan
	scan.BackgroundTransparency = 0.55
	scan.BorderSizePixel = 0
	scan.Parent = overlay
	BitmapText.BindTree(screen, typography)

	return setmetatable({
		_screen = screen,
		_overlay = overlay,
		_destination = destination,
		_stage = stage,
		_fill = fill,
		_percentage = percentage,
		_scan = scan,
		_progressTween = nil,
		_scanTween = nil,
		_startedAt = 0,
		_finishing = false,
	}, ModuleLoadingScreen)
end

function ModuleLoadingScreen:Show(destination: string)
	if self._scanTween then
		self._scanTween:Cancel()
	end
	self._finishing = false
	self._startedAt = os.clock()
	self._destination.Text = destination
	self._stage.Text = "ESTABLECIENDO ENLACE SEGURO"
	self._fill.Size = UDim2.fromScale(0.04, 1)
	self._percentage.Text = "04%"
	self._overlay.GroupTransparency = 0
	self._scan.Position = UDim2.fromScale(0, 0)
	self._screen.Enabled = true
	self._scanTween = TweenService:Create(
		self._scan,
		TweenInfo.new(1.35, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Position = UDim2.fromScale(0, 1) }
	)
	self._scanTween:Play()
end

function ModuleLoadingScreen:SetStage(text: string, progress: number)
	if not self._screen.Enabled then
		return
	end
	local clamped = math.clamp(progress, 0.04, 1)
	self._stage.Text = text
	self._percentage.Text = string.format("%02d%%", math.floor(clamped * 100 + 0.5))
	if self._progressTween then
		self._progressTween:Cancel()
	end
	self._progressTween = TweenService:Create(
		self._fill,
		TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(clamped, 1) }
	)
	self._progressTween:Play()
end

function ModuleLoadingScreen:Finish()
	if not self._screen.Enabled or self._finishing then
		return
	end
	self._finishing = true
	self:SetStage("MÓDULO LISTO", 1)
	local remaining = MINIMUM_VISIBLE_TIME - (os.clock() - self._startedAt)
	if remaining > 0 then
		task.wait(remaining)
	end
	local fade = TweenService:Create(self._overlay, TweenInfo.new(0.28), { GroupTransparency = 1 })
	fade:Play()
	fade.Completed:Wait()
	if self._scanTween then
		self._scanTween:Cancel()
		self._scanTween = nil
	end
	self._screen.Enabled = false
	self._finishing = false
end

function ModuleLoadingScreen:Destroy()
	if self._progressTween then
		self._progressTween:Cancel()
	end
	if self._scanTween then
		self._scanTween:Cancel()
	end
	self._screen:Destroy()
end

return ModuleLoadingScreen
