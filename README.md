# mod-quest-teleport

AzerothCore 3.3.5a **Eluna/ALE** script plus a tiny client addon. Puts a **Teleport Near** button on the quest log: stand still 3 seconds, then land about 25 yards from the quest goal (or the turn-in when the quest is complete).

Works with **stock Blizzard quest log** (`QuestLogFrame`). ForeverUI is optional: if it is loaded, the stock log is hidden, so the addon also attaches to `ForeverUIQuestDetailsFrame`.

Compatible with **mod-playerbots** (bots are ignored). No core C++ patch. No SQL.

## Server

Requires [mod-eluna](https://github.com/azerothcore/mod-eluna) (or ALE) on AzerothCore / Playerbots branch.

Copy `lua_scripts/quest_teleport.lua` into your worldserver Lua folder (for example `lua_scripts/` or `modules/lua_scripts/`) and `.reload ale` / restart.

Config at the top of the script: cooldown (60s), cast time (3s), offset (25 yd), continents only, optional GM-only.

## Client

Copy `addon/FamQuestPort` into `Interface/AddOns/`. `/tpnear` works even if the button is hidden.

## Protocol

Addon message prefix `FQP`, whisper to self, payload `TP:<questId>`.
