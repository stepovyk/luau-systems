--!strict
-- Session-locked player data on top of DataStoreService.
--
-- * One server owns a player's data at a time. The lock lives inside the saved record and is
--   claimed and released with UpdateAsync, so two servers can never overwrite each other.
-- * A lock that has not been refreshed for LOCK_TIMEOUT seconds belongs to a crashed server
--   and may be taken over. Live servers refresh it on every autosave.
-- * Every request waits for DataStore budget and retries with backoff.
-- * New fields in the template are filled into old saves automatically; numbered migrations
--   handle anything that needs real conversion.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Signal = require(game:GetService("ReplicatedStorage").Systems.Util.Signal)

local AUTOSAVE_INTERVAL = 60
local LOCK_TIMEOUT = 5 * 60
local LOAD_ATTEMPTS_WHILE_LOCKED = 6
local LOCKED_RETRY_DELAY = 5
local REQUEST_ATTEMPTS = 5
local BUDGET_WAIT_LIMIT = 30

-- Studio has no JobId, and each Studio session must still look like its own server.
local SESSION_ID = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

type Lock = { Session: string, PlaceId: number, Updated: number }
type Record = { Data: any, Lock: Lock?, Version: number }

export type Profile = {
	Player: Player,
	Data: any,
	Released: boolean,
	-- Fires once when the profile stops being authoritative (player left or lock lost).
	OnRelease: Signal.Signal<>,
}

export type Config = {
	StoreName: string,
	Template: { [string]: any },
	-- Migrations[n] turns data saved at version n-1 into version n.
	Migrations: { (data: any) -> any }?,
}

local PlayerData = {}

local store: DataStore? = nil
local config: Config? = nil
local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}
-- UserIds whose final save is still running; a quick rejoin must wait for it.
local releasing: { [number]: boolean } = {}
local savesInFlight = 0

PlayerData.ProfileLoaded = Signal.new() :: Signal.Signal<Profile>

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[deepCopy(k)] = deepCopy(v)
	end
	return copy :: any
end

-- Fills in keys that exist in the template but not in the data, recursively.
local function reconcile(data: { [string]: any }, template: { [string]: any })
	for key, value in template do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(data[key]) == "table" and type(value) == "table" then
			reconcile(data[key], value)
		end
	end
end

local function currentVersion(): number
	return if config and config.Migrations then #config.Migrations else 0
end

local function waitForBudget(requestType: Enum.DataStoreRequestType)
	local started = os.clock()
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 do
		if os.clock() - started > BUDGET_WAIT_LIMIT then
			return
		end
		task.wait(0.5)
	end
end

-- Runs UpdateAsync with budget checks and exponential backoff. The transform may run more
-- than once, so it must stay free of side effects outside its return value.
local function update(key: string, transform: (record: Record?) -> Record?): (boolean, string?)
	local lastError: string? = nil
	for attempt = 1, REQUEST_ATTEMPTS do
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key, function(old)
				return transform(old)
			end)
		end)
		if ok then
			return true
		end
		lastError = tostring(err)
		warn(`[PlayerData] UpdateAsync failed for {key} (attempt {attempt}/{REQUEST_ATTEMPTS}): {lastError}`)
		if attempt < REQUEST_ATTEMPTS then
			task.wait(2 ^ (attempt - 1))
		end
	end
	return false, lastError
end

local function keyFor(player: Player): string
	return `Player_{player.UserId}`
end

local function isLockedByOther(lock: Lock?, now: number): boolean
	return lock ~= nil and lock.Session ~= SESSION_ID and now - lock.Updated < LOCK_TIMEOUT
end

local function migrate(data: any, fromVersion: number): any
	local migrations = (config :: Config).Migrations
	if migrations then
		for version = fromVersion + 1, #migrations do
			data = migrations[version](data)
		end
	end
	return data
end

type LoadResult = "Loaded" | "Locked" | "Failed"

local function tryLoad(player: Player): (LoadResult, any)
	local cfg = config :: Config
	local result: LoadResult = "Failed"
	local loaded: any = nil
	local ok = update(keyFor(player), function(old)
		local now = os.time()
		if old and isLockedByOther(old.Lock, now) then
			result = "Locked"
			return nil -- leave the record untouched
		end
		local data: any
		if old and old.Data ~= nil then
			data = migrate(old.Data, old.Version or 0)
		else
			data = deepCopy(cfg.Template)
		end
		reconcile(data, cfg.Template)
		result = "Loaded"
		loaded = data
		return {
			Data = data,
			Version = currentVersion(),
			Lock = { Session = SESSION_ID, PlaceId = game.PlaceId, Updated = now },
		}
	end)
	if not ok then
		return "Failed", nil
	end
	return result, loaded
