--!strict
-- Item models built from parts, so the system ships without uploaded assets.
-- The same model is used for inventory icons (ViewportFrame) and world pickups.
-- To use real meshes instead, return a clone from ReplicatedStorage in `Build`.

type PartSpec = {
	Shape: Enum.PartType?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	Transparency: number?,
	Reflectance: number?,
}

local METAL = Color3.fromRGB(196, 202, 210)
local DARK_METAL = Color3.fromRGB(70, 74, 82)
local GOLD = Color3.fromRGB(232, 182, 72)
local WOOD = Color3.fromRGB(110, 72, 44)
local LEATHER = Color3.fromRGB(140, 92, 56)

local function deg(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local function sword(bladeColor: Color3, bladeMaterial: Enum.Material, guardColor: Color3): { PartSpec }
	return {
		{
			Size = Vector3.new(0.5, 3, 0.12),
			CFrame = CFrame.new(0, 1.6, 0),
			Color = bladeColor,
			Material = bladeMaterial,
		},
		{
			Size = Vector3.new(0.36, 0.36, 0.12),
			CFrame = CFrame.new(0, 3.1, 0) * deg(0, 0, 45),
			Color = bladeColor,
			Material = bladeMaterial,
		},
		{
			Size = Vector3.new(1.5, 0.22, 0.3),
			CFrame = CFrame.new(0, 0.05, 0),
			Color = guardColor,
			Material = Enum.Material.Metal,
		},
		{
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.9, 0.24, 0.24),
			CFrame = CFrame.new(0, -0.5, 0) * deg(0, 0, 90),
			Color = WOOD,
			Material = Enum.Material.Wood,
		},
		{
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.36, 0.36, 0.36),
			CFrame = CFrame.new(0, -1.02, 0),
			Color = guardColor,
			Material = Enum.Material.Metal,
		},
	}
end

