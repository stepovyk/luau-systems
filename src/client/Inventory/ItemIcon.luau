--!strict
-- Renders an item model into a ViewportFrame, framed to fill it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Systems = ReplicatedStorage:WaitForChild("Systems")
local ItemCatalog = require(Systems.Inventory.ItemCatalog)
local ItemModels = require(Systems.Inventory.ItemModels)

local FOV = 30
local VIEW_ANGLE = CFrame.Angles(math.rad(-18), math.rad(-32), 0)

local ItemIcon = {}

-- Clears the viewport and, if `itemId` is given, shows that item in it.
function ItemIcon.Set(viewport: ViewportFrame, itemId: string?)
	if viewport:GetAttribute("ItemId") == itemId then
		return
	end
	viewport:SetAttribute("ItemId", itemId)
	viewport:ClearAllChildren()
	if not itemId then
		return
	end
	local def = ItemCatalog.Get(itemId)
	if not def then
		return
	end

	local model = ItemModels.Build(def.Model)
	-- Tilt long items diagonally so they use the square icon well.
	if def.Category == "Weapon" then
		model:PivotTo(model:GetPivot() * CFrame.Angles(0, 0, math.rad(-40)))
	end
	model.Parent = viewport

	local boxCFrame, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local distance = radius / math.tan(math.rad(FOV / 2)) * 1.02
	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	local center = boxCFrame.Position
	camera.CFrame = CFrame.new(center) * VIEW_ANGLE * CFrame.new(0, 0, distance)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

return ItemIcon
