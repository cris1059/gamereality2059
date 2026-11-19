--!strict

-- Client side of the carried weapons (WeaponService): the two loadout slots
-- (shown by the HUD's weapon module), 1 / 2 or the mouse wheel to switch, and the pickup prompts'
-- text (AGARRAR with a free slot, INTERCAMBIAR when full). Roblox's own
-- backpack bar is hidden while it is enabled.

local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local RemoteNames = require(root.Network.RemoteNames)
local WeaponConfig = require(root.Config.WeaponConfig)
local CombatHUD = require(script.Parent.Parent.HUD.CombatHUD)

local WeaponController = {}
WeaponController.__index = WeaponController

local SLOT_ACTION = "Reality2059WeaponSlot"
local WHEEL_ACTION = "Reality2059WeaponWheel"

function WeaponController.new(playerGui: PlayerGui)
	-- The slots are drawn by the HUD's weapon module (HUD/CombatHUD); this
	-- ScreenGui is kept empty so Enable / Disable stay as they were.
	local screen = Instance.new("ScreenGui")
	screen.Name = "WeaponSlots"
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.Parent = playerGui
	local self = setmetatable({
		_screen = screen,
		_hud = CombatHUD.get(),
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
	self._hud:SetSlots(loadout.slots, loadout.equipped, loadout.max or WeaponConfig.MaxSlots)
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
	-- The prompt says what F will do for this player.
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
