--!strict
-- Inventory window. Shows what the server sends and turns input into requests;
-- every change is decided by the server and comes back through Sync.
--
-- Mouse / touch: drag to move, Shift+drag (or a long press on touch) to split half a stack,
-- drop outside the window to throw items on the ground, double-click to equip or use.
-- Keyboard: B toggles the window, Esc closes it.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Systems = ReplicatedStorage:WaitForChild("Systems")
local ItemCatalog = require(Systems.Inventory.ItemCatalog)
local InventoryCore = require(Systems.Inventory.InventoryCore)
local ItemIcon = require(script.ItemIcon)

local remotes = ReplicatedStorage:WaitForChild("InventoryRemotes")
local syncEvent = remotes:WaitForChild("Sync") :: RemoteEvent
local requestFunction = remotes:WaitForChild("Request") :: RemoteFunction

local player = Players.LocalPlayer

type InventoryData = InventoryCore.InventoryData

---------------------------------------------------------------------------------------------
-- Look

local THEME = {
	Panel = Color3.fromRGB(17, 19, 25),
	Surface = Color3.fromRGB(28, 31, 40),
	SurfaceHover = Color3.fromRGB(38, 42, 54),
	Stroke = Color3.fromRGB(52, 57, 72),
	Text = Color3.fromRGB(236, 239, 245),
	Muted = Color3.fromRGB(142, 149, 166),
	Accent = Color3.fromRGB(255, 196, 92),
	Danger = Color3.fromRGB(255, 104, 104),
}
local FONT = Font.fromEnum(Enum.Font.BuilderSans)
local FONT_BOLD = Font.new(FONT.Family, Enum.FontWeight.Bold)
local FONT_SEMI = Font.new(FONT.Family, Enum.FontWeight.SemiBold)

local SLOT = 68
local GAP = 8
local COLUMNS = 6
local PADDING = 20
local EQUIP_COLUMN = 220

local ERROR_TEXT: { [string]: string } = {
	StackFull = "That stack is full",
	WrongSlotType = "That item doesn't go there",
	CannotSplitOntoItem = "Split onto an empty slot",
	BackpackFull = "Your backpack is full",
	FullHealth = "You're already at full health",
	NotUsable = "This item can't be used",
	NotEquippable = "This item can't be equipped",
	Dead = "You can't do that right now",
	TooFast = "Slow down a little",
	NotLoaded = "Your inventory is still loading",
	DropFailed = "Can't drop that here",
}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function text(props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextColor3 = THEME.Text
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(label :: any)[key] = value
	end
	return label
end

local function tween(instance: Instance, seconds: number, goal: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal):Play()
end

local function newViewport(parent: Instance, size: UDim2, position: UDim2): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Size = size
	viewport.Position = position
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Ambient = Color3.fromRGB(150, 150, 160)
	viewport.LightColor = Color3.fromRGB(255, 248, 235)
	viewport.LightDirection = Vector3.new(-1, -2, -1.5)
	viewport.Parent = parent
	return viewport
end

---------------------------------------------------------------------------------------------
-- Layout

local rows = 4 -- recalculated when the first Sync tells us the capacity
local gui = Instance.new("ScreenGui")
gui.Name = "Inventory"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 10

-- Toggle button, bottom left, sized for thumbs.
local toggleButton = Instance.new("TextButton")
toggleButton.Name = "Toggle"
toggleButton.AutoButtonColor = false
toggleButton.AnchorPoint = Vector2.new(0, 1)
toggleButton.Position = UDim2.new(0, 20, 1, -20)
toggleButton.Size = UDim2.fromOffset(150, 48)
toggleButton.BackgroundColor3 = THEME.Panel
toggleButton.BackgroundTransparency = 0.08
toggleButton.Text = ""
toggleButton.Parent = gui
corner(toggleButton, 14)
stroke(toggleButton, THEME.Stroke, 1)
text({
	Text = "Inventory",
	FontFace = FONT_SEMI,
	TextSize = 18,
	Size = UDim2.new(1, -56, 1, 0),
	Position = UDim2.fromOffset(16, 0),
	Parent = toggleButton,
})
local keyHint = Instance.new("Frame")
keyHint.AnchorPoint = Vector2.new(1, 0.5)
keyHint.Position = UDim2.new(1, -12, 0.5, 0)
keyHint.Size = UDim2.fromOffset(28, 28)
keyHint.BackgroundColor3 = THEME.Surface
keyHint.Parent = toggleButton
corner(keyHint, 8)
text({
	Text = "B",
	FontFace = FONT_BOLD,
	TextSize = 15,
	TextColor3 = THEME.Muted,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1),
	Parent = keyHint,
})

