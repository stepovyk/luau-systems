--!strict
-- Server entry point: wires the systems together and starts them.

local PlayerData = require(script.Parent.PlayerData)
local InventoryService = require(script.Parent.Inventory.InventoryService)
local ItemPickups = require(script.Parent.Inventory.ItemPickups)

-- What a brand-new player starts with.
local STARTER_ITEMS = {
	{ "iron_sword", 1 },
	{ "leather_cap", 1 },
	{ "health_potion", 3 },
}

local template: { [string]: any } = { StarterItemsGiven = false }
for key, value in InventoryService.Template() do
	template[key] = value
end

InventoryService.Start()
ItemPickups.Start()

PlayerData.OnEachProfile(function(profile)
	if profile.Data.StarterItemsGiven then
		return
	end
	profile.Data.StarterItemsGiven = true
	for _, entry in STARTER_ITEMS do
		InventoryService.Give(profile.Player, entry[1], entry[2])
	end
end)

PlayerData.Start({
	StoreName = "PlayerData",
	Template = template,
})
