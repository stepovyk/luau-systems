--!strict
-- Shop window. Prices, names and icons come from Roblox, so changing a price in Creator Hub
-- updates the shop without touching code. Purchases go through Roblox's own prompt; the
-- server grants rewards and tells this script when to celebrate.

local ContextActionService = game:GetService("ContextActionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local root = script.Parent
local Config = require(root:WaitForChild("Config")) :: any
local purchasedEvent = root:WaitForChild("Purchased") :: RemoteEvent

local player = Players.LocalPlayer

---------------------------------------------------------------------------------------------
-- Look

local THEME = {
	Panel = Color3.fromRGB(17, 19, 25),
	Surface = Color3.fromRGB(28, 31, 40),
	SurfaceHover = Color3.fromRGB(38, 42, 54),
	Stroke = Color3.fromRGB(52, 57, 72),
	Text = Color3.fromRGB(236, 239, 245),
	Muted = Color3.fromRGB(142, 149, 166),
	Buy = Color3.fromRGB(58, 186, 110),
	BuyHover = Color3.fromRGB(72, 204, 126),
	Owned = Color3.fromRGB(46, 50, 62),
	Badge = Color3.fromRGB(255, 176, 64),
}
local FONT = Font.fromEnum(Enum.Font.BuilderSans)
local FONT_BOLD = Font.new(FONT.Family, Enum.FontWeight.Bold)
local FONT_SEMI = Font.new(FONT.Family, Enum.FontWeight.SemiBold)
local ROBUX = utf8.char(0xE002)

local COLUMNS = 3
local CARD_W, CARD_H = 196, 232
local GAP = 12
local PADDING = 20
local VISIBLE_ROWS = 2

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

local function label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextColor3 = THEME.Text
	l.TextSize = 16
	l.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(l :: any)[key] = value
	end
	return l
end

local function tween(instance: Instance, seconds: number, goal: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal):Play()
end

local function hover(button: GuiButton, normal: Color3, hovered: Color3)
	button.MouseEnter:Connect(function()
		if button.Active then
			tween(button, 0.12, { BackgroundColor3 = hovered })
		end
	end)
	button.MouseLeave:Connect(function()
		if button.Active then
			tween(button, 0.12, { BackgroundColor3 = normal })
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Product info, cached

type Info = { Name: string, Description: string, Price: number?, Icon: number? }
local infoCache: { [string]: Info } = {}

local function fetchInfo(id: number, kind: Enum.InfoType): Info?
	local key = `{kind.Name}:{id}`
	if infoCache[key] then
		return infoCache[key]
	end
	for attempt = 1, 3 do
		local ok, result = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, kind)
		if ok and type(result) == "table" then
			local info: Info = {
				Name = result.Name or "",
				Description = result.Description or "",
				Price = result.PriceInRobux,
				Icon = result.IconImageAssetId,
			}
			infoCache[key] = info
			return info
		end
		task.wait(attempt)
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- Layout

local gui = Instance.new("ScreenGui")
gui.Name = "ShopKit"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 11

local openButton = Instance.new("TextButton")
openButton.Name = "OpenShop"
openButton.AutoButtonColor = false
openButton.AnchorPoint = Vector2.new(0.5, 0.5)
openButton.Position = Config.ButtonPosition
openButton.Size = UDim2.fromOffset(150, 48)
openButton.BackgroundColor3 = THEME.Buy
openButton.FontFace = FONT_BOLD
openButton.TextSize = 18
openButton.TextColor3 = Color3.new(1, 1, 1)
openButton.Text = `{ROBUX}  {Config.Title}`
openButton.Parent = gui
corner(openButton, 14)
hover(openButton, THEME.Buy, THEME.BuyHover)

local gridWidth = COLUMNS * CARD_W + (COLUMNS - 1) * GAP
local window = Instance.new("Frame")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromOffset(gridWidth + PADDING * 2, 66 + 44 + 14 + VISIBLE_ROWS * CARD_H + GAP + PADDING)
window.BackgroundColor3 = THEME.Panel
window.BackgroundTransparency = 0.04
window.Visible = false
window.Parent = gui
corner(window, 18)
stroke(window, THEME.Stroke, 1)
local windowScale = Instance.new("UIScale")
windowScale.Parent = window

label({
	Text = Config.Title,
	FontFace = FONT_BOLD,
	TextSize = 24,
	Position = UDim2.fromOffset(PADDING, 16),
	Size = UDim2.fromOffset(300, 32),
	Parent = window,
})

local closeButton = Instance.new("TextButton")
closeButton.AutoButtonColor = false
closeButton.Text = ""
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -PADDING, 0, 16)
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.BackgroundColor3 = THEME.Surface
closeButton.Parent = window
corner(closeButton, 10)
hover(closeButton, THEME.Surface, THEME.SurfaceHover)
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