local window = Instance.new("Frame")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.BackgroundColor3 = THEME.Panel
window.BackgroundTransparency = 0.04
window.Visible = false
window.Parent = gui
corner(window, 18)
stroke(window, THEME.Stroke, 1)
local windowScale = Instance.new("UIScale")
windowScale.Parent = window

local title = text({
	Text = "Inventory",
	FontFace = FONT_BOLD,
	TextSize = 24,
	Position = UDim2.fromOffset(PADDING, 16),
	Size = UDim2.fromOffset(200, 32),
	Parent = window,
})
local capacityLabel = text({
	Text = "",
	TextColor3 = THEME.Muted,
	TextSize = 16,
	Position = UDim2.fromOffset(PADDING + 112, 22),
	Size = UDim2.fromOffset(80, 24),
	Parent = window,
})
title.AutomaticSize = Enum.AutomaticSize.X
title:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	capacityLabel.Position = UDim2.fromOffset(PADDING + title.AbsoluteSize.X / windowScale.Scale + 10, 22)
end)

local function headerButton(label: string, width: number, rightOffset: number): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -rightOffset, 0, 16)
	button.Size = UDim2.fromOffset(width, 34)
	button.BackgroundColor3 = THEME.Surface
	button.FontFace = FONT_SEMI
	button.TextSize = 15
	button.TextColor3 = THEME.Text
	button.Text = label
	button.Parent = window
	corner(button, 10)
	button.MouseEnter:Connect(function()
		tween(button, 0.15, { BackgroundColor3 = THEME.SurfaceHover })
	end)
	button.MouseLeave:Connect(function()
		tween(button, 0.15, { BackgroundColor3 = THEME.Surface })
	end)
	return button
end

local closeButton = headerButton("", 34, PADDING)
-- Cross drawn from two bars, so it renders the same with any font.
for _, angle in { 45, -45 } do
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
	bar.Size = UDim2.fromOffset(14, 2)
	bar.Rotation = angle
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = THEME.Text
	bar.Parent = closeButton
	corner(bar, 1)
end
local sortButton = headerButton("Sort", 64, PADDING + 34 + 8)

-- Equipment column
local equipColumn = Instance.new("Frame")
equipColumn.BackgroundTransparency = 1
equipColumn.Position = UDim2.fromOffset(PADDING, 66)
equipColumn.Size = UDim2.fromOffset(EQUIP_COLUMN, 0)
equipColumn.Parent = window

-- Backpack grid
local grid = Instance.new("Frame")
grid.BackgroundTransparency = 1
grid.Position = UDim2.fromOffset(PADDING + EQUIP_COLUMN + 20, 66)
grid.Parent = window

local statusLabel = text({
	Text = "",
	TextColor3 = THEME.Danger,
	TextSize = 15,
	TextTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 1),
	Parent = window,
})

local hintLabel = text({
	Text = "Drag to move · Shift+drag to split · Double-click to equip or use · Drop outside to throw away",
	TextColor3 = THEME.Muted,
	TextSize = 13,
	TextWrapped = true,
	AnchorPoint = Vector2.new(0, 1),
	Parent = window,
})

---------------------------------------------------------------------------------------------
-- Slots

