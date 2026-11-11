--!strict

-- Client side of the carried weapons (WeaponService): the two-slot panel
-- (bottom right), 1 / 2 or the mouse wheel to switch, and the pickup prompts'
-- text (AGARRAR with a free slot, INTERCAMBIAR when full). Roblox's own
-- backpack bar is hidden while it is enabled.

local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local RemoteNames = require(root.Network.RemoteNames)
local WeaponConfig = require(root.Config.WeaponConfig)

local WeaponController = {}
WeaponController.__index = WeaponController

local SLOT_ACTION = "Reality2059WeaponSlot"
local WHEEL_ACTION = "Reality2059WeaponWheel"
local TEXT = Color3.fromRGB(236, 240, 255)
local MUTED = Color3.fromRGB(130, 140, 165)
local ACCENT = Color3.fromRGB(0, 220, 255)

function WeaponController.new(playerGui: PlayerGui)
	local screen = Instance.new("ScreenGui")
	screen.Name = "WeaponSlots"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 81
	screen.Enabled = false
	screen.Parent = playerGui
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -24, 1, -24)
	holder.Size = UDim2.fromOffset(240, WeaponConfig.MaxSlots * 46)
	holder.BackgroundTransparency = 1
	holder.Parent = screen
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = holder
	local slots = {}
	for index = 1, WeaponConfig.MaxSlots do
		local slot = Instance.new("Frame")
		slot.LayoutOrder = index
		slot.Size = UDim2.new(1, 0, 0, 40)
		slot.BackgroundColor3 = Color3.fromRGB(10, 12, 22)
		slot.BackgroundTransparency = 0.25
		slot.BorderSizePixel = 0
		slot.Parent = holder
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, 6)
		round.Parent = slot
		local outline = Instance.new("UIStroke")
		outline.Color = ACCENT
		outline.Transparency = 0.7
		outline.Parent = slot
		local key = Instance.new("TextLabel")
		key.Size = UDim2.fromOffset(32, 40)
		key.BackgroundTransparency = 1
		key.Font = Enum.Font.SciFi
		key.Text = tostring(index)
		key.TextSize = 20
		key.TextColor3 = ACCENT
		key.Parent = slot
		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromOffset(36, 0)
		name.Size = UDim2.new(1, -44, 1, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.SciFi
		name.Text = "VACÍO"
		name.TextSize = 15
		name.TextColor3 = MUTED
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Parent = slot
		slots[index] = { outline = outline, name = name }
	end
	local self = setmetatable({
		_screen = screen,
		_slots = slots,
		_enabled = false,
		_loadout = { slots = {}, equipped = 1, max = WeaponConfig.MaxSlots },
		_connections = {} :: { RBXScriptConnection },
		_equipRemote = nil :: RemoteEvent?,
		_backpackWasEnabled = nil :: boolean?,
	}, WeaponController)
	task.spawn(function()
		local remotes = root:WaitForChild("Runtime"):WaitForChild(RemoteNames.Folder)
		local loadoutRemote = remotes:WaitForChild(RemoteNames.WeaponLoadout)
		self._equipRemote = remotes:WaitForChild(RemoteNames.WeaponEquip) :: RemoteEvent
		if loadoutRemote:IsA("RemoteEvent") then
			loadoutRemote.OnClientEvent:Connect(function(loadout)
				self._loadout = loadout
				self:_render()
			end)
		end
	end)
	return self
end

function WeaponController:_render()
	local loadout = self._loadout
	for index, slot in self._slots do
		local name = loadout.slots[index]
		local equipped = name ~= nil and index == loadout.equipped
		slot.name.Text = name or "VACÍO"
		slot.name.TextColor3 = if equipped then TEXT elseif name then MUTED else Color3.fromRGB(80, 86, 104)
		slot.outline.Transparency = if equipped then 0 else 0.7
	end
end

function WeaponController:_select(slot: number)
	if slot >= 1 and slot <= #self._loadout.slots and self._equipRemote then
		self._equipRemote:FireServer(slot)
	end
end

function WeaponController:Enable()
	if self._enabled then
		return
	end
	self._enabled = true
	self._screen.Enabled = true
	pcall(function()
		self._backpackWasEnabled = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	ContextActionService:BindAction(SLOT_ACTION, function(_, state, input)
		if state == Enum.UserInputState.Begin then
			self:_select(if input.KeyCode == Enum.KeyCode.Two then 2 else 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.One, Enum.KeyCode.Two)
	ContextActionService:BindAction(WHEEL_ACTION, function(_, state, input)
		if state == Enum.UserInputState.Change and #self._loadout.slots > 1 then
			local count = #self._loadout.slots
			local step = if input.Position.Z > 0 then -1 else 1
			self:_select((self._loadout.equipped - 1 + step) % count + 1)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseWheel)
	-- The prompt says what E will do for this player.
	table.insert(self._connections, ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt:GetAttribute("WeaponId") then
			prompt.ActionText = if #self._loadout.slots >= (self._loadout.max or WeaponConfig.MaxSlots) then "INTERCAMBIAR" else "AGARRAR"
		end
	end))
	self:_render()
end

function WeaponController:Disable()
	if not self._enabled then
		return
	end
	self._enabled = false
	self._screen.Enabled = false
	ContextActionService:UnbindAction(SLOT_ACTION)
	ContextActionService:UnbindAction(WHEEL_ACTION)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	if self._backpackWasEnabled ~= nil then
		local wasEnabled = self._backpackWasEnabled
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, wasEnabled)
		end)
		self._backpackWasEnabled = nil
	end
end

function WeaponController:Destroy()
	self:Disable()
	self._screen:Destroy()
end

return WeaponController
