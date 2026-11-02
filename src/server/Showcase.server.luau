--!strict
-- Showcase place: a small plaza with an item spawner on every pedestal.
-- Real games place "ItemSpawner"-tagged parts in their own map and delete this script.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local ItemCatalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Systems").Inventory.ItemCatalog)

local SPAWNS: { { id: string, count: number } } = {
	{ id = "ember_blade", count = 1 },
	{ id = "knight_helm", count = 1 },
	{ id = "chain_mail", count = 1 },
	{ id = "jade_amulet", count = 1 },
	{ id = "health_potion", count = 2 },
	{ id = "iron_ore", count = 12 },
	{ id = "crystal_shard", count = 4 },
	{ id = "iron_sword", count = 1 },
}

local RADIUS = 26

local map = Instance.new("Model")
map.Name = "Showcase"

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = map
	return p
end

part({
	Name = "Ground",
	Size = Vector3.new(400, 2, 400),
	Position = Vector3.new(0, -1, 0),
	Color = Color3.fromRGB(78, 112, 74),
	Material = Enum.Material.Grass,
})
part({
	Name = "Plaza",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(1, RADIUS * 2 + 14, RADIUS * 2 + 14),
	CFrame = CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
	Color = Color3.fromRGB(176, 168, 152),
	Material = Enum.Material.Cobblestone,
})

local spawn = Instance.new("SpawnLocation")
spawn.Name = "Spawn"
spawn.Anchored = true
spawn.Size = Vector3.new(8, 1, 8)
spawn.Position = Vector3.new(0, 1, 0)
spawn.Color = Color3.fromRGB(120, 112, 100)
spawn.Material = Enum.Material.Slate
spawn.Duration = 0
spawn.Parent = map

for index, entry in SPAWNS do
	local def = ItemCatalog.Get(entry.id)
	assert(def, `Showcase: unknown item {entry.id}`)
	local angle = (index - 1) / #SPAWNS * math.pi * 2
	local position = Vector3.new(math.cos(angle) * RADIUS, 0, math.sin(angle) * RADIUS)
	local facing = CFrame.lookAt(position, Vector3.zero)

	part({
		Name = `Pedestal_{def.Id}`,
		Size = Vector3.new(4, 2.4, 4),
		CFrame = facing + Vector3.new(0, 1.2, 0),
		Color = Color3.fromRGB(92, 96, 108),
		Material = Enum.Material.Slate,
	})
	part({
		Name = `Trim_{def.Id}`,
		Size = Vector3.new(4.2, 0.24, 4.2),
		CFrame = facing + Vector3.new(0, 2.42, 0),
		Color = ItemCatalog.RarityColors[def.Rarity],
		Material = Enum.Material.SmoothPlastic,
	})

	local spawner = part({
		Name = `Spawner_{def.Id}`,
		Size = Vector3.new(1, 1, 1),
		Position = position + Vector3.new(0, 2.6, 0),
		Transparency = 1,
		CanCollide = false,
	})
	spawner:SetAttribute("ItemId", def.Id)
	spawner:SetAttribute("Count", entry.count)
	spawner:SetAttribute("RespawnSeconds", 20)
	CollectionService:AddTag(spawner, "ItemSpawner")
end

map.Parent = Workspace

Lighting.ClockTime = 16.5
Lighting.Brightness = 2.2
Lighting.OutdoorAmbient = Color3.fromRGB(128, 132, 146)
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.6