type SlotView = {
	Key: string,
	Button: TextButton,
	Viewport: ViewportFrame,
	Count: TextLabel,
	Stroke: UIStroke,
	Placeholder: TextLabel?,
}

local slotViews: { [string]: SlotView } = {}
local inventory: InventoryData? = nil

local function makeSlot(key: string, parent: Instance, position: UDim2, placeholder: string?): SlotView
	local button = Instance.new("TextButton")
	button.Name = `Slot_{key}`
	button.AutoButtonColor = false
	button.Text = ""
	button.Size = UDim2.fromOffset(SLOT, SLOT)
	button.Position = position
	button.BackgroundColor3 = THEME.Surface
	button.Parent = parent
	corner(button, 12)
	local slotStroke = stroke(button, THEME.Stroke, 1.5, 0.4)

	local viewport = newViewport(button, UDim2.fromOffset(SLOT - 10, SLOT - 10), UDim2.fromScale(0.5, 0.5))

	local count = text({
		Text = "",
		FontFace = FONT_BOLD,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -7, 1, -4),
		Size = UDim2.fromOffset(40, 18),
		ZIndex = 2,
		Parent = button,
	})
	local countStroke = Instance.new("UIStroke")
	countStroke.Thickness = 1.5
	countStroke.Transparency = 0.35
	countStroke.Parent = count

	local placeholderLabel: TextLabel? = nil
	if placeholder then
		placeholderLabel = text({
			Text = placeholder,
			TextColor3 = THEME.Muted,
			TextTransparency = 0.35,
			TextSize = 12,
			FontFace = FONT_SEMI,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = button,
		})
	end

	local view: SlotView = {
		Key = key,
		Button = button,
		Viewport = viewport,
		Count = count,
		Stroke = slotStroke,
		Placeholder = placeholderLabel,
	}
	slotViews[key] = view
	return view
end

-- Equipment slots with labels and the stat card under them.
local statLabels: { [string]: TextLabel } = {}
do
	for index, slotName in ItemCatalog.EquipSlots do
		local y = (index - 1) * (SLOT + GAP)
		makeSlot(slotName, equipColumn, UDim2.fromOffset(0, y))
		text({
			Text = slotName,
			FontFace = FONT_SEMI,
			TextColor3 = THEME.Muted,
			TextSize = 15,
			Position = UDim2.fromOffset(SLOT + 14, y + 12),
			Size = UDim2.fromOffset(EQUIP_COLUMN - SLOT - 14, 20),
			Parent = equipColumn,
		})
		text({
			Name = `Name_{slotName}`,
			Text = "Empty",
			TextColor3 = THEME.Muted,
			TextTransparency = 0.4,
			TextSize = 16,
			FontFace = FONT_SEMI,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(SLOT + 14, y + 34),
			Size = UDim2.fromOffset(EQUIP_COLUMN - SLOT - 14, 22),
			Parent = equipColumn,
		})
	end

	local statsTop = #ItemCatalog.EquipSlots * (SLOT + GAP) + 6
	local card = Instance.new("Frame")
	card.Name = "Stats"
	card.Position = UDim2.fromOffset(0, statsTop)
	card.Size = UDim2.fromOffset(EQUIP_COLUMN, 3 * 26 + 20)
	card.BackgroundColor3 = THEME.Surface
	card.Parent = equipColumn
	corner(card, 12)
	for index, stat in { { "Attack", "Attack" }, { "Defense", "Defense" }, { "MaxHealth", "Max health" } } do
		local y = 10 + (index - 1) * 26
		text({
			Text = stat[2],
			TextColor3 = THEME.Muted,
			TextSize = 16,
			Position = UDim2.fromOffset(14, y),
			Size = UDim2.fromOffset(120, 26),
			Parent = card,
		})
		statLabels[stat[1]] = text({
			Text = "0",
			FontFace = FONT_BOLD,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, y),
			Size = UDim2.fromOffset(80, 26),
			Parent = card,
		})
	end
end

