--!strict
-- Every item the game knows about. Add an entry here and it can be granted, stacked,
-- equipped, used and saved without touching any other code.

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"
export type Category = "Weapon" | "Armor" | "Trinket" | "Consumable" | "Material"
export type EquipSlot = "Weapon" | "Head" | "Body" | "Trinket"
export type Stats = { Attack: number?, Defense: number?, MaxHealth: number? }

export type ItemDef = {
	Id: string,
	Name: string,
	Description: string,
	Category: Category,
	Rarity: Rarity,
	MaxStack: number,
	EquipSlot: EquipSlot?,
	Stats: Stats?,
	-- Consumables: health restored when used.
	Heal: number?,
	-- Name of the model in ItemModels used for the icon and world pickup.
	Model: string,
}

local RARITY_ORDER: { [Rarity]: number } = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
}

local RARITY_COLORS: { [Rarity]: Color3 } = {
	Common = Color3.fromRGB(168, 176, 189),
	Uncommon = Color3.fromRGB(88, 196, 120),
	Rare = Color3.fromRGB(77, 152, 255),
	Epic = Color3.fromRGB(177, 106, 255),
	Legendary = Color3.fromRGB(255, 166, 61),
}

local CATEGORY_ORDER: { [Category]: number } = {
	Weapon = 1,
	Armor = 2,
	Trinket = 3,
	Consumable = 4,
	Material = 5,
}

local EQUIP_SLOTS: { EquipSlot } = { "Weapon", "Head", "Body", "Trinket" }

local items: { ItemDef } = {
	{
		Id = "iron_sword",
		Name = "Iron Sword",
		Description = "Reliable blade forged from plain iron.",
		Category = "Weapon",
		Rarity = "Common",
		MaxStack = 1,
		EquipSlot = "Weapon",
		Stats = { Attack = 8 },
		Model = "Sword",
	},
	{
		Id = "ember_blade",
		Name = "Ember Blade",
		Description = "Still warm from the forge it was born in.",
		Category = "Weapon",
		Rarity = "Epic",
		MaxStack = 1,
		EquipSlot = "Weapon",
		Stats = { Attack = 15, MaxHealth = 10 },
		Model = "EmberSword",
	},
	{
		Id = "leather_cap",
		Name = "Leather Cap",
		Description = "Better than nothing. Barely.",
		Category = "Armor",
		Rarity = "Common",
		MaxStack = 1,
		EquipSlot = "Head",
		Stats = { Defense = 2 },
		Model = "Cap",
	},
	{
		Id = "knight_helm",
		Name = "Knight Helm",
		Description = "Heavy steel that has turned many blows.",
		Category = "Armor",
		Rarity = "Rare",
		MaxStack = 1,
		EquipSlot = "Head",
		Stats = { Defense = 5, MaxHealth = 15 },
		Model = "Helm",
	},
	{
		Id = "chain_mail",
		Name = "Chain Mail",
		Description = "Thousands of linked rings, one solid wall.",
		Category = "Armor",
		Rarity = "Uncommon",
		MaxStack = 1,
		EquipSlot = "Body",
		Stats = { Defense = 6, MaxHealth = 20 },
		Model = "Armor",
	},
	{
		Id = "jade_amulet",
		Name = "Jade Amulet",
		Description = "Hums quietly when danger is near.",
		Category = "Trinket",
		Rarity = "Legendary",
		MaxStack = 1,
		EquipSlot = "Trinket",
		Stats = { Attack = 4, Defense = 4, MaxHealth = 40 },
		Model = "Amulet",
	},
	{
		Id = "health_potion",
		Name = "Health Potion",
		Description = "Restores 35 health.",
		Category = "Consumable",
		Rarity = "Uncommon",
		MaxStack = 10,
		Heal = 35,
		Model = "Potion",
	},
	{
		Id = "iron_ore",
		Name = "Iron Ore",
		Description = "Raw ore, ready for the smelter.",
		Category = "Material",
		Rarity = "Common",
		MaxStack = 50,
		Model = "Ore",
	},
	{
		Id = "crystal_shard",
		Name = "Crystal Shard",
		Description = "A splinter of pure light.",
		Category = "Material",
		Rarity = "Rare",
		MaxStack = 25,
		Model = "Crystal",
	},
}

local byId: { [string]: ItemDef } = {}
for _, def in items do
	assert(byId[def.Id] == nil, `ItemCatalog: duplicate item id "{def.Id}"`)
	assert(def.MaxStack >= 1 and def.MaxStack % 1 == 0, `ItemCatalog: bad MaxStack on "{def.Id}"`)
	assert(def.EquipSlot == nil or def.MaxStack == 1, `ItemCatalog: equippable "{def.Id}" must have MaxStack 1`)
	byId[def.Id] = table.freeze(def)
end

local ItemCatalog = {
	Items = table.freeze(items),
	RarityOrder = table.freeze(RARITY_ORDER),
	RarityColors = table.freeze(RARITY_COLORS),
	CategoryOrder = table.freeze(CATEGORY_ORDER),
	EquipSlots = table.freeze(EQUIP_SLOTS),
}

function ItemCatalog.Get(id: string): ItemDef?
	return byId[id]
end

return table.freeze(ItemCatalog)
