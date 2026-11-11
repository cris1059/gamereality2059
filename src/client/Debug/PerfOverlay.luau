--!strict

-- F3: small performance readout (FPS, frame time, ping, memory, ambient
-- agents) for measuring changes on real devices. Hidden by default.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local PerfOverlay = {}

function PerfOverlay.Start(playerGui: PlayerGui, font: Enum.Font)
	local screen = Instance.new("ScreenGui")
	screen.Name = "Reality2059Perf"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 200
	screen.Enabled = false
	screen.Parent = playerGui
	local readout = Instance.new("TextLabel")
	readout.Position = UDim2.fromOffset(8, 8)
	readout.Size = UDim2.fromOffset(250, 110)
	readout.BackgroundColor3 = Color3.new(0, 0, 0)
	readout.BackgroundTransparency = 0.35
	readout.BorderSizePixel = 0
	readout.Font = font
	readout.TextSize = 13
	readout.TextColor3 = Color3.fromRGB(90, 255, 180)
	readout.TextXAlignment = Enum.TextXAlignment.Left
	readout.TextYAlignment = Enum.TextYAlignment.Top
	readout.Parent = screen
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.Parent = readout

	local frames, elapsed, worst = 0, 0, 0
	RunService.RenderStepped:Connect(function(deltaTime)
		if not screen.Enabled then
			return
		end
		frames += 1
		elapsed += deltaTime
		worst = math.max(worst, deltaTime)
		if elapsed < 0.5 then
			return
		end
		local life = Workspace:FindFirstChild("CityLife")
		local ping = Players.LocalPlayer:GetNetworkPing() * 1000
		readout.Text = string.format(
			"FPS %d  (peor %.1f ms)\nPING %d ms\nMEMORIA %d MB\nAUTOS %d · AÉREOS %d · PERSONAS %d\nINSTANCIAS %d",
			math.round(frames / elapsed),
			worst * 1000,
			math.round(ping),
			math.round(Stats:GetTotalMemoryUsageMb()),
			if life then life:GetAttribute("Cars") or 0 else 0,
			if life then life:GetAttribute("Flying") or 0 else 0,
			if life then life:GetAttribute("People") or 0 else 0,
			Stats.InstanceCount
		)
		frames, elapsed, worst = 0, 0, 0
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.F3 and not UserInputService:GetFocusedTextBox() then
			screen.Enabled = not screen.Enabled
		end
	end)
end

return PerfOverlay