local function layout(capacity: number)
	rows = math.ceil(capacity / COLUMNS)
	for i = 1, capacity do
		local key = tostring(i)
		if not slotViews[key] then
			local column = (i - 1) % COLUMNS
			local row = (i - 1) // COLUMNS
			makeSlot(key, grid, UDim2.fromOffset(column * (SLOT + GAP), row * (SLOT + GAP)))
		end
	end
	local gridWidth = COLUMNS * SLOT + (COLUMNS - 1) * GAP
	local gridHeight = rows * SLOT + (rows - 1) * GAP
	grid.Size = UDim2.fromOffset(gridWidth, gridHeight)
	local equipHeight = #ItemCatalog.EquipSlots * (SLOT + GAP) + 6 + 3 * 26 + 20
	local contentHeight = math.max(gridHeight, equipHeight)
	local width = PADDING * 2 + EQUIP_COLUMN + 20 + gridWidth
	local height = 66 + contentHeight + 56
	window.Size = UDim2.fromOffset(width, height)
	hintLabel.Position = UDim2.new(0, PADDING, 1, -14)
	hintLabel.Size = UDim2.new(1, -PADDING * 2 - 220, 0, 34)
	statusLabel.Position = UDim2.new(1, -PADDING, 1, -18)
	statusLabel.Size = UDim2.fromOffset(220, 20)
end

-- Keep the window inside small screens (phones) without touching its layout.
local function fitToScreen()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local size = window.Size
	local scale = math.min(1, (viewport.X - 24) / size.X.Offset, (viewport.Y - 24) / size.Y.Offset)
	windowScale.Scale = math.max(0.4, scale)
end

---------------------------------------------------------------------------------------------
-- Rendering

local function render()
	local data = inventory
	if not data then
		return
	end
	local used = 0
	for i = 1, data.Capacity do
		if data.Slots[tostring(i)] then
			used += 1
		end
	end
	capacityLabel.Text = `{used}/{data.Capacity}`

	for key, view in slotViews do
		local stack = data.Slots[key]
		local def = stack and ItemCatalog.Get(stack.Id)
		ItemIcon.Set(view.Viewport, if def then def.Id else nil)
		view.Count.Text = if stack and stack.Count > 1 then tostring(stack.Count) else ""
		if def then
			view.Stroke.Color = ItemCatalog.RarityColors[def.Rarity]
			view.Stroke.Transparency = 0.1
		else
			view.Stroke.Color = THEME.Stroke
			view.Stroke.Transparency = 0.4
		end
		if view.Placeholder then
			view.Placeholder.Visible = def == nil
		end
		local nameLabel = equipColumn:FindFirstChild(`Name_{key}`) :: TextLabel?
		if nameLabel then
			nameLabel.Text = if def then def.Name else "Empty"
			nameLabel.TextColor3 = if def then ItemCatalog.RarityColors[def.Rarity] else THEME.Muted
			nameLabel.TextTransparency = if def then 0 else 0.4
		end
	end

	local stats = InventoryCore.stats(data, ItemCatalog.Get :: any, ItemCatalog.EquipSlots :: any)
	for stat, label in statLabels do
		local value = stats[stat] or 0
		label.Text = if value > 0 then `+{value}` else "0"
		label.TextColor3 = if value > 0 then THEME.Accent else THEME.Muted
	end
end

local statusToken = 0
local function showStatus(message: string)
	statusToken += 1
	local token = statusToken
	statusLabel.Text = message
	tween(statusLabel, 0.15, { TextTransparency = 0 })
	task.delay(2.2, function()
		if token == statusToken then
			tween(statusLabel, 0.4, { TextTransparency = 1 })
		end
	end)
end

