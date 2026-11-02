local Core = require("../src/shared/Inventory/InventoryCore")
local Catalog = require("../src/shared/Inventory/ItemCatalog")

local getDef = Catalog.Get
local slots = Catalog.EquipSlots

local function fresh(capacity: number?)
	return Core.new(capacity or 6)
end

local function at(inv, key)
	local stack = inv.Slots[key]
	return if stack then `{stack.Id}:{stack.Count}` else "empty"
end

return function(t)
	local test, eq = t.test, t.eq

	test("add fills existing stacks before opening new ones", function()
		local inv = fresh()
		eq(Core.add(inv, getDef, "iron_ore", 30), 30)
		eq(Core.add(inv, getDef, "iron_ore", 30), 30)
		eq(at(inv, "1"), "iron_ore:50")
		eq(at(inv, "2"), "iron_ore:10")
	end)

	test("add stops at capacity and reports the real amount", function()
		local inv = fresh(2)
		eq(Core.add(inv, getDef, "health_potion", 25), 20)
		eq(Core.count(inv, "health_potion"), 20)
		eq(Core.spaceFor(inv, getDef, "health_potion"), 0)
	end)

	test("add rejects unknown items and bad counts", function()
		local inv = fresh()
		eq(Core.add(inv, getDef, "nope", 1), 0)
		eq(Core.add(inv, getDef, "iron_ore", 0), 0)
		eq(Core.add(inv, getDef, "iron_ore", 1.5), 0)
		eq(Core.add(inv, getDef, "iron_ore", 0 / 0), 0)
		eq(next(inv.Slots), nil)
	end)

	test("remove is all or nothing and drains from the back", function()
		local inv = fresh()
		Core.add(inv, getDef, "iron_ore", 60)
		eq(Core.remove(inv, "iron_ore", 61), false)
		eq(Core.count(inv, "iron_ore"), 60)
		eq(Core.remove(inv, "iron_ore", 15), true)
		eq(at(inv, "1"), "iron_ore:45")
		eq(at(inv, "2"), "empty")
	end)

	test("remove never takes equipped gear", function()
		local inv = fresh()
		Core.add(inv, getDef, "iron_sword", 1)
		assert(Core.move(inv, getDef, slots, "1", "Weapon"))
		eq(Core.remove(inv, "iron_sword", 1), false)
		eq(at(inv, "Weapon"), "iron_sword:1")
	end)

	test("move into empty slot, with and without split", function()
		local inv = fresh()
		Core.add(inv, getDef, "iron_ore", 20)
		assert(Core.move(inv, getDef, slots, "1", "3", 5))
		eq(at(inv, "1"), "iron_ore:15")
		eq(at(inv, "3"), "iron_ore:5")
		assert(Core.move(inv, getDef, slots, "1", "4"))
		eq(at(inv, "1"), "empty")
		eq(at(inv, "4"), "iron_ore:15")
	end)

	test("move merges onto a matching stack up to its limit", function()
		local inv = fresh()
		inv.Slots["1"] = { Id = "iron_ore", Count = 40 }
		inv.Slots["2"] = { Id = "iron_ore", Count = 30 }
		assert(Core.move(inv, getDef, slots, "2", "1"))
		eq(at(inv, "1"), "iron_ore:50")
		eq(at(inv, "2"), "iron_ore:20")
		local ok, err = Core.move(inv, getDef, slots, "2", "1")
		eq(ok, false)
		eq(err, "StackFull")
	end)

	test("move swaps different items, but never splits onto one", function()
		local inv = fresh()
		inv.Slots["1"] = { Id = "iron_ore", Count = 10 }
		inv.Slots["2"] = { Id = "health_potion", Count = 3 }
		local ok, err = Core.move(inv, getDef, slots, "1", "2", 4)
		eq(ok, false)
		eq(err, "CannotSplitOntoItem")
		assert(Core.move(inv, getDef, slots, "1", "2"))
		eq(at(inv, "1"), "health_potion:3")
		eq(at(inv, "2"), "iron_ore:10")
	end)

	test("equipment slots only accept matching gear", function()
		local inv = fresh()
		Core.add(inv, getDef, "iron_ore", 1)
		Core.add(inv, getDef, "leather_cap", 1)
		Core.add(inv, getDef, "knight_helm", 1)
		local ok, err = Core.move(inv, getDef, slots, "1", "Head")
		eq(ok, false)
		eq(err, "WrongSlotType")
		eq(select(2, Core.move(inv, getDef, slots, "2", "Weapon")), "WrongSlotType")
		assert(Core.move(inv, getDef, slots, "2", "Head"))
		-- Swapping a helm in sends the cap back to the backpack slot it came from.
		assert(Core.move(inv, getDef, slots, "3", "Head"))
		eq(at(inv, "Head"), "knight_helm:1")
		eq(at(inv, "3"), "leather_cap:1")
	end)

	test("unequipping onto a non-matching item is refused", function()
		local inv = fresh()
		Core.add(inv, getDef, "leather_cap", 1)
		Core.add(inv, getDef, "iron_ore", 5)
		assert(Core.move(inv, getDef, slots, "1", "Head"))
		-- Ore cannot go into the Head slot, so this swap must fail.
		eq(select(2, Core.move(inv, getDef, slots, "Head", "2")), "WrongSlotType")
		eq(at(inv, "Head"), "leather_cap:1")
	end)

	test("move validates slots and amounts from untrusted input", function()
		local inv = fresh()
		Core.add(inv, getDef, "iron_ore", 5)
		eq(select(2, Core.move(inv, getDef, slots, "1", "7")), "BadSlot")
		eq(select(2, Core.move(inv, getDef, slots, "1", "0")), "BadSlot")
		eq(select(2, Core.move(inv, getDef, slots, "1", "01")), "BadSlot")
		eq(select(2, Core.move(inv, getDef, slots, 1, "2")), "BadSlot")
		eq(select(2, Core.move(inv, getDef, slots, "1", "Capacity")), "BadSlot")
		eq(select(2, Core.move(inv, getDef, slots, "1", "1")), "SameSlot")
		eq(select(2, Core.move(inv, getDef, slots, "2", "3")), "EmptySource")
		eq(select(2, Core.move(inv, getDef, slots, "1", "2", 6)), "BadAmount")
		eq(select(2, Core.move(inv, getDef, slots, "1", "2", 0)), "BadAmount")
		eq(select(2, Core.move(inv, getDef, slots, "1", "2", -1)), "BadAmount")
		eq(select(2, Core.move(inv, getDef, slots, "1", "2", 2.5)), "BadAmount")
		eq(select(2, Core.move(inv, getDef, slots, "1", "2", math.huge)), "BadAmount")
		eq(select(2, Core.move(inv, getDef, slots, "1", "2", "3")), "BadAmount")
		eq(at(inv, "1"), "iron_ore:5")
	end)

	test("takeFrom returns exactly what was taken", function()
		local inv = fresh()
		Core.add(inv, getDef, "health_potion", 4)
		local taken = Core.takeFrom(inv, "1", 3)
		eq(taken and taken.Count, 3)
		eq(at(inv, "1"), "health_potion:1")
		eq(Core.takeFrom(inv, "1", 2), nil)
		eq(Core.takeFrom(inv, "1") and true, true)
		eq(at(inv, "1"), "empty")
	end)

	test("sort merges stacks and orders by category, rarity, name", function()
		local inv = fresh(8)
		inv.Slots["1"] = { Id = "iron_ore", Count = 30 }
		inv.Slots["3"] = { Id = "health_potion", Count = 2 }
		inv.Slots["4"] = { Id = "iron_ore", Count = 30 }
		inv.Slots["6"] = { Id = "iron_sword", Count = 1 }
		inv.Slots["7"] = { Id = "ember_blade", Count = 1 }
		inv.Slots["8"] = { Id = "crystal_shard", Count = 3 }
		Core.sort(inv, getDef, Catalog.CategoryOrder, Catalog.RarityOrder)
		eq(at(inv, "1"), "ember_blade:1")
		eq(at(inv, "2"), "iron_sword:1")
		eq(at(inv, "3"), "health_potion:2")
		eq(at(inv, "4"), "crystal_shard:3")
		eq(at(inv, "5"), "iron_ore:50")
		eq(at(inv, "6"), "iron_ore:10")
		eq(at(inv, "7"), "empty")
	end)

	test("sanitize repairs old or tampered saves", function()
		local raw = {
			Capacity = 4,
			Slots = {
				["1"] = { Id = "iron_ore", Count = 70 }, -- over the stack limit
				["2"] = { Id = "removed_item", Count = 1 }, -- no longer in the catalog
				["3"] = { Id = "health_potion", Count = -2 }, -- broken count
				Head = { Id = "iron_sword", Count = 1 }, -- wrong equipment slot
				Weapon = { Id = "ember_blade", Count = 1 },
				["9"] = { Id = "crystal_shard", Count = 2 }, -- outside capacity
			},
		}
		local inv, lost = Core.sanitize(raw, getDef, slots, 4)
		eq(at(inv, "Weapon"), "ember_blade:1")
		eq(at(inv, "Head"), "empty")
		eq(at(inv, "1"), "iron_ore:50")
		eq(Core.count(inv, "iron_ore"), 70)
		eq(Core.count(inv, "iron_sword"), 1)
		eq(Core.count(inv, "crystal_shard"), 2)
		eq(Core.count(inv, "removed_item"), 0)
		eq(#lost, 0)
	end)

	test("sanitize reports items that no longer fit", function()
		local raw = { Capacity = 3, Slots = {} }
		for i = 1, 3 do
			raw.Slots[tostring(i)] = { Id = "iron_sword", Count = 1 }
		end
		local inv, lost = Core.sanitize(raw, getDef, slots, 2)
		eq(Core.count(inv, "iron_sword"), 2)
		eq(#lost, 1)
		eq(lost[1].Count, 1)
	end)

	test("sanitize survives garbage", function()
		for _, raw in { nil, 5, "x", {}, { Slots = 3 }, { Slots = { [1] = true, a = { Id = 4 } } } } do
			local inv = Core.sanitize(raw, getDef, slots, 4)
			eq(next(inv.Slots), nil)
		end
	end)

	test("stats sum equipped gear only", function()
		local inv = fresh()
		Core.add(inv, getDef, "jade_amulet", 1)
		Core.add(inv, getDef, "chain_mail", 1)
		Core.add(inv, getDef, "ember_blade", 1)
		assert(Core.move(inv, getDef, slots, "1", "Trinket"))
		assert(Core.move(inv, getDef, slots, "2", "Body"))
		local stats = Core.stats(inv, getDef, slots)
		eq(stats.Attack, 4)
		eq(stats.Defense, 10)
		eq(stats.MaxHealth, 60)
	end)
end
