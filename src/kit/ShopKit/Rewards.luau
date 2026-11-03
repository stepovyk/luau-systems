--!strict
-- What buyers actually get. Runs on the server only.
--
-- Products: Config.Products[i].Reward names a function below; it receives the player and
-- Config.Products[i].Amount. Return true once the reward is safely stored. Returning false
-- (or erroring) makes Roblox retry the purchase later, so the player never pays for nothing.
-- To sell currency, add e.g. `Coins = function(player, amount) return MyData.AddCoins(player, amount) end`.
--
-- Passes: OnPassOwned[passId] runs every time a player who owns that pass joins, and right
-- after they buy it. Use it to switch perks on.

local SUPPORTER_PASS = 2067888694
local GOLD = Color3.fromRGB(255, 196, 92)

local Rewards = {}

local function addTag(character: Model)
	-- The root part is never swapped out when the avatar's appearance loads, unlike the head.
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or root:FindFirstChild("SupporterTag") then
		return
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = "SupporterTag"
	tag.Size = UDim2.fromOffset(120, 30)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	tag.MaxDistance = 80
	tag.AlwaysOnTop = true
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
	text.TextSize = 18
	text.TextColor3 = GOLD
	text.TextStrokeTransparency = 0.4
	text.Text = "Supporter"
	text.Parent = tag
	tag.Parent = root
end

Rewards.Products = {
	-- A tip grants nothing in game; it is counted so supporters can be thanked.
	Tip = function(player: Player, amount: number): boolean
		player:SetAttribute("Tipped", ((player:GetAttribute("Tipped") :: number?) or 0) + amount)
		return true
	end,
} :: { [string]: (player: Player, amount: number) -> boolean }

Rewards.OnPassOwned = {
	[SUPPORTER_PASS] = function(player: Player)
		if player.Character then
			task.spawn(addTag, player.Character)
		end
		player.CharacterAdded:Connect(addTag)
	end,
} :: { [number]: (player: Player) -> () }

return Rewards