local function request(action: string, ...: any)
	local args = table.pack(...)
	task.spawn(function()
		local ok, result = pcall(requestFunction.InvokeServer, requestFunction, action, table.unpack(args, 1, args.n))
		if not ok then
			showStatus("Connection problem, try again")
		elseif result ~= "Ok" then
			local message = ERROR_TEXT[result]
			if message then
				showStatus(message)
			end
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Tooltip

local tooltip = Instance.new("Frame")
tooltip.Name = "Tooltip"
tooltip.Visible = false
tooltip.BackgroundColor3 = THEME.Panel
tooltip.Size = UDim2.fromOffset(250, 0)
tooltip.AutomaticSize = Enum.AutomaticSize.Y
tooltip.ZIndex = 50
tooltip.Parent = gui
corner(tooltip, 12)
local tooltipStroke = stroke(tooltip, THEME.Stroke, 1.5)
local tooltipPadding = Instance.new("UIPadding")
tooltipPadding.PaddingTop = UDim.new(0, 12)
tooltipPadding.PaddingBottom = UDim.new(0, 12)
tooltipPadding.PaddingLeft = UDim.new(0, 14)
tooltipPadding.PaddingRight = UDim.new(0, 14)
tooltipPadding.Parent = tooltip
local tooltipList = Instance.new("UIListLayout")
tooltipList.Padding = UDim.new(0, 4)
tooltipList.SortOrder = Enum.SortOrder.LayoutOrder
tooltipList.Parent = tooltip

local function tooltipLine(order: number, props: { [string]: any }): TextLabel
	local label = text(props)
	label.LayoutOrder = order
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.ZIndex = 51
	label.Parent = tooltip
	return label
end

local tooltipName = tooltipLine(1, { FontFace = FONT_BOLD, TextSize = 18 })
local tooltipKind = tooltipLine(2, { TextColor3 = THEME.Muted, TextSize = 14 })
local tooltipDescription = tooltipLine(3, { TextSize = 15 })
local tooltipStats = tooltipLine(4, { TextColor3 = THEME.Accent, TextSize = 15, FontFace = FONT_SEMI })
local tooltipHint = tooltipLine(5, { TextColor3 = THEME.Muted, TextSize = 13 })

local hoveredKey: string? = nil

local function updateTooltip()
	local data = inventory
	local stack = data and hoveredKey and data.Slots[hoveredKey]
	local def = stack and ItemCatalog.Get(stack.Id)
	if not def or not window.Visible then
		tooltip.Visible = false
		return
	end
	local rarityColor = ItemCatalog.RarityColors[def.Rarity]
	tooltipName.Text = def.Name
	tooltipName.TextColor3 = rarityColor
	tooltipStroke.Color = rarityColor
	tooltipKind.Text = `{def.Rarity} {string.lower(def.Category)}`
	tooltipDescription.Text = def.Description
	local statParts = {}
	if def.Stats then
		if def.Stats.Attack then
			table.insert(statParts, `+{def.Stats.Attack} Attack`)
		end
		if def.Stats.Defense then
			table.insert(statParts, `+{def.Stats.Defense} Defense`)
		end
		if def.Stats.MaxHealth then
			table.insert(statParts, `+{def.Stats.MaxHealth} Max health`)
		end
	end
	tooltipStats.Text = table.concat(statParts, "\n")
	tooltipStats.Visible = #statParts > 0
	tooltipHint.Text = if def.EquipSlot
		then (if hoveredKey == def.EquipSlot then "Double-click to unequip" else "Double-click to equip")
		elseif def.Heal then "Double-click to use"
		else `Stacks up to {def.MaxStack}`
	tooltip.Visible = true
end

local function placeTooltip()
	if not tooltip.Visible then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local screen = (Workspace.CurrentCamera :: Camera).ViewportSize
	local size = tooltip.AbsoluteSize
	local x = mouse.X + 18
	local y = mouse.Y + 18
	if x + size.X > screen.X - 8 then
		x = mouse.X - size.X - 18
	end
	if y + size.Y > screen.Y - 8 then
		y = screen.Y - size.Y - 8
	end
	tooltip.Position = UDim2.fromOffset(x, y)
end

---------------------------------------------------------------------------------------------
-- Drag and drop

local DRAG_THRESHOLD = 6
local DOUBLE_CLICK = 0.3
local LONG_PRESS = 0.45

local ghost = newViewport(gui, UDim2.fromOffset(SLOT, SLOT), UDim2.new())
ghost.Name = "DragGhost"
ghost.Visible = false
ghost.ZIndex = 40
ghost.ImageTransparency = 0.1

type Press = {
	Key: string,
	Input: InputObject,
	Start: Vector2,
	Started: number,
	Split: boolean,
	Dragging: boolean,
	-- Shift from InputObject.Position to this GUI's screen space (see beginPress).
	Offset: Vector2,
}
local press: Press? = nil
local lastClick: { Key: string, Time: number }? = nil

local function inside(position: Vector2, object: GuiObject): boolean
	local p, s = object.AbsolutePosition, object.AbsoluteSize
	return position.X >= p.X and position.X <= p.X + s.X and position.Y >= p.Y and position.Y <= p.Y + s.Y
end

local function slotAt(position: Vector2): string?
	for key, view in slotViews do
		local p, s = view.Button.AbsolutePosition, view.Button.AbsoluteSize
		if position.X >= p.X and position.X <= p.X + s.X and position.Y >= p.Y and position.Y <= p.Y + s.Y then
			return key
		end
	end
	return nil
end

local function insideWindow(position: Vector2): boolean
	return inside(position, window)
end

local function rawPosition(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function splitAmount(count: number): number
	return math.max(1, math.ceil(count / 2))
end

local function endDrag(releasePosition: Vector2)
	local current = press
	press = nil
	ghost.Visible = false
	local view = current and slotViews[current.Key]
	if view then
		tween(view.Viewport, 0.12, { ImageTransparency = 0 })
	end
	local data = inventory
	if not current or not data then
		return
	end
	local stack = data.Slots[current.Key]
	if not stack then
		return
	end

	if not current.Dragging then
		-- A click: check for a double-click on the same slot.
		local now = os.clock()
		if lastClick and lastClick.Key == current.Key and now - lastClick.Time <= DOUBLE_CLICK then
			lastClick = nil
			local def = ItemCatalog.Get(stack.Id)
			if def and def.EquipSlot then
				request("QuickEquip", current.Key)
			elseif def and def.Heal then
				request("Use", current.Key)
			end
		else
			lastClick = { Key = current.Key, Time = now }
		end
		return
	end

	local amount = if current.Split then splitAmount(stack.Count) else nil
	local target = slotAt(releasePosition)
	if target and target ~= current.Key then
		request("Move", current.Key, target, amount)
	elseif not target and not insideWindow(releasePosition) then
		request("Drop", current.Key, amount)
	end
end

local function beginPress(key: string, input: InputObject)
	local data = inventory
	if not data or not data.Slots[key] or press then
		return
	end
	local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	-- Whether input positions include the top bar inset differs between input types and
	-- Roblox versions. This press started inside the slot, so whichever reading lands
	-- inside it is the right one for the whole drag.
	local raw = rawPosition(input)
	local offset = if inside(raw, slotViews[key].Button) then Vector2.zero else GuiService:GetGuiInset()
	press = {
		Key = key,
		Input = input,
		Offset = offset,
		Start = raw + offset,
		Started = os.clock(),
		Split = shift,
		Dragging = false,
	}
end

local function updateDrag(position: Vector2)
	local current = press
	if not current then
		return
	end
	if not current.Dragging then
		if (position - current.Start).Magnitude < DRAG_THRESHOLD then
			return
		end
		current.Dragging = true
		-- A long press before moving means "split" on touch screens.
		if current.Input.UserInputType == Enum.UserInputType.Touch and os.clock() - current.Started >= LONG_PRESS then
			current.Split = true
		end
		local data = inventory :: InventoryData
		local stack = data.Slots[current.Key]
		ItemIcon.Set(ghost, stack and stack.Id)
		ghost.Visible = true
		tooltip.Visible = false
		tween(slotViews[current.Key].Viewport, 0.12, { ImageTransparency = 0.6 })
	end
	ghost.Position = UDim2.fromOffset(position.X, position.Y)
end

local function wire(view: SlotView)
	if view.Button:GetAttribute("Wired") then
		return
	end
	view.Button:SetAttribute("Wired", true)
	view.Button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			beginPress(view.Key, input)
		end
	end)
	view.Button.MouseEnter:Connect(function()
		hoveredKey = view.Key
		if not press or not press.Dragging then
			tween(view.Button, 0.12, { BackgroundColor3 = THEME.SurfaceHover })
			updateTooltip()
		end
	end)
	view.Button.MouseLeave:Connect(function()
		if hoveredKey == view.Key then
			hoveredKey = nil
			updateTooltip()
		end
		tween(view.Button, 0.12, { BackgroundColor3 = THEME.Surface })
	end)
end

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		if press and (input.UserInputType == Enum.UserInputType.MouseMovement or rawequal(input, press.Input)) then
			updateDrag(rawPosition(input) + press.Offset)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if press and (rawequal(input, press.Input) or input.UserInputType == Enum.UserInputType.MouseButton1) then
		endDrag(rawPosition(input) + press.Offset)
	end
end)

