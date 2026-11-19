--!strict

-- Small shared builders for the HUD components (text, frames, gradients,
-- tweens), so every module looks the same and no module carries its own
-- copy of these helpers.

local TweenService = game:GetService("TweenService")

local HUDConfig = require(script.Parent.HUDConfig)

local UIKit = {}

function UIKit.frame(parent: Instance, name: string, position: Vector2, size: Vector2, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Position = UDim2.fromOffset(position.X, position.Y)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.ZIndex = zIndex
	frame.Parent = parent
	return frame
end

function UIKit.box(parent: Instance, name: string, position: Vector2, size: Vector2, color: Color3, transparency: number, zIndex: number): Frame
	local frame = UIKit.frame(parent, name, position, size, zIndex)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	return frame
end

function UIKit.text(parent: Instance, name: string, value: string, position: Vector2, size: Vector2, font: Enum.Font, textSize: number, color: Color3, zIndex: number, alignX: Enum.TextXAlignment?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(position.X, position.Y)
	label.Size = UDim2.fromOffset(size.X, size.Y)
	label.Font = font
	label.Text = value
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextXAlignment = alignX or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = zIndex
	label.Parent = parent
	return label
end

-- Soft dark outline behind HUD text so it reads over bright scenery.
function UIKit.shadow(label: TextLabel, transparency: number?)
	label.TextStrokeColor3 = HUDConfig.Palette.Carbon
	label.TextStrokeTransparency = transparency or 0.55
end

function UIKit.gradient(parent: Instance, from: Color3, to: Color3, rotation: number, transparency: NumberSequence?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(from, to)
	gradient.Rotation = rotation
	if transparency then
		gradient.Transparency = transparency
	end
	gradient.Parent = parent
	return gradient
end

function UIKit.tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?, delay: number?): Tween
	local tween = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out, 0, false, delay or 0), goal)
	tween:Play()
	return tween
end

-- A module root: anchored to a screen corner, `margin` design pixels in,
-- scaled by the HUD's UIScale (passed in so every module shares it).
function UIKit.anchored(parent: Instance, name: string, anchor: Vector2, size: Vector2, offset: Vector2, zIndex: number): Frame
	local root = Instance.new("Frame")
	root.Name = name
	root.BackgroundTransparency = 1
	root.AnchorPoint = anchor
	root.Position = UDim2.new(anchor.X, offset.X, anchor.Y, offset.Y)
	root.Size = UDim2.fromOffset(size.X, size.Y)
	root.ZIndex = zIndex
	root.Parent = parent
	return root
end

return UIKit
