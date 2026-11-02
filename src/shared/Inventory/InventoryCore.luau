--!strict
-- Pure inventory rules: no Roblox services, no networking. The server runs every change
-- through these functions, and the same code can run anywhere Luau runs (tests included).
--
-- Data layout is DataStore-friendly: slot keys are strings, so there are no array holes.
--   Backpack slots: "1" .. tostring(Capacity)
--   Equipment slots: "Weapon", "Head", "Body", "Trinket" (whatever the catalog defines)

export type Stack = { Id: string, Count: number }
export type InventoryData = { Capacity: number, Slots: { [string]: Stack } }

-- Only the fields the rules need, so any catalog shape with these fields works.
export type Def = {
	Id: string,
	MaxStack: number,
	EquipSlot: string?,
	Category: string,
	Rarity: string,
	Name: string,
	Stats: { [string]: number? }?,
}
export type GetDef = (id: string) -> Def?

export type MoveError =
	"SameSlot"
	| "EmptySource"
	| "BadSlot"
	| "BadAmount"
	| "WrongSlotType"
	| "StackFull"
	| "CannotSplitOntoItem"

local InventoryCore = {}

local function isInteger(n: any): boolean
	return type(n) == "number" and n == n and n % 1 == 0 and n > -math.huge and n < math.huge
end

function InventoryCore.new(capacity: number): InventoryData
	assert(isInteger(capacity) and capacity >= 1, "InventoryCore.new: capacity must be a positive integer")
	return { Capacity = capacity, Slots = {} }
end

function InventoryCore.isBackpackSlot(data: InventoryData, key: any): boolean
	if type(key) ~= "string" then
		return false
	end
	local index = tonumber(key)
	return index ~= nil and isInteger(index) and index >= 1 and index <= data.Capacity and tostring(index) == key
end

function InventoryCore.isValidSlot(data: InventoryData, equipSlots: { string }, key: any): boolean
	return InventoryCore.isBackpackSlot(data, key) or (type(key) == "string" and table.find(equipSlots, key) ~= nil)
end

-- Can an item of this kind sit in this slot? Backpack slots take anything.
function InventoryCore.canPlace(data: InventoryData, def: Def, key: string): boolean
	if InventoryCore.isBackpackSlot(data, key) then
		return true
	end
	return def.EquipSlot == key
end

function InventoryCore.firstEmpty(data: InventoryData): string?
	for i = 1, data.Capacity do
		local key = tostring(i)
		if data.Slots[key] == nil then
			return key
		end
	end
	return nil
end

-- Total of an item across backpack and equipment.
function InventoryCore.count(data: InventoryData, id: string): number
	local total = 0
	for _, stack in data.Slots do
		if stack.Id == id then
			total += stack.Count
		end
	end
	return total
end

-- How many more of this item the backpack can take right now.
function InventoryCore.spaceFor(data: InventoryData, getDef: GetDef, id: string): number
	local def = getDef(id)
	if not def then
		return 0
	end
	local space = 0
	for i = 1, data.Capacity do
		local stack = data.Slots[tostring(i)]
		if stack == nil then
			space += def.MaxStack
		elseif stack.Id == id then
			space += math.max(0, def.MaxStack - stack.Count)
		end
	end
	return space
end

-- Adds up to `count`, topping up existing stacks before opening new ones.
-- Returns how many were actually added; the caller decides what to do with the rest.
function InventoryCore.add(data: InventoryData, getDef: GetDef, id: string, count: number): number
	local def = getDef(id)
	if not def or not isInteger(count) or count <= 0 then
		return 0
	end
	local remaining = count
	for i = 1, data.Capacity do
		if remaining == 0 then
			break
		end
		local stack = data.Slots[tostring(i)]
		if stack and stack.Id == id and stack.Count < def.MaxStack then
			local put = math.min(remaining, def.MaxStack - stack.Count)
			stack.Count += put
			remaining -= put
		end
	end
	for i = 1, data.Capacity do
		if remaining == 0 then
			break
		end
		local key = tostring(i)
		if data.Slots[key] == nil then
			local put = math.min(remaining, def.MaxStack)
			data.Slots[key] = { Id = id, Count = put }
			remaining -= put
		end
	end
	return count - remaining
end

-- Removes exactly `count` from the backpack, or nothing at all if there is not enough.
-- Equipped items are never taken implicitly.
function InventoryCore.remove(data: InventoryData, id: string, count: number): boolean
	if not isInteger(count) or count <= 0 then
		return false
	end
	local available = 0
	for i = 1, data.Capacity do
		local stack = data.Slots[tostring(i)]
		if stack and stack.Id == id then
			available += stack.Count
		end
	end
	if available < count then
		return false
	end
	local remaining = count
	-- Drain from the last slots first so the front of the backpack stays stable.
	for i = data.Capacity, 1, -1 do
		if remaining == 0 then
			break
		end
		local key = tostring(i)
		local stack = data.Slots[key]
		if stack and stack.Id == id then
			local take = math.min(remaining, stack.Count)
			stack.Count -= take
			remaining -= take
			if stack.Count == 0 then
				data.Slots[key] = nil
			end
		end
	end
	return true
end

-- Takes `amount` (default: whole stack) out of one slot and returns what was taken.
function InventoryCore.takeFrom(data: InventoryData, key: string, amount: number?): Stack?
	local stack = data.Slots[key]
	if not stack then
		return nil
	end
	local take = amount or stack.Count
	if not isInteger(take) or take < 1 or take > stack.Count then
		return nil
	end
	stack.Count -= take
	if stack.Count == 0 then
		data.Slots[key] = nil
	end
	return { Id = stack.Id, Count = take }
end

