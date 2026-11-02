--!strict
-- Server side of the inventory: owns each player's inventory inside their saved profile,
-- validates every client request, applies equipment stats and keeps the client in sync.
-- The client only ever asks; it never decides.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Systems = ReplicatedStorage:WaitForChild("Systems")
local InventoryCore = require(Systems.Inventory.InventoryCore)
local ItemCatalog = require(Systems.Inventory.ItemCatalog)
local RateLimiter = require(Systems.Util.RateLimiter)
local Signal = require(Systems.Util.Signal)
local PlayerData = require(script.Parent.Parent.PlayerData)

local CAPACITY = 24
local BASE_MAX_HEALTH = 100

type InventoryData = InventoryCore.InventoryData

export type ActionResult = "Ok" | string

local InventoryService = {}

-- Fires with (player, inventory) after every change, for quests, UI hooks, analytics.
InventoryService.Changed = Signal.new() :: Signal.Signal<Player, InventoryData>

local getDef = ItemCatalog.Get :: InventoryCore.GetDef
local equipSlots = ItemCatalog.EquipSlots :: { string }
local limiter = RateLimiter.new(12, 20)

local remotes: Folder
local syncEvent: RemoteEvent
local requestFunction: RemoteFunction

-- Optional hook for the Drop action; set by whatever spawns world items.
local dropHandler: ((player: Player, stack: InventoryCore.Stack) -> boolean)? = nil

local function inventoryOf(player: Player): InventoryData?
	local profile = PlayerData.Get(player)
	return if profile then profile.Data.Inventory else nil
end

local function applyStats(player: Player, inventory: InventoryData)
	local stats = InventoryCore.stats(inventory, getDef, equipSlots)
	player:SetAttribute("Attack", stats.Attack or 0)
	player:SetAttribute("Defense", stats.Defense or 0)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		local newMax = BASE_MAX_HEALTH + (stats.MaxHealth or 0)
		local ratio = humanoid.Health / humanoid.MaxHealth
		humanoid.MaxHealth = newMax
		humanoid.Health = math.clamp(newMax * ratio, 1, newMax)
	end
end

local function changed(player: Player, inventory: InventoryData)
	applyStats(player, inventory)
	syncEvent:FireClient(player, inventory)
	InventoryService.Changed:Fire(player, inventory)
end

local function isSlotKey(value: any): boolean
	return type(value) == "string" and #value <= 16
end

local function isOptionalAmount(value: any): boolean
	return value == nil or (type(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value <= 1e6)
end

type Handler = (player: Player, inventory: InventoryData, a: any, b: any, c: any) -> ActionResult

local handlers: { [string]: Handler } = {
	Move = function(_player, inventory, from, to, amount)
		if not isSlotKey(from) or not isSlotKey(to) or not isOptionalAmount(amount) then
			return "BadRequest"
		end
		local ok, err = InventoryCore.move(inventory, getDef, equipSlots, from, to, amount)
		return if ok then "Ok" else err :: string
	end,

	-- Equips gear to its slot (swapping with what is there), or unequips into the backpack.
	QuickEquip = function(_player, inventory, slot)
		if not isSlotKey(slot) then
			return "BadRequest"
		end
		local stack = inventory.Slots[slot]
		if not stack then
			return "EmptySource"
		end
		local def = getDef(stack.Id)
		if not def or not def.EquipSlot then
			return "NotEquippable"
		end
		if slot == def.EquipSlot then
			local free = InventoryCore.firstEmpty(inventory)
			if not free then
				return "BackpackFull"
			end
			local ok, err = InventoryCore.move(inventory, getDef, equipSlots, slot, free)
			return if ok then "Ok" else err :: string
		end
		local ok, err = InventoryCore.move(inventory, getDef, equipSlots, slot, def.EquipSlot)
		return if ok then "Ok" else err :: string
	end,

	Use = function(player, inventory, slot)
		if not isSlotKey(slot) then
			return "BadRequest"
		end
		local stack = inventory.Slots[slot]
		local def = stack and getDef(stack.Id)
		if not def or not def.Heal then
			return "NotUsable"
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return "Dead"
		end
		if humanoid.Health >= humanoid.MaxHealth then
			return "FullHealth"
		end
		InventoryCore.takeFrom(inventory, slot, 1)
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + def.Heal)
		return "Ok"
	end,

	Drop = function(player, inventory, slot, amount)
		if not isSlotKey(slot) or not isOptionalAmount(amount) then
			return "BadRequest"
		end
		if not dropHandler then
			return "DropDisabled"
		end
		if not InventoryCore.isValidSlot(inventory, equipSlots, slot) or not inventory.Slots[slot] then
			return "EmptySource"
		end
		local stack = InventoryCore.takeFrom(inventory, slot, amount)
		if not stack then
			return "BadAmount"
		end
		if not dropHandler(player, stack) then
			-- Could not place it in the world: put it straight back.
			InventoryCore.add(inventory, getDef, stack.Id, stack.Count)
			return "DropFailed"
		end
		return "Ok"
	end,

	Sort = function(_player, inventory)
		InventoryCore.sort(inventory, getDef, ItemCatalog.CategoryOrder, ItemCatalog.RarityOrder)
		return "Ok"
	end,
}