-- Tabs
local tabBar = Instance.new("Frame")
tabBar.Position = UDim2.fromOffset(PADDING, 62)
tabBar.Size = UDim2.fromOffset(240, 40)
tabBar.BackgroundColor3 = THEME.Surface
tabBar.Parent = window
corner(tabBar, 12)
local tabPadding = Instance.new("UIPadding")
tabPadding.PaddingLeft = UDim.new(0, 4)
tabPadding.PaddingRight = UDim.new(0, 4)
tabPadding.PaddingTop = UDim.new(0, 4)
tabPadding.PaddingBottom = UDim.new(0, 4)
tabPadding.Parent = tabBar
local tabHighlight = Instance.new("Frame")
tabHighlight.Size = UDim2.fromScale(0.5, 1)
tabHighlight.BackgroundColor3 = THEME.SurfaceHover
tabHighlight.Parent = tabBar
corner(tabHighlight, 9)

type Tab = "Passes" | "Items"
local tabButtons: { [Tab]: TextButton } = {}
for index, name in { "Passes", "Items" } :: { Tab } do
	local button = Instance.new("TextButton")
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(0.5, 1)
	button.Position = UDim2.fromScale((index - 1) * 0.5, 0)
	button.FontFace = FONT_SEMI
	button.TextSize = 16
	button.TextColor3 = THEME.Muted
	button.Text = name
	button.ZIndex = 2
	button.Parent = tabBar
	tabButtons[name :: Tab] = button
end

local scroller = Instance.new("ScrollingFrame")
scroller.Position = UDim2.fromOffset(PADDING, 62 + 40 + 14)
scroller.Size = UDim2.new(1, -PADDING * 2 + 8, 1, -(62 + 40 + 14) - PADDING)
scroller.BackgroundTransparency = 1
scroller.BorderSizePixel = 0
scroller.ScrollBarThickness = 4
scroller.ScrollBarImageColor3 = THEME.Stroke
scroller.CanvasSize = UDim2.new()
scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroller.ScrollingDirection = Enum.ScrollingDirection.Y
scroller.Parent = window
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
grid.CellPadding = UDim2.fromOffset(GAP, GAP)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = scroller

local emptyLabel = label({
	Text = "",
	TextColor3 = THEME.Muted,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.fromOffset(300, 24),
	Visible = false,
	Parent = window,
})

---------------------------------------------------------------------------------------------
-- Cards

type Card = { Frame: Frame, Button: TextButton, Kind: Tab, Id: number }
local cards: { Card } = {}

local function ownsPass(id: number): boolean
	return player:GetAttribute(`ShopKitPass_{id}`) == true
end

local function refreshButton(card: Card)
	local info =
		infoCache[`{(if card.Kind == "Passes" then Enum.InfoType.GamePass else Enum.InfoType.Product).Name}:{card.Id}`]
	local button = card.Button
	if card.Kind == "Passes" and ownsPass(card.Id) then
		button.Active = false
		button.AutoButtonColor = false
		button.BackgroundColor3 = THEME.Owned
		button.TextColor3 = THEME.Muted
		button.Text = "Owned"
	elseif info and info.Price then
		button.Active = true
		button.BackgroundColor3 = THEME.Buy
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Text = `{ROBUX} {info.Price}`
	else
		button.Active = false
		button.BackgroundColor3 = THEME.Owned
		button.TextColor3 = THEME.Muted
		button.Text = if info then "Off sale" else "Loading"
	end
end

