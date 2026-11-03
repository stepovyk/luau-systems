--!strict
-- Shop Kit server. Drop the ShopKit folder into ServerScriptService; this script does the rest:
-- moves the client part to ReplicatedStorage, tracks pass ownership and handles every
-- developer product purchase exactly once.

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local kit = script.Parent
local Config = require(kit.Config)
local Rewards = require(kit.Rewards)

local OWNERSHIP_ATTEMPTS = 4
local STORE_ATTEMPTS = 4

---------------------------------------------------------------------------------------------
-- Validate the setup early, with messages a developer can act on.

local productsById: { [number]: Config.ProductEntry } = {}
local passesById: { [number]: Config.PassEntry } = {}

for _, pass in Config.Passes do
	assert(type(pass.Id) == "number" and pass.Id > 0, "[ShopKit] Every entry in Config.Passes needs a real pass Id")
	passesById[pass.Id] = pass
end
for _, product in Config.Products do
	assert(
		type(product.Id) == "number" and product.Id > 0,
		"[ShopKit] Every entry in Config.Products needs a real developer product Id"
	)
	assert(
		Rewards.Products[product.Reward] ~= nil,
		`[ShopKit] Product {product.Id} uses reward "{product.Reward}", which is missing from Rewards.Products`
	)
	productsById[product.Id] = product
end
if #Config.Passes == 0 and #Config.Products == 0 then
	warn("[ShopKit] The shop is empty. Add your pass and product Ids to ShopKit.Config.")
end

---------------------------------------------------------------------------------------------
-- Client part and remotes

local clientFolder = kit:WaitForChild("Client")
local configCopy = kit.Config:Clone()
configCopy.Parent = clientFolder
clientFolder.Name = "ShopKitClient"
clientFolder.Parent = ReplicatedStorage

local purchasedEvent = Instance.new("RemoteEvent")
purchasedEvent.Name = "Purchased"
purchasedEvent.Parent = clientFolder

---------------------------------------------------------------------------------------------
-- Game passes

local function ownershipAttribute(passId: number): string
	return `ShopKitPass_{passId}`
end

local function applyPass(player: Player, passId: number)
	if player:GetAttribute(ownershipAttribute(passId)) then
		return
	end
	player:SetAttribute(ownershipAttribute(passId), true)
	local perk = Rewards.OnPassOwned[passId]
	if perk then
		task.spawn(perk, player)
	end
end

local function checkPasses(player: Player)
	for passId in passesById do
		task.spawn(function()
			for attempt = 1, OWNERSHIP_ATTEMPTS do
				local ok, owns =
					pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
				if ok then
					if owns and player.Parent == Players then
						applyPass(player, passId)
					end
					return
				end
				task.wait(2 ^ attempt)
			end
			warn(`[ShopKit] Could not check pass {passId} for {player.UserId}`)
		end)
	end
end

Players.PlayerAdded:Connect(checkPasses)
for _, player in Players:GetPlayers() do
	checkPasses(player)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if purchased and passesById[passId] then
		applyPass(player, passId)
		purchasedEvent:FireClient(player, "Pass", passId)
	end
end)

---------------------------------------------------------------------------------------------
-- Developer products
--
-- Roblox may call ProcessReceipt more than once for the same purchase (server crash, retry,
-- another server). Each granted PurchaseId is written to a DataStore and checked first, so a
-- purchase is rewarded once and only once. Anything that fails returns NotProcessedYet, and
-- Roblox tries again later, so a player never pays without getting the reward.

local receipts: DataStore? = nil
do
	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, Config.ReceiptStore)
	if ok and RunService:IsStudio() then
		-- Unpublished places and places without API access fail on the first request.
		ok = pcall(store.GetAsync, store, "__probe")
	end
	if ok then
		receipts = store
	elseif RunService:IsStudio() then
		warn("[ShopKit] DataStores unavailable in Studio: test purchases are remembered for this session only.")
	else
		error("[ShopKit] DataStores unavailable; purchases cannot be processed safely.")
	end
end
-- Receipts granted on this server, also the only record in Studio without API access.
local sessionReceipts: { [string]: boolean } = {}
local inProgress: { [string]: boolean } = {}

local function withRetries<T>(attempts: number, fn: () -> T): (boolean, T?)
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt < attempts then
			task.wait(2 ^ (attempt - 1))
		end
	end
	return false, nil
end

local function alreadyGranted(purchaseId: string): boolean?
	if sessionReceipts[purchaseId] then
		return true
	end
	local store = receipts
	if not store then
		return false
	end
	local ok, record = withRetries(STORE_ATTEMPTS, function()
		return store:GetAsync(purchaseId)
	end)
	if not ok then
		return nil -- unknown: try again later rather than risk a double grant
	end
	return record ~= nil
end

local function rememberGrant(purchaseId: string, receipt: { [string]: any })
	sessionReceipts[purchaseId] = true
	local store = receipts
	if not store then
		return
	end
	local ok = withRetries(STORE_ATTEMPTS, function()
		store:SetAsync(purchaseId, {
			UserId = receipt.PlayerId,
			ProductId = receipt.ProductId,
			Spent = receipt.CurrencySpent,
			Time = os.time(),
		}, { receipt.PlayerId })
	end)
	if not ok then
		warn(`[ShopKit] Granted {purchaseId} but could not record it; this server still remembers it`)
	end
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local purchaseId = tostring(receipt.PurchaseId)
	local product = productsById[receipt.ProductId]
	if not product then
		warn(`[ShopKit] Receipt for product {receipt.ProductId}, which is not in Config.Products`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- The same receipt can arrive twice at once; handle one copy at a time.
	if inProgress[purchaseId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	inProgress[purchaseId] = true

	local decision = Enum.ProductPurchaseDecision.NotProcessedYet
	local granted = alreadyGranted(purchaseId)
	if granted == true then
		decision = Enum.ProductPurchaseDecision.PurchaseGranted
	elseif granted == false then
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if player then
			local ok, result = pcall(Rewards.Products[product.Reward], player, product.Amount)
			if ok and result == true then
				rememberGrant(purchaseId, receipt)
				purchasedEvent:FireClient(player, "Product", receipt.ProductId)
				decision = Enum.ProductPurchaseDecision.PurchaseGranted
			elseif not ok then
				warn(`[ShopKit] Reward "{product.Reward}" failed for {receipt.PlayerId}: {result}`)
			end
		end
		-- Player already left: Roblox retries when they are back in any server.
	end

	inProgress[purchaseId] = nil
	return decision
end

MarketplaceService.ProcessReceipt = processReceipt
