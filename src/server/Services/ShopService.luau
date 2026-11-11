--!strict

-- TIENDA: credit packs bought with Robux (Developer Products, ShopConfig).
-- Roblox calls ProcessReceipt on the server; credits are granted only once
-- per receipt (PlayerDataService.GrantCredits) and only while the buyer's
-- profile is loaded here, otherwise Roblox retries the receipt later. The
-- new balance is pushed to the buyer (CurrencyChanged).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local ShopConfig = require(root.Config.ShopConfig)
local RemoteNames = require(root.Network.RemoteNames)

local ShopService = {}
ShopService.__index = ShopService

-- dataService: PlayerDataService (HasSession / GrantCredits).
function ShopService.new(runtime: Folder, dataService: any)
	local remotes = runtime:WaitForChild(RemoteNames.Folder)
	local changed = remotes:FindFirstChild(RemoteNames.CurrencyChanged)
	if not changed then
		changed = Instance.new("RemoteEvent")
		changed.Name = RemoteNames.CurrencyChanged
		changed.Parent = remotes
	end
	local packs = {}
	for _, pack in ShopConfig.CreditPacks do
		if pack.productId > 0 then
			packs[pack.productId] = pack
		end
	end
	return setmetatable({
		_data = dataService,
		_changed = changed :: RemoteEvent,
		_packs = packs,
	}, ShopService)
end

function ShopService:ProcessReceipt(receipt): Enum.ProductPurchaseDecision
	local pack = self._packs[receipt.ProductId]
	if not pack then
		warn("[REALITY 2059] Recibo de un producto desconocido: " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not self._data:HasSession(receipt.PlayerId) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, errorCode, balance = self._data:GrantCredits(receipt.PlayerId, pack.credits, tostring(receipt.PurchaseId), ShopConfig.ReceiptHistory)
	if not ok then
		warn("[REALITY 2059] No se pudieron acreditar los créditos: " .. tostring(errorCode))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player then
		self._changed:FireClient(player, balance, pack.credits)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ShopService:Start()
	MarketplaceService.ProcessReceipt = function(receipt)
		local ok, decision = pcall(function()
			return self:ProcessReceipt(receipt)
		end)
		if not ok then
			warn("[REALITY 2059] Error al procesar la compra: " .. tostring(decision))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return decision
	end
end

return ShopService