local function makeCard(kind: Tab, entry: any, order: number): Card
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.BackgroundColor3 = THEME.Surface
	frame.Parent = scroller
	corner(frame, 14)
	stroke(frame, THEME.Stroke, 1, 0.5)

	local icon = Instance.new("ImageLabel")
	icon.BackgroundColor3 = THEME.Panel
	icon.BackgroundTransparency = 0.4
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 14)
	icon.Size = UDim2.fromOffset(84, 84)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = frame
	corner(icon, 16)

	local name = label({
		Text = "",
		FontFace = FONT_BOLD,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(12, 106),
		Size = UDim2.new(1, -24, 0, 22),
		Parent = frame,
	})
	local description = label({
		Text = "",
		TextColor3 = THEME.Muted,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(12, 130),
		Size = UDim2.new(1, -24, 0, 38),
		Parent = frame,
	})

	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -12)
	button.Size = UDim2.new(1, -24, 0, 40)
	button.BackgroundColor3 = THEME.Owned
	button.FontFace = FONT_BOLD
	button.TextSize = 17
	button.TextColor3 = THEME.Muted
	button.Text = "Loading"
	button.Parent = frame
	corner(button, 10)
	hover(button, THEME.Buy, THEME.BuyHover)

	if entry.Badge then
		local badge = label({
			Text = entry.Badge,
			FontFace = FONT_BOLD,
			TextSize = 12,
			TextColor3 = Color3.fromRGB(32, 22, 6),
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0,
			BackgroundColor3 = THEME.Badge,
			AutomaticSize = Enum.AutomaticSize.X,
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.fromOffset(0, 22),
			ZIndex = 2,
			Parent = frame,
		})
		corner(badge, 11)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 9)
		pad.PaddingRight = UDim.new(0, 9)
		pad.Parent = badge
	end

	local card: Card = { Frame = frame, Button = button, Kind = kind, Id = entry.Id }

	button.Activated:Connect(function()
		if not button.Active then
			return
		end
		if kind == "Passes" then
			MarketplaceService:PromptGamePassPurchase(player, entry.Id)
		else
			MarketplaceService:PromptProductPurchase(player, entry.Id)
		end
	end)

	task.spawn(function()
		local info = fetchInfo(entry.Id, if kind == "Passes" then Enum.InfoType.GamePass else Enum.InfoType.Product)
		if info then
			name.Text = info.Name
			description.Text = entry.Description or info.Description
			if info.Icon and info.Icon > 0 then
				icon.Image = `rbxassetid://{info.Icon}`
			end
		else
			name.Text = "Unavailable"
		end
		refreshButton(card)
	end)

	if kind == "Passes" then
		player:GetAttributeChangedSignal(`ShopKitPass_{entry.Id}`):Connect(function()
			refreshButton(card)
		end)
	end

	table.insert(cards, card)
	return card
end

for index, entry in Config.Passes do
	makeCard("Passes", entry, index)
end
for index, entry in Config.Products do
	makeCard("Items", entry, index)
end

local currentTab: Tab = "Passes"
local function showTab(tab: Tab)
	currentTab = tab
	local count = 0
	for _, card in cards do
		card.Frame.Visible = card.Kind == tab
		if card.Frame.Visible then
			count += 1
		end
	end
	for name, button in tabButtons do
		tween(button, 0.15, { TextColor3 = if name == tab then THEME.Text else THEME.Muted })
	end
	tween(tabHighlight, 0.2, { Position = UDim2.fromScale(if tab == "Passes" then 0 else 0.5, 0) })
	emptyLabel.Text = if tab == "Passes" then "No passes yet" else "No items yet"
	emptyLabel.Visible = count == 0
	scroller.CanvasPosition = Vector2.zero
end

for name, button in tabButtons do
	button.Activated:Connect(function()
		showTab(name :: any)
	end)
end

---------------------------------------------------------------------------------------------
-- Toast after a successful purchase

local toast = Instance.new("Frame")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, -80)
toast.Size = UDim2.fromOffset(0, 52)
toast.AutomaticSize = Enum.AutomaticSize.X
toast.BackgroundColor3 = THEME.Panel
toast.Visible = false
toast.ZIndex = 20
toast.Parent = gui
corner(toast, 14)
stroke(toast, THEME.Buy, 1.5)
local toastPad = Instance.new("UIPadding")
toastPad.PaddingLeft = UDim.new(0, 20)
toastPad.PaddingRight = UDim.new(0, 20)
toastPad.Parent = toast
local toastText = label({
	FontFace = FONT_SEMI,
	TextSize = 17,
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.fromScale(0, 1),
	ZIndex = 21,
	Parent = toast,
})

local toastToken = 0
local function showToast(text: string)
	toastToken += 1
	local token = toastToken
	toastText.Text = text
	toast.Visible = true
	toast.Position = UDim2.new(0.5, 0, 0, -80)
	tween(toast, 0.35, { Position = UDim2.new(0.5, 0, 0, 72) })
	task.delay(2.8, function()
		if token == toastToken then
			tween(toast, 0.3, { Position = UDim2.new(0.5, 0, 0, -80) })
			task.delay(0.3, function()
				if token == toastToken then
					toast.Visible = false
				end
			end)
		end
	end)
end

purchasedEvent.OnClientEvent:Connect(function(kind: string, id: number)
	local info = infoCache[`{(if kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product).Name}:{id}`]
	showToast(`Thanks! {if info then info.Name else "Purchase"} is yours`)
end)

---------------------------------------------------------------------------------------------
-- Open / close

local open = false

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
		showTab(currentTab)
	else
		window.Visible = false
	end
end

openButton.Activated:Connect(function()
	setOpen(not open)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)

if Config.ToggleKey then
	ContextActionService:BindAction("ShopKitToggle", function(_, state)
		if state == Enum.UserInputState.Begin then
			setOpen(not open)
		end
		return Enum.ContextActionResult.Sink
	end, false, Config.ToggleKey)
end

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

-- Start on whichever tab has something in it.
if #Config.Passes == 0 and #Config.Products > 0 then
	currentTab = "Items"
end

gui.Parent = player:WaitForChild("PlayerGui")
