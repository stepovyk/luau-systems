# Luau Systems

Production-ready Roblox systems in strictly typed Luau. Each one is server-authoritative, survives bad input from exploiters and ships with tests.

**Try it live:** [Luau Systems Showcase](https://www.roblox.com/games/93824850830403)

## Player data

`src/server/PlayerData` keeps every player's data in a DataStore without losing or duplicating it.

- **Session locking.** Only one server owns a player's data at a time. The lock lives in the saved record and is taken with `UpdateAsync`, so two servers never overwrite each other, even during fast teleports. A lock from a crashed server expires after 5 minutes.
- **Safe saving.** Autosave every 60 s, final save on leave, and `BindToClose` waits for pending writes on shutdown. Each request waits for DataStore budget and retries with exponential backoff.
- **Schema evolution.** New template fields appear in old saves automatically; numbered migrations handle real conversions.
- **Studio friendly.** In an unpublished place (or without API access) data lives in memory for the session, with a clear warning instead of a crash.

```lua
PlayerData.Start({ StoreName = "PlayerData", Template = { Coins = 0 } })
PlayerData.OnEachProfile(function(profile)
	profile.Data.Coins += 10
end)
```

## Inventory

- 24 backpack slots plus Weapon, Head, Body and Trinket equipment slots; equipped gear adds Attack, Defense and Max health.
- Stacking, splitting, merging, swapping, sorting, using consumables, dropping into the world and picking up again.
- Every request is validated on the server and rate limited per player. The client only asks; the server decides and sends the result back.
- Saved inventories are repaired on load: removed items, broken counts, misplaced gear and a changed capacity are all handled.
- Items are defined in one table (`ItemCatalog`). Add an entry and it works everywhere.
- The window works with mouse, touch and keyboard (`B`), scales to phone screens and shows item tooltips with stats.

```lua
InventoryService.Give(player, "health_potion", 3) -- returns how many fit
InventoryService.Take(player, "iron_ore", 10)     -- all or nothing
InventoryService.Changed:Connect(function(player, inventory) end)
```

World pickups: tag any part `ItemSpawner` and set the `ItemId`, `Count` and `RespawnSeconds` attributes.

## Project layout

| Path | Goes to | Contents |
| --- | --- | --- |
| `src/shared` | ReplicatedStorage.Systems | Pure inventory rules, item catalog, item models, utilities |
| `src/server` | ServerScriptService.Systems | Player data, inventory service, pickups, showcase map |
| `src/client` | StarterPlayerScripts.Systems | Inventory window |

`Showcase.server.luau` only builds the demo plaza; delete it in a real game.

## Development

Built with [Rojo](https://rojo.space). Checks run on every push: StyLua formatting, Selene lint, luau-lsp strict type checking, Lune unit tests and a Rojo build.

```sh
rojo build -o showcase.rbxl   # place file
rojo serve                    # live sync into Studio
lune run tests/run            # unit tests
```

## License

MIT