local function onRequest(player: Player, action: any, a: any, b: any, c: any): ActionResult
	if not limiter:Allow(player) then
		return "TooFast"
	end
	if type(action) ~= "string" then
		return "BadRequest"
	end
	if action == "Fetch" then
		-- The client asks once on start, in case it missed the first Sync.
		return inventoryOf(player) :: any
	end
	local handler = handlers[action]
	if not handler then
		return "BadRequest"
	end
	local inventory = inventoryOf(player)
	if not inventory then
		return "NotLoaded"
	end
	local result = handler(player, inventory, a, b, c)
	if result == "Ok" then
		changed(player, inventory)
	end
	return result
end

-- Adds items to a player's backpack. Returns how many fit.
function InventoryService.Give(player: Player, id: string, count: number): number
	local inventory = inventoryOf(player)
	if not inventory then
		return 0
	end
	local added = InventoryCore.add(inventory, getDef, id, count)
	if added > 0 then
		changed(player, inventory)
	end
	return added
end

-- Removes exactly `count` from the backpack, or nothing. Use for crafting costs, quests, trades.
function InventoryService.Take(player: Player, id: string, count: number): boolean
	local inventory = inventoryOf(player)
	if not inventory then
		return false
	end
	local ok = InventoryCore.remove(inventory, id, count)
	if ok then
		changed(player, inventory)
	end
	return ok
end

function InventoryService.Count(player: Player, id: string): number
	local inventory = inventoryOf(player)
	return if inventory then InventoryCore.count(inventory, id) else 0
end

function InventoryService.SpaceFor(player: Player, id: string): number
	local inventory = inventoryOf(player)
	return if inventory then InventoryCore.spaceFor(inventory, getDef, id) else 0
end

function InventoryService.GetEquipped(player: Player, slot: string): string?
	local inventory = inventoryOf(player)
	local stack = inventory and inventory.Slots[slot]
	return if stack then stack.Id else nil
end

function InventoryService.SetDropHandler(handler: (player: Player, stack: InventoryCore.Stack) -> boolean)
	dropHandler = handler
end

-- Template piece for PlayerData: merge into the profile template.
function InventoryService.Template(): { [string]: any }
	return { Inventory = InventoryCore.new(CAPACITY) }
end

function InventoryService.Start()
	remotes = Instance.new("Folder")
	remotes.Name = "InventoryRemotes"
	syncEvent = Instance.new("RemoteEvent")
	syncEvent.Name = "Sync"
	syncEvent.Parent = remotes
	requestFunction = Instance.new("RemoteFunction")
	requestFunction.Name = "Request"
	requestFunction.Parent = remotes
	remotes.Parent = ReplicatedStorage

	requestFunction.OnServerInvoke = onRequest

	PlayerData.OnEachProfile(function(profile)
		local player = profile.Player
		local inventory, lost = InventoryCore.sanitize(profile.Data.Inventory, getDef, equipSlots, CAPACITY)
		profile.Data.Inventory = inventory
		for _, stack in lost do
			warn(`[Inventory] {player.UserId} lost {stack.Count}x {stack.Id} while repairing saved data`)
		end

		local characterConnection = player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid")
			applyStats(player, inventory)
		end)
		profile.OnRelease:Once(function()
			characterConnection:Disconnect()
		end)
		changed(player, inventory)
	end)

	Players.PlayerRemoving:Connect(function(player)
		limiter:Forget(player)
	end)
end

return InventoryService
