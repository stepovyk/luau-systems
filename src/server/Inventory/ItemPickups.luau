--!strict
-- Items lying in the world. Two sources:
--   * Spawners: any BasePart tagged "ItemSpawner" with attributes ItemId (string),
--     Count (number, default 1) and RespawnSeconds (number, default 30).
--   * Drops: created by the inventory Drop action, despawn after DROP_LIFETIME.
-- Players collect with a ProximityPrompt; if their backpack fills up, the rest stays behind.
-- Models stay still on the server; each client animates them locally (no replication cost).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Systems = ReplicatedStorage:WaitForChild("Systems")
local ItemCatalog = require(Systems.Inventory.ItemCatalog)
local ItemModels = require(Systems.Inventory.ItemModels)
local InventoryService = require(script.Parent.InventoryService)

local SPAWNER_TAG = "ItemSpawner"
local DROP_LIFETIME = 120
local DROP_DISTANCE = 4
local PICKUP_RANGE = 10
local HOVER_HEIGHT = 2.2

local container = Instance.new("Folder")
container.Name = "ItemPickups"

local ItemPickups = {}

type Pickup = {
	Model: Model,
	ItemId: string,
	Count: number,
	OnEmpty: () -> (),
}

local function label(def: ItemCatalog.ItemDef, count: number): string
	return if count > 1 then `{def.Name} x{count}` else def.Name
end

local function spawnPickup(position: Vector3, itemId: string, count: number, onEmpty: () -> ()): Pickup?
	local def = ItemCatalog.Get(itemId)
	if not def or not ItemModels.Has(def.Model) then
		warn(`[ItemPickups] Unknown item "{itemId}"`)
		return nil
	end
	local model = ItemModels.Build(def.Model)
	model.Name = `Pickup_{itemId}`
	-- Scale big items down so every pickup reads as roughly the same size in the world.
	local _, size = model:GetBoundingBox()
	model:ScaleTo(math.min(1, 2.2 / math.max(size.X, size.Y, size.Z)))
	model:PivotTo(CFrame.new(position + Vector3.new(0, HOVER_HEIGHT, 0)))

	local root = model.PrimaryPart :: BasePart
	local light = Instance.new("PointLight")
	light.Color = ItemCatalog.RarityColors[def.Rarity]
	light.Range = 8
	light.Brightness = 1.4
	light.Parent = root

	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = label(def, count)
	prompt.MaxActivationDistance = PICKUP_RANGE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = attachment

	local pickup: Pickup = { Model = model, ItemId = itemId, Count = count, OnEmpty = onEmpty }

	prompt.Triggered:Connect(function(player)
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart or (rootPart.Position - root.Position).Magnitude > PICKUP_RANGE + 2 then
			return
		end
		local added = InventoryService.Give(player, pickup.ItemId, pickup.Count)
		if added == 0 then
			return
		end
		pickup.Count -= added
		if pickup.Count <= 0 then
			model:Destroy()
			pickup.OnEmpty()
		else
			prompt.ObjectText = label(def, pickup.Count)
		end
	end)

	model.Parent = container
	return pickup
end

local function watchSpawner(part: BasePart)
	if not part:IsA("BasePart") then
		return
	end
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true

	local function respawn()
		if not part.Parent then
			return
		end
		local itemId = part:GetAttribute("ItemId")
		local count = part:GetAttribute("Count")
		if type(itemId) ~= "string" then
			warn(`[ItemPickups] Spawner {part:GetFullName()} has no ItemId attribute`)
			return
		end
		spawnPickup(part.Position, itemId, if type(count) == "number" then math.max(1, math.floor(count)) else 1, function()
			local delaySeconds = part:GetAttribute("RespawnSeconds")
			task.delay(if type(delaySeconds) == "number" then delaySeconds else 30, respawn)
		end)
	end
	respawn()
end

local function onDrop(player: Player, stack: { Id: string, Count: number }): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return false
	end
	local origin = rootPart.Position + rootPart.CFrame.LookVector * DROP_DISTANCE
	-- Land on whatever is below, ignoring characters.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { container }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(origin + Vector3.new(0, 3, 0), Vector3.new(0, -50, 0), params)
	local position = if hit then hit.Position else rootPart.Position - Vector3.new(0, 3, 0)

	local pickup = spawnPickup(position, stack.Id, stack.Count, function() end)
	if not pickup then
		return false
	end
	task.delay(DROP_LIFETIME, function()
		if pickup.Model.Parent then
			pickup.Model:Destroy()
		end
	end)
	return true
end

function ItemPickups.Start()
	container.Parent = Workspace
	InventoryService.SetDropHandler(onDrop)
	for _, part in CollectionService:GetTagged(SPAWNER_TAG) do
		task.spawn(watchSpawner, part)
	end
	CollectionService:GetInstanceAddedSignal(SPAWNER_TAG):Connect(watchSpawner)
end

return ItemPickups
