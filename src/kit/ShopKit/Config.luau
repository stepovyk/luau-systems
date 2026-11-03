--!strict
-- Everything you edit to set up the shop lives in this file and in Rewards.
-- Ids come from Creator Hub: your experience > Monetization > Passes / Developer Products.
-- Prices, names and icons are read from Roblox automatically; the fields below only add
-- what Roblox doesn't store (category, highlight, reward).

export type PassEntry = {
	Id: number,
	-- Short line under the name. Leave nil to use the description from Creator Hub.
	Description: string?,
	-- Shown as a ribbon on the card, e.g. "Popular" or "Best value".
	Badge: string?,
}

export type ProductEntry = {
	Id: number,
	Description: string?,
	Badge: string?,
	-- Name of a function in Rewards and the value passed to it.
	Reward: string,
	Amount: number,
}

local Config = {
	-- Title of the shop window.
	Title = "Support",

	-- Game passes: bought once, owned forever.
	Passes = {
		{ Id = 2067888694, Badge = "Cosmetic" },
	} :: { PassEntry },

	-- Developer products: can be bought again and again (currency packs, boosts, revives).
	Products = {
		{ Id = 3727574161, Reward = "Tip", Amount = 25 },
		{ Id = 3727574589, Reward = "Tip", Amount = 100, Badge = "Thank you!" },
	} :: { ProductEntry },

	-- Where the shop button sits. Scale X/Y of the screen, anchored at its own center.
	ButtonPosition = UDim2.new(1, -96, 1, -44),

	-- Key that opens and closes the shop on keyboards. Set to nil to disable.
	ToggleKey = Enum.KeyCode.M :: Enum.KeyCode?,

	-- Name of the DataStore that remembers granted purchases so nothing is granted twice.
	ReceiptStore = "ShopKitReceipts",
}

return Config