local specs: { [string]: { PartSpec } } = {
	Sword = sword(METAL, Enum.Material.Metal, DARK_METAL),
	EmberSword = sword(Color3.fromRGB(255, 112, 46), Enum.Material.Neon, Color3.fromRGB(58, 34, 30)),
	Cap = {
		{
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.9, 1.9, 1.9),
			CFrame = CFrame.new(0, 0, 0),
			Color = LEATHER,
			Material = Enum.Material.Fabric,
		},
		{
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.18, 2.3, 2.3),
			CFrame = CFrame.new(0, -0.12, 0) * deg(0, 0, 90),
			Color = Color3.fromRGB(116, 74, 44),
			Material = Enum.Material.Fabric,
		},
	},
	Helm = {
		{
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.3, 1.8, 1.8),
			CFrame = CFrame.new(0, 0, 0) * deg(0, 0, 90),
			Color = METAL,
			Material = Enum.Material.Metal,
		},
		{
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.8, 1.8, 1.8),
			CFrame = CFrame.new(0, 0.62, 0),
			Color = METAL,
			Material = Enum.Material.Metal,
		},
		{
			Size = Vector3.new(1.2, 0.16, 0.2),
			CFrame = CFrame.new(0, 0.1, -0.86),
			Color = DARK_METAL,
			Material = Enum.Material.Metal,
		},
		{
			Size = Vector3.new(0.16, 0.9, 0.16),
			CFrame = CFrame.new(0, -0.3, -0.88),
			Color = DARK_METAL,
			Material = Enum.Material.Metal,
		},
		{
			Size = Vector3.new(0.18, 0.5, 1.4),
			CFrame = CFrame.new(0, 1.55, 0.1),
			Color = Color3.fromRGB(176, 42, 52),
			Material = Enum.Material.Fabric,
		},
	},
	Armor = {
		{
			Size = Vector3.new(2, 2.2, 1),
			CFrame = CFrame.new(0, 0, 0),
			Color = Color3.fromRGB(150, 158, 168),
			Material = Enum.Material.DiamondPlate,
		},
		{
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(-1.05, 0.85, 0),
			Color = METAL,
			Material = Enum.Material.Metal,
		},
		{
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(1.05, 0.85, 0),
			Color = METAL,
			Material = Enum.Material.Metal,
		},
		{
			Size = Vector3.new(2.06, 0.26, 1.06),
			CFrame = CFrame.new(0, -0.7, 0),
			Color = LEATHER,
			Material = Enum.Material.Leather,
		},
		{
			Size = Vector3.new(0.4, 0.3, 0.1),
			CFrame = CFrame.new(0, -0.7, -0.55),
			Color = GOLD,
			Material = Enum.Material.Metal,
		},
	},
	Amulet = {
		{
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, 1.5, 1.5),
			CFrame = deg(0, 90, 0),
			Color = GOLD,
			Material = Enum.Material.Metal,
		},
		{
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.95, 0.95, 0.95),
			CFrame = CFrame.new(0, 0, -0.12),
			Color = Color3.fromRGB(46, 196, 126),
			Material = Enum.Material.Glass,
			Reflectance = 0.2,
		},
		{
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, 0.5, 0.5),
			CFrame = CFrame.new(0, 0.9, 0) * deg(0, 90, 0),
			Color = GOLD,
			Material = Enum.Material.Metal,
		},
	},
	Potion = {
		{
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.6, 1.6, 1.6),
			CFrame = CFrame.new(0, 0, 0),
			Color = Color3.fromRGB(220, 236, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.55,
		},
		{
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.3, 1.3, 1.3),
			CFrame = CFrame.new(0, -0.08, 0),
			Color = Color3.fromRGB(232, 44, 76),
			Material = Enum.Material.Neon,
		},
		{
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 0.5, 0.5),
			CFrame = CFrame.new(0, 0.95, 0) * deg(0, 0, 90),
			Color = Color3.fromRGB(220, 236, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.4,
		},
		{
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 0.42, 0.42),
			CFrame = CFrame.new(0, 1.35, 0) * deg(0, 0, 90),
			Color = Color3.fromRGB(150, 110, 70),
			Material = Enum.Material.Wood,
		},
	},
	Ore = {
		{
			Size = Vector3.new(1.4, 1.1, 1.2),
			CFrame = deg(12, 20, 8),
			Color = Color3.fromRGB(96, 92, 90),
			Material = Enum.Material.Slate,
		},
		{
			Size = Vector3.new(0.9, 0.8, 0.9),
			CFrame = CFrame.new(0.6, 0.45, 0.2) * deg(-18, 40, 25),
			Color = Color3.fromRGB(110, 104, 100),
			Material = Enum.Material.Slate,
		},
		{
			Size = Vector3.new(0.35, 0.35, 0.35),
			CFrame = CFrame.new(-0.35, 0.45, -0.5) * deg(30, 30, 0),
			Color = Color3.fromRGB(214, 140, 86),
			Material = Enum.Material.Metal,
		},
		{
			Size = Vector3.new(0.3, 0.3, 0.3),
			CFrame = CFrame.new(0.4, -0.1, -0.62) * deg(10, 60, 20),
			Color = Color3.fromRGB(214, 140, 86),
			Material = Enum.Material.Metal,
		},
	},
	Crystal = {
		{
			Size = Vector3.new(0.6, 2.2, 0.6),
			CFrame = deg(0, 45, 0),
			Color = Color3.fromRGB(112, 226, 255),
			Material = Enum.Material.Neon,
			Transparency = 0.15,
		},
		{
			Size = Vector3.new(0.45, 1.4, 0.45),
			CFrame = CFrame.new(-0.45, -0.35, 0.1) * deg(0, 45, 24),
			Color = Color3.fromRGB(150, 236, 255),
			Material = Enum.Material.Neon,
			Transparency = 0.15,
		},
		{
			Size = Vector3.new(0.4, 1.1, 0.4),
			CFrame = CFrame.new(0.42, -0.45, -0.1) * deg(0, 45, -28),
			Color = Color3.fromRGB(92, 206, 245),
			Material = Enum.Material.Neon,
			Transparency = 0.15,
		},
	},
}

local ItemModels = {}

-- Returns a new, anchored, non-colliding model centered on its pivot.
function ItemModels.Build(name: string): Model
	local spec = specs[name]
	assert(spec, `ItemModels: no model named "{name}"`)
	local model = Instance.new("Model")
	model.Name = name
	local root: BasePart? = nil
	for index, partSpec in spec do
		local part = Instance.new("Part")
		part.Name = if index == 1 then "Root" else `Part{index}`
		part.Shape = partSpec.Shape or Enum.PartType.Block
		part.Size = partSpec.Size
		part.CFrame = partSpec.CFrame
		part.Color = partSpec.Color
		part.Material = partSpec.Material or Enum.Material.SmoothPlastic
		part.Transparency = partSpec.Transparency or 0
		part.Reflectance = partSpec.Reflectance or 0
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		root = root or part
	end
	model.PrimaryPart = root
	-- Pivot at the visual center so rotating icons and pickups spin in place.
	local boxCFrame = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(boxCFrame.Position)
	return model
end

function ItemModels.Has(name: string): boolean
	return specs[name] ~= nil
end

return ItemModels