-- Moves `amount` (default: whole stack) from one slot to another: into an empty slot,
-- onto a matching stack, or as a swap with a different item.
function InventoryCore.move(
	data: InventoryData,
	getDef: GetDef,
	equipSlots: { string },
	from: any,
	to: any,
	amount: any?
): (boolean, MoveError?)
	if not InventoryCore.isValidSlot(data, equipSlots, from) or not InventoryCore.isValidSlot(data, equipSlots, to) then
		return false, "BadSlot"
	end
	if from == to then
		return false, "SameSlot"
	end
	local source = data.Slots[from]
	if not source then
		return false, "EmptySource"
	end
	local amt = if amount == nil then source.Count else amount
	if not isInteger(amt) or amt < 1 or amt > source.Count then
		return false, "BadAmount"
	end
	local sourceDef = getDef(source.Id)
	if not sourceDef then
		return false, "BadSlot"
	end
	if not InventoryCore.canPlace(data, sourceDef, to) then
		return false, "WrongSlotType"
	end

	local target = data.Slots[to]
	if target == nil then
		data.Slots[to] = { Id = source.Id, Count = amt }
		source.Count -= amt
		if source.Count == 0 then
			data.Slots[from] = nil
		end
		return true
	end

	if target.Id == source.Id then
		local put = math.min(amt, sourceDef.MaxStack - target.Count)
		if put <= 0 then
			return false, "StackFull"
		end
		target.Count += put
		source.Count -= put
		if source.Count == 0 then
			data.Slots[from] = nil
		end
		return true
	end

	-- Different items: only a whole stack can trade places.
	if amt ~= source.Count then
		return false, "CannotSplitOntoItem"
	end
	local targetDef = getDef(target.Id)
	if not targetDef or not InventoryCore.canPlace(data, targetDef, from) then
		return false, "WrongSlotType"
	end
	data.Slots[from], data.Slots[to] = target, source
	return true
end

-- Merges partial stacks and orders the backpack by category, rarity (best first) and name.
-- Equipment is left untouched.
function InventoryCore.sort(
	data: InventoryData,
	getDef: GetDef,
	categoryOrder: { [string]: number },
	rarityOrder: { [string]: number }
)
	local totals: { [string]: number } = {}
	local order: { string } = {}
	for i = 1, data.Capacity do
		local key = tostring(i)
		local stack = data.Slots[key]
		if stack then
			if totals[stack.Id] == nil then
				totals[stack.Id] = 0
				table.insert(order, stack.Id)
			end
			totals[stack.Id] += stack.Count
			data.Slots[key] = nil
		end
	end
	table.sort(order, function(a, b)
		local da, db = getDef(a) :: Def, getDef(b) :: Def
		local ca, cb = categoryOrder[da.Category] or math.huge, categoryOrder[db.Category] or math.huge
		if ca ~= cb then
			return ca < cb
		end
		local ra, rb = rarityOrder[da.Rarity] or 0, rarityOrder[db.Rarity] or 0
		if ra ~= rb then
			return ra > rb
		end
		if da.Name ~= db.Name then
			return da.Name < db.Name
		end
		return a < b
	end)
	-- Every item was already in the backpack, so it all fits back after merging.
	for _, id in order do
		InventoryCore.add(data, getDef, id, totals[id])
	end
end

-- Repairs saved data against the current catalog: drops removed items, fixes broken counts,
-- moves misplaced gear back to the backpack and adapts to a changed capacity.
-- Returns stacks that no longer fit anywhere so the caller can log or compensate them.
function InventoryCore.sanitize(
	raw: any,
	getDef: GetDef,
	equipSlots: { string },
	capacity: number
): (InventoryData, { Stack })
	local data = InventoryCore.new(capacity)
	local lost: { Stack } = {}
	if type(raw) ~= "table" or type(raw.Slots) ~= "table" then
		return data, lost
	end

	local pending: { Stack } = {}
	-- Equipment first, then backpack in slot order, so a re-fit keeps the original layout.
	local keys: { string } = {}
	for key in raw.Slots do
		if type(key) == "string" then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b)
		local na, nb = tonumber(a), tonumber(b)
		if (na == nil) ~= (nb == nil) then
			return na == nil
		end
		if na and nb then
			return na < nb
		end
		return a < b
	end)

	for _, key in keys do
		local stack = raw.Slots[key]
		if type(stack) ~= "table" or type(stack.Id) ~= "string" then
			continue
		end
		local def = getDef(stack.Id)
		local count = stack.Count
		if not def or not isInteger(count) or count < 1 then
			continue
		end
		local valid = InventoryCore.isValidSlot(data, equipSlots, key) and InventoryCore.canPlace(data, def, key)
		if valid and data.Slots[key] == nil then
			local keep = math.min(count, def.MaxStack)
			data.Slots[key] = { Id = def.Id, Count = keep }
			count -= keep
		end
		if count > 0 then
			table.insert(pending, { Id = def.Id, Count = count })
		end
	end

	for _, stack in pending do
		local added = InventoryCore.add(data, getDef, stack.Id, stack.Count)
		if added < stack.Count then
			table.insert(lost, { Id = stack.Id, Count = stack.Count - added })
		end
	end
	return data, lost
end

-- Sum of stats from everything currently equipped.
function InventoryCore.stats(data: InventoryData, getDef: GetDef, equipSlots: { string }): { [string]: number }
	local totals: { [string]: number } = {}
	for _, slot in equipSlots do
		local stack = data.Slots[slot]
		local def = stack and getDef(stack.Id)
		if def and def.Stats then
			for stat, value in def.Stats do
				totals[stat] = (totals[stat] or 0) + (value or 0)
			end
		end
	end
	return totals
end

return InventoryCore