---------------------------------------------------------------------------------------------
-- Open / close

local open = false

local function setOpen(value: boolean)
	if open == value then
		return
	end
	open = value
	if value then
		fitToScreen()
		local target = windowScale.Scale
		windowScale.Scale = target * 0.94
		window.Position = UDim2.new(0.5, 0, 0.5, 12)
		window.Visible = true
		tween(windowScale, 0.22, { Scale = target })
		tween(window, 0.22, { Position = UDim2.fromScale(0.5, 0.5) })
		render()
	else
		press = nil
		ghost.Visible = false
		tooltip.Visible = false
		hoveredKey = nil
		window.Visible = false
	end
end

toggleButton.Activated:Connect(function()
	setOpen(not open)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)
sortButton.Activated:Connect(function()
	request("Sort")
end)

ContextActionService:BindAction("ToggleInventory", function(_, state)
	if state == Enum.UserInputState.Begin then
		setOpen(not open)
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.B)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and open then
		setOpen(false)
	end
end)

local function watchCamera()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if open then
				fitToScreen()
			end
		end)
	end
end
watchCamera()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)

RunService.RenderStepped:Connect(placeTooltip)

---------------------------------------------------------------------------------------------
-- Data

local function apply(data: InventoryData)
	if not inventory or inventory.Capacity ~= data.Capacity then
		layout(data.Capacity)
		for _, view in slotViews do
			wire(view)
		end
	end
	inventory = data
	render()
	updateTooltip()