end

-- Writes the profile. With `release`, also clears the lock so the next server can load.
local function save(profile: Profile, release: boolean): boolean
	local lostLock = false
	savesInFlight += 1
	local ok = update(keyFor(profile.Player), function(old)
		if old and old.Lock and old.Lock.Session ~= SESSION_ID then
			-- Another server took the lock over; our copy is no longer the truth.
			lostLock = true
			return nil
		end
		return {
			Data = profile.Data,
			Version = currentVersion(),
			Lock = if release then nil else { Session = SESSION_ID, PlaceId = game.PlaceId, Updated = os.time() },
		}
	end)
	savesInFlight -= 1
	if lostLock then
		warn(`[PlayerData] Lost session lock for {profile.Player.UserId}; this server stops saving it`)
		PlayerData._release(profile)
		if profile.Player.Parent == Players then
			profile.Player:Kick("Your data was opened on another server. Please rejoin.")
		end
		return false
	end
	return ok
end

function PlayerData._release(profile: Profile)
	if profile.Released then
		return
	end
	profile.Released = true
	if profiles[profile.Player] == profile then
		profiles[profile.Player] = nil
	end
	profile.OnRelease:Fire()
	profile.OnRelease:DisconnectAll()
end

local function loadPlayer(player: Player)
	if loading[player] or profiles[player] then
		return
	end
	loading[player] = true
	while releasing[player.UserId] do
		task.wait()
	end

	local status: LoadResult, data: any = "Failed", nil
	for attempt = 1, LOAD_ATTEMPTS_WHILE_LOCKED do
		status, data = tryLoad(player)
		if status ~= "Locked" or player.Parent ~= Players then
			break
		end
		-- Usually the previous server is still finishing its final save after a teleport.
		if attempt < LOAD_ATTEMPTS_WHILE_LOCKED then
			task.wait(LOCKED_RETRY_DELAY)
		end
	end
	loading[player] = nil

	if status ~= "Loaded" then
		if player.Parent == Players then
			player:Kick(
				if status == "Locked"
					then "Your data is still being saved on another server. Please rejoin in a minute."
					else "Could not load your data. Please rejoin."
			)
		end
		return
	end

	local profile: Profile = {
		Player = player,
		Data = data,
		Released = false,
		OnRelease = Signal.new(),
	}

	if player.Parent ~= Players then
		-- Left while we were loading: hand the lock straight back.
		save(profile, true)
		return
	end

	profiles[player] = profile
	PlayerData.ProfileLoaded:Fire(profile)
end

local function releasePlayer(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	-- Detach first so game code sees the release before the final write finishes.
	PlayerData._release(profile)
	releasing[player.UserId] = true
	save(profile, true)
	releasing[player.UserId] = nil
end

-- Starts the service. Call once from a server script before players need their data.
function PlayerData.Start(cfg: Config)
	assert(config == nil, "PlayerData.Start called twice")
	assert(RunService:IsServer(), "PlayerData runs on the server only")
	config = cfg
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, cfg.StoreName)
	if not ok then
		error(
			`[PlayerData] DataStores unavailable ({result}). In Studio, enable "Studio Access to API Services" in Game Settings > Security.`
		)
	end
	store = result

	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(releasePlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, profile in profiles do
				task.spawn(save, profile, false)
			end
		end
	end)

	game:BindToClose(function()
		for player in profiles do
			task.spawn(releasePlayer, player)
		end
		-- Roblox gives BindToClose 30 seconds; leave a margin.
		local deadline = os.clock() + 25
		while (savesInFlight > 0 or next(loading) ~= nil) and os.clock() < deadline do
			task.wait()
		end
	end)
end

-- The loaded profile, or nil while loading / after the player left.
function PlayerData.Get(player: Player): Profile?
	return profiles[player]
end

-- Yields until the profile is ready. Returns nil if the player leaves first.
function PlayerData.WaitFor(player: Player): Profile?
	while player.Parent == Players do
		local profile = profiles[player]
		if profile then
			return profile
		end
		task.wait()
	end
	return nil
end

-- Calls `handler` for every profile, now and in the future.
function PlayerData.OnEachProfile(handler: (Profile) -> ())
	for _, profile in profiles do
		task.spawn(handler, profile)
	end
	PlayerData.ProfileLoaded:Connect(handler)
end

-- Saves immediately, e.g. right after a purchase.
function PlayerData.SaveNow(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and save(profile, false)
end

return PlayerData
