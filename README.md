![Faction Power](docs/banner.png)

# Faction Power — your deeds earn Faction Power in SpaceBourne 2

In vanilla SpaceBourne 2 your faction's **Faction Power** — the currency you spend on
operations, stations and houses — comes from your stations and a few story missions.
Contracts, dungeons and trade earn you nothing for it. **Faction Power** changes that, and makes
the factions of the galaxy notice what you do where you do it.

Version 0.1.0 · [Nexus Mods page](https://www.nexusmods.com/spacebourne2/mods/9) · UE4SS Lua mod · works alone or with
[Hardcore Tactical Realism](https://github.com/hubertdungen/SpaceBourne2-HardcoreTacticalRealism).

## What it does

- **Missions pay Faction Power.** Contracts, bounties, guild and side quests: 300 Power × the
  mission type (a hack 0.5, a kill 0.75, a raid 1.5) × the difficulty. Story missions and your
  faction's own operations are left to vanilla, which already pays them.
- **Dungeons pay Faction Power.** Clearing a dungeon (its boss floor) gives 600 Power, more if
  the boss is above the system's level.
- **Strategic sales pay Faction Power.** Ship weapons, rockets, combat drones, ship modules,
  military salvage, hand weapons, grenades, ammo, suits: up to 150 Power per 10 000 credits.
  Junk, ore and trade goods do not count.
- **The galaxy reacts.** The family that rules the system gains or loses local support
  (the game's own *dominance*, the number that decides whether a system can be raided) and
  its relation with your faction changes:
  - you protected its space (guard, escort, rescue, clearing pirates) → it holds the system
    more firmly and likes you more;
  - you struck against it (a raid in a pirate-held system, a bounty on its faction, your
    faction's operation against it) → its hold weakens and it likes you less;
  - you sold it weapons → it grows a little stronger there. Selling in a pirate-held system
    strengthens the pirates, but only slightly.
- **No grinding.** Repeated sales of the same kind in the same place count for less; at most
  2 000 Power per game day (~10 minutes of play); local support is capped at ±25 % of a
  system's dominance and fades by half in ~5 hours of play; a dungeon in the same system
  counts again only after 7 game days.
- **Visible where the game shows it.** A HUD line for every deed that counts
  (`+225 Faction Power, Xeghan local support +1.1, relation with Xeghan +2 (mission)`), your
  Power counter, your relations, and a **Local support** line in the system's dominance
  breakdown.
- **Off by default.** Nothing changes until you switch it on.

## Requirements

- SpaceBourne 2 (Steam).
- [UE4SS 3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1). Installing HTR
  installs it too.

## Install

1. Download `FactionPower-0.1.0.zip` from the
   [releases](https://github.com/hubertdungen/SpaceBourne2-FactionPower/releases).
2. Extract it into the game folder (`...\steamapps\common\SpaceBourne 2\`). It adds
   `SB2\Binaries\Win64\Mods\FactionPower\` (the `enabled.txt` inside turns it on).
3. In game press **Shift+F9** to switch Faction Power on (remembered between sessions).
   The HUD shows your Power and the balance of the system you are in.

Manual install: copy the `FactionPower` folder from this repository into
`SpaceBourne 2\SB2\Binaries\Win64\Mods\`.

**Uninstall:** delete `SB2\Binaries\Win64\Mods\FactionPower`. Faction Power you earned stays
(it is yours). The Local support line disappears on its own the next time the game
recalculates a system (any system window does it).

## Keys

| Key | Action |
|---|---|
| **Shift+F9** | Faction Power on / off (switching on shows your Power and the local balance) |

Shift is the only modifier the realism set uses (on foot Ctrl opens the map and Alt
crouches), and no mod of the set uses the game's F6 quick save, F8 quick load or F10 bug
report. The key can be changed in `scripts\config.lua`.

## Settings

Edit `Mods\FactionPower\scripts\config.lua` (every line is optional):

- `Channels` — Faction Power, local influence, relations (all on).
- `Sources` — dungeons, sales, missions (on); commodity trade (not yet).
- `Dungeon`, `Sales` (the strategic weight of every item type), `Missions` — the amounts.
- `Limits` — Power per day, the influence cap, fading, daily budgets, market saturation.

## Save safety

- Everything goes through the game's own functions (`Add Remove Faction Power`, the family
  manager's diplomacy and dominance). The mod never writes save data directly.
- Its own memory is a small file next to it (`ledger-<character>.lua`), written through a
  temporary file with a backup. Load an older save and the mod undoes its own bookkeeping for
  the "future".
- Tested on a copy of a save: every other save file was byte-identical afterwards.

## Status and known limits

Tested in game (0.1.0): missions through the game's own completion path (a side quest paid
225 Power, +1.1 local support, relation +2; a mail contract was correctly left to vanilla),
Faction Power payouts, relations, the dominance line (one line, matching the mod's memory,
rebuilt after the game recalculates a system), market saturation, Shift+F9, frame times (no
measurable cost, no spikes).

Written from the game's Blueprints but **not yet seen in game**: shop sales (the "sold" toast
hook), the dungeon end (the dungeon door that marks a floor cleared; boss death as fallback),
the HUD line on screen. Commodity trade is not wired yet.

## Part of the SpaceBourne 2 realism set

| Mod | |
|---|---|
| **Hardcore Tactical Realism** — realistic on-foot ballistics and tactical NPC AI | [GitHub](https://github.com/hubertdungen/SpaceBourne2-HardcoreTacticalRealism) · [Nexus](https://www.nexusmods.com/spacebourne2/mods/4) · [Steam discussion](https://steamcommunity.com/app/1646850/discussions/0/573805072991123580) |
| **SB2 HOTAS** | [GitHub](https://github.com/hubertdungen/SpaceBourne2-HOTAS) · [Nexus](https://www.nexusmods.com/spacebourne2/mods/8) |
| **Split Controls** | [GitHub](https://github.com/hubertdungen/SpaceBourne2-SplitControls) · [Nexus](https://www.nexusmods.com/spacebourne2/mods/5) |
| **Silent Ops** — realistic stealth | [GitHub](https://github.com/hubertdungen/SpaceBourne2-SilentOps) · [Nexus](https://www.nexusmods.com/spacebourne2/mods/6) |
| **Gear Without Levels** | [GitHub](https://github.com/hubertdungen/SpaceBourne2-GearWithoutLevels) · [Nexus](https://www.nexusmods.com/spacebourne2/mods/7) |
| **Faction Power** (this mod) | [Nexus](https://www.nexusmods.com/spacebourne2/mods/9) |
| **Tactical Engineering** (turrets) | coming |
| **Tactical First Person** | coming |

One installer for the whole set is planned.

## License

MIT (see `LICENSE`). No game data is included.