end

syncEvent.OnClientEvent:Connect(apply)

layout(rows * COLUMNS)
for _, view in slotViews do
	wire(view)
end
gui.Parent = player:WaitForChild("PlayerGui")

task.spawn(function()
	-- Ask once in case the first Sync arrived before this script was listening.
	while not inventory do
		local ok, data = pcall(requestFunction.InvokeServer, requestFunction, "Fetch")
		if ok and type(data) == "table" and not inventory then
			apply(data)
		end
		if not inventory then
			task.wait(1)
		end
	end
end)

---------------------------------------------------------------------------------------------
-- World pickups: animate locally so the server never has to replicate the motion.

local pickupFolder = Workspace:WaitForChild("ItemPickups")
local bases: { [Model]: CFrame } = {}

local function track(child: Instance)
	if child:IsA("Model") then
		bases[child] = child:GetPivot()
	end
end
for _, child in pickupFolder:GetChildren() do
	track(child)
end
pickupFolder.ChildAdded:Connect(track)
pickupFolder.ChildRemoved:Connect(function(child)
	bases[child :: Model] = nil
end)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for model, base in bases do
		local phase = (base.Position.X + base.Position.Z) * 0.37
		model:PivotTo(base * CFrame.new(0, math.sin(t * 2 + phase) * 0.25, 0) * CFrame.Angles(0, t * 1.2 + phase, 0))
	end
end)
