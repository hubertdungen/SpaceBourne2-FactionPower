# Faction Power — design

Status: **groundwork**. Research from the decompiled Blueprints (game build of
2026-10-26, UE 4.27.2, UE4SS 3.0.1). Nothing here has been run in game. Every hook and call
below is a plan to be verified in Phase 0.

Request: *dungeons, certain items you sell and certain missions give faction power.*
"Faction power" means the game's currency **Faction Power** (`Game_Builder.FactionPower`): the
author confirmed it. That is the main effect. The same deeds also move the local influence of
the family that rules the system and your relations with it (author: yes, missions may lower a
rival's hold depending on the mission; diplomatic relations must exist).

## 1. Summary

**Feasible**

- **Faction Power, the currency** (main effect), through the game's own `Add Remove Faction
  Power`. Vanilla pays it for story missions (`PowerReward`), mail quests, your stations
  (daily), castles and battles, but **not** for contracts, bounties, dungeons or sales. The mod
  adds those.
- **Relations** between your faction (`WRA`) and the ruling family through
  `UpdateDiplomaticRelations`: on by default (realism).
- **Local influence of AI factions (and of your own) per solar system.** The game already
  models how firmly a family holds a system: its *dominance*, a list of named point lines
  (planets, stations, trade routes, public order, civil rights, house bonus). When the total
  falls to the system's raid threshold, the system can be raided and captured. The native
  family manager has a function to add a line to that list
  (`AddDominanceVariableToSystem`), and the game's own system window lists every line by
  name. The mod adds **one line of its own per system** ("Local support") and moves it with
  your deeds. It is local, visible and bounded, and it works through the game's own war rules
  (raids, captures): lowering a rival's line is how a mission can open its system to your raids.
- **Event sources**: mission and contract completion (`Game_Builder:CompleteQuest`), shop sales
  (`Bought_Slot:UpdateItem`, the "sold" toast), a dungeon boss's death (section 3.1), dominance
  recalculation (`Game_Builder:CalculateDominance`). All are Blueprint functions, so they can be
  post-hooked.
- **Dungeons, partly.** The dungeon logic itself is native or in assets that were not decompiled,
  so "cleared" is detected as "the dungeon's boss died" (a good proxy, to refine in Phase 0).

**Not feasible (or not without big risk)**

- **Directly adding "power" to an AI family.** `FamilyPower`, `MilitaryPower`, `EconomicPower`,
  `DiplomaticPower` and `Wealth` are computed in C++ (`CalculateFamilyPowerAndWealth`) from what
  a family owns. There is no setter. The mod changes the inputs (dominance and, through the game's
  raids, territory) instead.
- **Instant territory flips.** Changing a system's owner (`ChangeStationsOwner`,
  `TransferStationToPF`) bypasses the war rules and could break saves. Not used.
- **Knowing who gave a mission and who it targets.** The quest data has a `GiverFaction` field,
  but the contract generator never fills it, and there is no target field. The mod derives
  both from where the mission takes place (section 3.3).
- **Hooking native code.** The family manager's functions are native C++: the mod may *call*
  them, never hook them.

**Unknown until tested** (Phase 0): whether AI factions consider dominance when they pick
targets (the code for AI attacks is native), whether the game keeps or drops a foreign line
when it recalculates a system, and how UE4SS returns out parameters of native calls.

## 2. How SpaceBourne 2 models faction power

### 2.1 Three layers

| Layer | Where | State |
|---|---|---|
| Old Blueprint families | `Game_Builder.Families` (`S_Diplomacy_Data`), `CalculatePower`, `AddRelationToFamilies`, `Reduce Power Struct` | legacy: converted to the native layer at load (`Q1FamiliyManager_BP:N_ConvertFamiliesToCPP`); power recomputed from scratch, so writes would be lost |
| **Native family manager** | `/Game/1Data/Q1FamiliyManager_BP.Q1FamiliyManager_BP_C`, child of native `/Script/SB2.Q1FamilyManager`; found via `Game_Builder.FamilyManagerRef` | **live**: families, systems, stations, dominance, wars, relations, trades; saved through `Game_Builder:Save Load Family Manager` |
| Your faction ("WRA") | `Game_Builder.FactionPower` (Int), `PlayerFactionData`, `PF_SolarSystems`, `PF_Wars`; in the native layer the family `WRA` | live |

### 2.2 Factions and families

- A **family** (house) has `FamilyID`, `FamilyName`, `FamilyLevel`, `FamilyParentType`,
  `FamilyOwnSystems`, `DiplomaticRelations`, `Castles` (native `Families` struct via
  `GetFamilyByID(FamilyID, out Family)`).
- `FamilyParentType` names seen in code: `Falron`, `Xeghan`, `Morthra`, `Pirates`, `Earthling`,
  `WRA` (you), `None`.
- The old `Factions` byte (quests, system data): 0 Morthra, 1 Falron, 2 Xeghan, 3 Pirates,
  4 Aliens, 5 Independent family, 6 WRA. Inferred from code; the enum asset was not dumped.
- `FindSystemOwner(SystemID)` returns the owning `FamilyID` directly (no out parameter).
- `GetFamilyStats(FamilyID)` returns `FamilyPower`, `MilitaryPower`, `DiplomaticPower`,
  `EconomicPower`, `Wealth`, all computed natively by `CalculateFamilyPowerAndWealth()`.
- Legacy formula, for scale: power = (systems × 100 + structures × 50) × `BaseSoldierLevel`.

### 2.3 Territory: system dominance

- `GetDominanceDataOfSystem(SystemID, out FamilyDominanceInSystem)` gives `SystemID`,
  `SystemSecurity`, `SystemDominanceVariables` (array of `DominanceVariable`), `StartDominance`,
  `RaidRequiredDominance`, `SystemLevel`, `ActiveDebuffs`, `PolicyType`, `IsStationsShutDown`,
  `IsStargatesShutDown`, `DailyTraffic`, `DailyIncome`, `DailyExpense`.
- `DominanceVariable` = `{ ID: Name, Name: Name, Type: Name, Point: Float }`.
- `Game_Builder:CalculateDominance(System, GameStartCalculete, out RaidRequiredValue, out OutData,
  out L_StationCount1)` (Blueprint) rebuilds the list with `AddDominanceVariableToSystem`:
  - `Planet` lines (one per planet; 6 points, 2 for special planet types, 0 if plundered),
  - `House` (house bonus), `PublicOrder` (2–20), `CivilRights` (2–14),
  - one line per station (its points), `TradeRoute` (8 or 16 per route).
  - A system totals roughly 30–100 points.
- `GetTotalDominanceOfSystem(System, false)` sums the lines. The raid threshold
  (`SetRaidRequiredDominance`) is about 40 % of the structure points plus extras;
  `StartDominance` is snapshotted once.
- **Raid rule** (the system resistance window, `GW_System_Resistance`): a system can be raided
  when `RaidRequiredDominance >= total dominance`. Lower total = easier to take.
- `CalculateDominance` runs when a system, faction, station, trade or operations window opens
  (11 call sites in widgets) and once per system at game start.
- The window's `BaseDominances` creates one slot per line, showing its `Name` and `Point`. A
  mod line appears there without any UI work.
- Spy operations add `ActiveDebuffs` natively (`AISpyOperation`); there is no Blueprint-callable
  "add debuff".

### 2.4 Relations

- Native: `UpdateDiplomaticRelations(FamilyA, FamilyB, Value:Int, Bool)`. Calls seen:
  `('WRA', defender, 9, true)` when you join a battle side, `(a, b, 100, true)` and
  `(a, b, 1000, true)` between galaxy-war allies, `(a, b, random 80–99, false)` at setup. So the
  bool most likely means *add* (true) vs *set* (false). To verify.
- Legacy `AddRelationToFamilies` clamps to −100..100.

### 2.5 Faction Power (the currency)

- `Game_Builder.FactionPower` (Int), shown in the main widget. Changed only by
  `Game_Builder:Add Remove Faction Power(Amount, out Success?, out CurrentPower)`: clamps at 0,
  fails if a spend would go negative, fires the global event `PowerUpdated`.
- Income: daily, the sum of `DailyPowerIncome` of your stations (`CalculateDailyResources`,
  native per-station value); mission `PowerReward` (`Game_Builder` mission-complete event); mail
  quests (`|Fame|`); castle battles; meeting table +5000; a scripted event +3100.
- Costs: a new house 10 000 × houses you own (`CalculateHouseBuildPower`); stations
  10 000–30 000; operations (native `GetOperationPowerCost`: capture, plunder, destroy);
  soldier training and upgrades; change of path −35 000.
- So the currency lives in the thousands. The mod pays hundreds per deed and at most 2 000 per
  game day (~12 000 per hour of play, about one station), to calibrate in Phase 0 against a
  station's real `DailyPowerIncome`.

### 2.6 Wars

- AI wars and the galaxy war live in the native manager (`GetAllWars`, `StartWar`, `StopWar`,
  `GetWarSidesPowerPercent`, `GenerateAIAttackOperation`, `UpdateBattleProgress`). No setter for
  war power.
- Blueprint events that the mod may listen to later: `Q1FamiliyManager_BP_C:BP_OnWarConcluded(WarID,
  WinnerFamilyID, LoserFamilyID, bPlayerFactionInvolved, bPlayerFactionLost)`,
  `Game_Builder_C:HandleGLXBattleOver(GalaxyBattleData)`.
- Station statuses (`AddStatusToStation`: `Destroyed`, `Plundered`, `Destructing`) are
  destructive. Not used.

### 2.7 Game clock

`Game_Builder.CurrentGameTime` (Int) grows by 3 every 3 s timer tick; `Game_Builder.Day =
CurrentGameTime / 600`. **One game day ≈ 10 minutes of play.** All the mod's limits are per game
day.

### 2.8 What vanilla already changes

| Event | Vanilla effect on factions |
|---|---|
| Contract, bounty, guild or side quest done | money, XP, guild points. **No faction, power or relation change.** Failure: no penalty |
| Mail quest (your faction's operations) | your faction's stats, people, Power |
| Story mission with `PowerReward` | your faction's Power |
| Your stations, daily | your faction's Power |
| Galaxy war battle over | stations destroyed or removed from their owner |
| Joining a battle side | relation +9 with that side |
| Dungeon cleared | nothing: the boss fires `ABossDied` and may drop a legend-key fragment |
| Selling or buying | money only; commodity sales change the sector's stock and demand |

## 3. Events the mod listens to

### 3.1 Dungeons

**The dungeon logic itself was not decompiled.** It lives in assets outside the rendered
folders and in C++:

- `/Game/1Galaxy/1_CPP_Dungeons/` (current system): `Q1_DungeonManager` (Blueprint child of native
  `/Script/SB2.CPP_DungeonManager`), `BP_DungeonTrasmitor`, `BP_MasterDungeonEnemy`, `BP_TreasureSpawner`,
  per-type folders CampDungeon, SalvageDungeon, CaveType (Crab/Monster/Scorpion/Spider), SpaceDungeon,
  WormholeDungeon.
- `/Game/1_Tests/DungeonFlow/` (older generator used by on-foot contracts): `DungeonGenerator_C`,
  `Boss_Triger`, `Dungeon_Boss`, `EBP_LegendaryChest`, `Leave_Dungeon_Elevator`.
- `/Game/Vx/Spwner/SurfaceLocations/Master_Random_LocationAtSurface` (planet-surface dungeons;
  `Q1Controller.CurrentSurfaceDungeon` with `DungeonCleared`, `MaxFloor`, `Current_Floor`).

The station interiors in `11Misc/1_Dungeons` (pirate, Falron, Morthra, independent stations) are
not dungeons you clear: they build station interiors.

What is known:

- Dungeon records are native `CPP_DungeonData` (`DungeonType`, `DungeonName`, `SystemID`,
  `SystemName`, `PlanetName`, `DungeonLevel`, `DungeonTier`, `Floors[]` with `bCleared`,
  `bIsDungeonLocked`, `IsLeagandDungeon`), read with the native `GetDungeons()` of the dungeon
  manager. Types shown by the records widget: 0 "Crimson Hideout" (camp), 1 "Scrapper Colony"
  (salvage), 2–3 caves, 4 "Black Orbit" (space).
- `Game_Builder.PlayerIsAt` (`WhereIsPlayer`: 0 Space, 1 PlanetSurface, 2 Dungeon, 3 Wormhole,
  4 StationTrans, 5 StationSubLevel), set through `Game_Builder:UpdatePlayerWhere`.
- A boss death fires the global event `ABossDied`; final and legendary bosses add a legend-key
  fragment (`GenerateLoots → AddKeyToLoot`). Vanilla changes no faction stat when a dungeon ends.

**Phase 2 plan: "the dungeon's boss died" = the dungeon is cleared.**

1. Post-hook `/Game/1Data/11_AI/Q1_Shooter_AI.Q1_Shooter_AI_C:OnDeadEvent` (already hooked by
   HTR). The callback reads `IsBoss` and returns for every other NPC. For a boss it reads
   `FinalBoss?`, `LegandBoss?`, `Level`, `Raider?`, `Robot?` and **queues**; nothing else runs in
   the fight. (`Q1_Boss_C` has `IsBoss = true`; mini-bosses do not.)
2. Post-hook `/Game/11Misc/1_1_1_HalilAICreature/BP_Creatures/Q1_BP_Creature.Q1_BP_Creature_C:OnDead`
   for cave creature bosses (`IsBoss?`).
3. Five seconds later, the 1 s loop handles the queue: it counts the boss if `PlayerIsAt` is
   Dungeon or PlanetSurface, or if the boss is flagged final/legendary. The system is
   `CurrentSolarID`; a pirate boss (`Raider?`) in a pirate-held system counts against the owner.
   Level factor: up to ×1.5 when the boss is above the system level
   (`CurrentSystemData.Systemlevel_53_…`).
4. Dedup: one dungeon per system per 7 game days (key `dungeon:<SystemID>`), since the dungeon's
   own ID is native. Phase 0 tries `GetDungeons()` from Lua: if the array comes back, the key
   becomes `SystemID|DungeonName|DungeonType` and the `bCleared` flags can confirm the clear.
5. On-foot contracts that send you into a generated dungeon (`Foot_*` types 14–20) also count
   as missions through `CompleteQuest` (3.3); the per-system daily budget keeps the two from
   stacking up.

Also available, weaker: `Game_Builder:OnAreaCleared(AreaTag)` (no decompiled caller),
treasure-chest interaction (`TreausreChest_C:Interact`, `Q1Controller:CreateAndHandleLootWidget`).

**Phase 0 must decompile `/Game/1Galaxy/1_CPP_Dungeons/`** (tools/sb2dump) to look for a
Blueprint "floor cleared" or "dungeon completed" event, which would be a better hook than the
boss death.

### 3.2 Sales

**Shop items** (weapons, modules, salvage…), `/Game/1Data/Bazaar/Widgets/Shop_Widget`:

- Flow of one sale (in the shop's event graph): `SoldItem` (S_Item_Data) and `Amount` are set →
  `Game_Builder:RemoveItemAtIndex` → `CalculateCut(SoldItem)` → `Game_Builder:Add Remove Money(Amount
  × Final)` → **`self.Bought_Slot.UpdateItem(Icon, Name, Sell?=true, PriceText)`**.
- Hook: post-hook **`/Game/1Data/Bazaar/Widgets/Bought_Slot.Bought_Slot_C:UpdateItem`**. It is a
  Blueprint custom event, called only by the shop: once per sale (`Sell?` = true) and once per
  purchase (false). At that moment `Shop_Widget.SoldItem` and `.Amount` still hold the sale (Amount
  is reset to 1 after). The shop is reached through the toast's outer chain (Bought_Slot →
  WidgetTree → Shop_Widget), to verify.
- Price received: `Value / 1.4` per unit (`CalculateCut`; ores pay the miners' guild a cut).
- The shop has no faction. The buyer is **the owner of the current system**
  (`Game_Builder.CurrentSolarID` → `FindSystemOwner`). `Shop_Widget.MarketWidget` gives the market
  type (0 Weapon, 1 Upgrades, 2 GeneralMerchant, 3 Ship, 4 HandWeapons).
- "Sell all" (`SellAllInterface`) only sells types 0 Garbage, 4 Mine (ore) and 5 UsableModule:
  ignored.

Item types (`Item_Types1`, `S_Item_Data.Type_10_…`) and how strategic they are. A sale earns
`weight × credits/10 000 × 150` Faction Power (at most 600 per sale) and
`weight × credits/10 000 × 0.8` influence for the system's ruler (at most 1.5):

| Byte | Type | Strategic weight |
|---|---|---|
| 0 | Garbage | 0 |
| 1 | Weapon (ship weapon) | 1.0 |
| 2 | Module (ship module) | 0.6 |
| 3 | UpgradeComponent | 0.4 |
| 4 | Mine (ore) | 0 |
| 5 | UsableModule | 0 |
| 6 | Wreck (salvage) | 0.6 |
| 7 | Rockets | 0.8 |
| 8 | Probes | 0.1 |
| 9 | MisactorTools | 0 |
| 10 | QuestItem | 0 |
| 11 | CargoCrate | 0 |
| 12 | HandWeapon | 0.6 |
| 13 | Granade | 0.5 |
| 14 | Ammo | 0.3 |
| 15 | Suit | 0.4 |
| 16 | Compax | 0 |
| 17 | SuitModule | 0.3 |
| 18 | CombatDrone | 0.8 |
| 19 | TradeGoods | 0 (commodities below) |

There is no contraband flag on items. "Contraband" is modelled by *where* you sell: selling
weapons in a pirate-held system strengthens the pirates there, **but only slightly** (author's
choice): Power and influence × 0.5 (`Sales.PirateFactor`).

**Commodities** (trade goods, Phase 3): the trade terminal (`1Widgets/TradeMain/TradeMarket`) calls
`Game_Builder:Reduce/ Add Stock From Sector(GridIndex, ItemIndex, BuyAmount, out OutData)` with a
negative amount when you sell. It is the player-only variant (AI trade uses `…_Auto`).
`OutData.SolarID_26_…` gives the system. The function name contains `/` and spaces: check that
RegisterHook accepts it.

### 3.3 Missions

- **Every** quest that uses `S_Quest_Info_1` (contracts, bounties, guild and side quests,
  operations, mail quests) succeeds through **`Game_Builder_C:CompleteQuest(Tag, Fail?, out
  Completed?)`**, called with `Fail? = false` only from `CompleteSubGoal`. Post-hook: success when
  `Completed? == true` and `Fail? == false`. The quest has then moved from `AllQuests` to
  `CompletedQuests`; the mod finds it there by `Contract_Tag_36_…` (search from the end).
  - Risk: it is a Blueprint-to-Blueprint call inside `Game_Builder`. UE4SS hooks fire for those
    in HTR's experience, but this must be checked once.
  - Fallback: `CompleteSubGoal(QuestTag, GoalIndex, out Complete?)` and check that the tag left
    `AllQuests`.
- `Game_Builder_C:AddNewQuest(QuestToAdd, ForceToAdd?, NoCContractSpawner?, out QuestTtOAdd)` is
  hooked to remember, per final tag, what completion can no longer read (the bounty's faction:
  `BountyList[…].Faction_24_…` is deleted by `KillBounty` before completion).
- **Giver and target are not stored.** `GiverFaction_7_…` stays 0 for generated contracts, which
  would read as "Morthra" every time. Enemies in contracts are generic (pirates/raiders). So:
  - **place** = `SubGoals[0].Location_5_…` (a system ID; the generator picks a random system in
    your grid cell); **ruler** = that system's owner;
  - **kind of mission** decides the sign ("depends on the mission", author's choice):

    | Kind | Contract types | Ruler's influence | Relation |
    |---|---|---|---|
    | help | GuardAsteroid/Salvage (0.75), GuardConvoy/Trade/Base, Escord, SavePerson, JoinGuard, Foot_SavePerson, DLC_Help*, DLC_SaveSomeone | **+1.5 × w** (0 in a pirate-held system) | +2 |
    | strike | KillOne (0.75), KillMulti, ClearArea (1.25), DestroyBase (1.5), Capture_Person, JoinRaid (1.5), Foot_KillOne (0.75), Foot_Hack (0.5), Foot_DestroyCrates (0.5), Foot_Planet_* (1.0–1.5), DLC_Destroy* (1.25), DLC_GetItem (0.5) | enemies are pirates/raiders: **+1.5 × w** | +2 |
    | strike against the ruler | a strike in a pirate-held system, or a bounty on the ruler's faction | **−1.5 × w** | −2 |
    | your faction's operation | quest tag `Operation`; target = `Game_Builder.OperationData.OperationLocation_37_….StationSystemID` | **−1.5** | −2 |

  - Faction Power: 300 × w × (0.75 + 0.25 × difficulty tier 1–4), for every kind except
    operations (vanilla already pays those through battle summaries and castles).
- Skipped: main story quests (`C_Type` = MainQuest) and mail quests (`Mail?`): vanilla already
  pays Power for both.
- Dedup key: `Contract_Tag` + `AcceptedTime_50_…` (random tags can collide).
- Not covered: mining contracts and freelancer mail missions (they do not go through
  `CompleteQuest`).

### 3.4 Dominance recalculation

Post-hook `Game_Builder_C:CalculateDominance(System, …)`: the mod writes its line for that
system again (with fading applied). Free cache refresh: `self` is the Game_Builder.

## 4. The model

### 4.1 Who gains, who loses

| Deed | **Faction Power** (yours) | Ruler's local influence | Relation with the ruler |
|---|---|---|---|
| Clear a dungeon (its boss dies: pirates, raiders, robots, creatures) | **+600**; a boss above the system's level up to ×1.5 | +3 (2 + 1 boss) | +1 |
| … a pirate base in a pirate-held system (you raided the ruler) | **+600** | −1.5 | 0 |
| Sell strategic goods (table 3.2) | **weight × 150 per 10 000 credits**, at most 600 per sale | weight × 0.8 per 10 000, at most +1.5 | — |
| … in a pirate-held system | × 0.5 | the pirates gain, × 0.5 | — |
| Mission that helps the ruler or clears criminals from its space | **300 × w × (0.75 + 0.25 × tier)** | +1.5 × w | +2 |
| Mission against the ruler (pirate-held system, bounty on its faction) | **300 × w × (0.75 + 0.25 × tier)** | −1.5 × w | −2 |
| Your faction's operation against a system | vanilla pays it | −1.5 | −2 |

Faction Power is the reward; influence and relations are the consequences. Influence is in
the game's own dominance points and always applies to **the family that owns the system** at
the time (your own faction included). If the owner changes, the mod's line in that system
starts again from 0: local support for the old ruler does not pass to a conqueror.

### 4.2 Diminishing returns

Nobody flips the galaxy in an hour (= 6 game days):

1. **Cap per system:** the mod's line stays within ±25 % of the system's `StartDominance`,
   clamped to 3–20 points (8 if unknown). A system of 60 points: ±15 at most.
2. **Saturation:** each deed moves the line by `raw × (1 − current/cap)` in the same direction.
   The tenth dungeon in the same system barely counts.
3. **Fading:** the line fades by half every 30 game days (~5 h of play). Favors and grudges are
   forgotten unless renewed.
4. **Daily budgets:** at most **2 000 Faction Power** per game day (~12 000 per hour of play);
   at most 3 influence points per system and 5 per parent faction (galaxy-wide) per game day;
   at most 4 relation per family per day.
5. **Market saturation:** items of the same kind sold in the same system on the same day count
   1, 1/2, 1/3… (after 50 000, 100 000… credits). Applies to Power and influence.
6. **No repeats:** a dungeon in the same system counts again only after 7 days; a quest once.

Worked example, one hour of play (6 game days):

- 2 dungeons in 2 Falron systems: 2 × 600 = **1 200 Power**; each ruler +3.
- 200 000 credits of ship weapons sold in one system, in 10 sales: market saturation brings
  10 × 300 down to about **1 340 Power**; that ruler +1.5 per sale, stopped by the daily budget
  (3) and the cap.
- 5 contracts of tier 2 there: 5 × 375 = **1 875 Power**; +1.5 each, budget-limited.

About **4 400 Faction Power**: a station costs 10 000–30 000, so deeds pay for one every few
hours, on top of vanilla income. The busiest system's line ends around +11 of a ±15 cap: its
ruler's hold grows by about a fifth and nothing changes hands. Strikes against a rival
(bounties on its faction, your operations, raids in its space) lower its line toward −15; if the
system was near its raid threshold, your faction can now raid it.

### 4.3 Formulas (fp/model.lua)

```
cap      = clamp(StartDominance × CapFraction, CapMin, CapMax)
decay    = p × 0.5^(Δdays / HalfLifeDays)
fatigue  = 1 / (1 + units sold of that kind, in that system, today / FatigueScale)
power    = min(deed power × fatigue, what is left of FactionPowerPerDay)
raw      = deed influence × fatigue → per-system budget → per-faction budget
step     = raw × max(0, 1 − max(0, ±p)/cap)          (± = same direction as raw)
p        = clamp(p + step, −cap, cap)
relation = deed relation, within RelationPerDay per family
```

## 5. Hooks and calls

| Purpose | Kind | Path / call | Notes |
|---|---|---|---|
| Re-apply line after recalculation | post-hook | `/Game/1Data/Game_Builder.Game_Builder_C:CalculateDominance` | `(System, GameStartCalculete, out …)` |
| Quest accepted | post-hook | `…Game_Builder_C:AddNewQuest` | read final tag from `QuestTtOAdd` |
| Quest done | post-hook | `…Game_Builder_C:CompleteQuest` | `(Tag, Fail?, out Completed?)` |
| Shop sale | post-hook | `/Game/1Data/Bazaar/Widgets/Bought_Slot.Bought_Slot_C:UpdateItem` | `Sell?` = true |
| Commodity sale (Phase 3) | post-hook | `…Game_Builder_C:Reduce/ Add Stock From Sector` | `BuyAmount < 0` |
| Dungeon boss died | post-hook | `/Game/1Data/11_AI/Q1_Shooter_AI.Q1_Shooter_AI_C:OnDeadEvent` | reads `IsBoss` only, queues |
| Cave boss died | post-hook | `/Game/11Misc/1_1_1_HalilAICreature/BP_Creatures/Q1_BP_Creature.Q1_BP_Creature_C:OnDead` | `IsBoss?` |
| Where the player is | read | `Game_Builder.PlayerIsAt` | 2 = Dungeon |
| System owner | call | `FamilyManager:FindSystemOwner(FName SystemID) → FName` | native, returns directly |
| Owner's faction | call | `FamilyManager:GetFamilyByID(FName, out Families) → bool` | out parameter: verify |
| Cap base | call | `FamilyManager:GetDominanceDataOfSystem(FName, out FamilyDominanceInSystem) → bool` | out parameter: verify |
| Write the line | call | `FamilyManager:AddDominanceVariableToSystem(FName, {ID, Name, Type, Point})` | ID `FP_LocalSupport`, Name `Local support`, Type `FactionPower` |
| Faction Power | call | `Game_Builder:"Add Remove Faction Power"(Amount, out, out)` | positive only |
| Relations | call | `FamilyManager:UpdateDiplomaticRelations('WRA', FamilyID, delta, true)` | ± |
| Operation target | read | `Game_Builder.OperationData.OperationLocation_37_1D073FF24C820745ECF779BFC866D7CA.StationSystemID` | quest tag `Operation` |
| Current system | read | `Game_Builder.CurrentSolarID` | |
| Clock | read | `Game_Builder.CurrentGameTime` | 600 per day |
| Character | read | `Q1GameInstance.CharacterID` (fallback `CharacterName`) | keys the ledger |

Finding objects: hooks on Game_Builder give it as `self` (cached for free). Other hooks use
`GameplayStatics:GetPlayerController(self, 0).GameBuilderRef` (instant; `Q1Controller` holds
it). Only as a last resort one `FindFirstOf("Game_Builder_C")` (~50 ms) on a rare action (a
sale, a key press), at most once per 10 s. Cached, re-checked with `IsValid()`. The family manager comes from
`Game_Builder.FamilyManagerRef`. Never `GetAllActorsOfClass` (corrupts the Lua state in UE4SS
3.0.1).

## 6. Save safety

The user's saves must never be corrupted.

1. **Off by default.** Nothing is written to the game until the player switches the mod on.
2. **Only the game's own functions** change saved data (the four calls in section 5). The mod
   never writes a saved struct, array or property directly.
3. **Small and bounded:** one line per system, |value| ≤ 20 points (a system has 30–100);
   at most 2 000 Faction Power per game day, positive only (the mod never spends your Power);
   relations ±4 per family per day, and the game clamps to −100..100.
4. **The mod's memory is its own file**, `ledger-<CharacterID>.lua` in the mod folder, written
   at most every 30 s, through a `.tmp` file, keeping a `.bak`. A broken ledger is set aside
   (`.broken`) and a new one started; the game is not affected.
5. **Older saves:** the ledger journals its last 400 changes with the game day. If the game clock
   is earlier than the ledger's last day (an older save was loaded), the mod undoes its own
   bookkeeping for the "future" days and writes the lines again. Power and relations live in
   the game's save, so loading the older save already restored them. A clock of 0, or an earlier
   clock seen on fewer than 3 ticks in a row, is ignored, so a value read mid-load never rolls
   anything back. The ledger follows the loaded character (`CharacterID`).
6. **Reversible:** `Cleanup = true` in config sets every line the mod wrote to 0 for each
   character you load, and no new deeds count meanwhile. Uninstall: run cleanup, then delete the
   folder.
7. **Backups:** before its first write for a character, the mod copies the loaded save file
   (read-only on the original; the save folder and `Q1GameInstance.LoadSaveFile` give the name,
   to locate in Phase 0) to `<mod>\backups\`. The README tells players to back up saves before
   the first use.
8. **No writes during loading:** effects only follow Blueprint events that happen in play; the
   1 s loop only writes during an explicit cleanup.
9. **Testing** (Phase 0–2) is done on a copy of a save with a throwaway character.

Open point: if the mod is removed *without* cleanup, its lines stay in the save, frozen. If
Phase 0 shows that the game drops unknown lines on its own recalculation, removal cleans
itself.

## 7. HUD feedback

- One short line per counted deed, on the HUD warning channel HTR verified on foot
  (`pawn:TMWPerkWarning(FText)`; in a ship the cursor warning):
  `+600 Faction Power, Falron local support +3.0, relation with Falron +1 (dungeon cleared)`.
  Influence changes below 0.1 are not shown. The game's own Power counter in the main widget
  updates too (`PowerUpdated` event).
- The game's own system resistance window shows the line **Local support** with its points,
  next to planets and trade routes.
- Toggle key (**Shift+F9**): on/off message; switching on also shows your Faction Power, the
  current system, its ruler and faction, the mod's line and its cap. An extra status key can
  be set in config (none by default).

## 8. Config and keys

`scripts/config.lua`: `Enabled = false` (master switch); `ToggleKey`/`ToggleModifiers`,
`StatusKey`/`StatusModifiers`; `Channels` (FactionPower, Influence, Relations — all on);
`Sources` (Dungeons, Sales, Commodities=false, Missions); per-source amounts (`Dungeon`,
`Sales.Strategic` weights and rates, `Missions`); `Limits` (Power per day, cap, fading,
budgets, repeats); `Hud`; `Cleanup`; `Debug`. On/off is remembered in `state.txt`, like HTR.

**Shared key plan of the realism set, revision 2 (laptop-safe)** — coordinated by this session
with the sibling sessions; master copy in the sessions' shared notes, `key-plan.md`.

- The game binds F1/F2/F5 (squad orders on foot; F3/F4 are free on foot; F1–F5 are fleet
  orders in ships), **F6 quick save,
  F8 quick load, F10 bug report**, F12 (Steam screenshot), and Insert/Home/End/PageUp/PageDown in
  some camera contexts. Laptops often lack the navigation keys.
- On foot **Ctrl alone opens the map** and **Alt crouches**; Shift runs only while moving. So
  **Shift is the only modifier**.
- Verified in game for HTR 0.4.4: UE4SS matches modifiers exactly, so a plain bind does not
  fire while Shift is held, and a `{ModifierKey.SHIFT}` bind fires on Shift+key. So
  Shift+<a key another mod binds plain> is usable (every mod also guards its plain binds).

| Key | Mod |
|---|---|
| F7 / Shift+F7 / F9 / F11 | HTR (mode / gear bonus / ships / slow perks) |
| **Shift+F9** | **Faction Power** on/off |
| Shift+F11 | Tactical FPS |
| F3 / F4 / Shift+F4 | Stealth (on foot only) |
| Delete | Engineering Turrets |
| Shift+Delete | Gear Any Level |
| Shift+F3 | spare (on foot only) |

Keys that may be pressed anywhere (on/off toggles) use only F7, F9, F11 or Delete, which the
game binds nowhere.

The mod refuses F1, F2, F5, F6, F8, F10, F12 and the Ctrl/Alt modifiers even if config asks.

## 9. Performance

- All hooks fire on rare events: a quest finishing, a sale, a system window opening, a dungeon
  end. None runs per frame. Callbacks do a few property reads and at most three native calls.
- No `FindAllOf`. `FindFirstOf` only on rare player actions, at most once per 10 s, never in the
  1 s loop or in combat code.
- Missing classes are probed with the HTR back-off (1–16 s, one miss per poll, ~37 ms each),
  and only while the mod is on. The shop toast class is only loaded at a shop.
- The 1 s loop reads cached values only; the ledger is a few kB, written at most every 30 s.
- If a dungeon hook needs NPC deaths (`Q1_Shooter_AI_C:OnDeadEvent`, also used by HTR), the
  callback must stay under 0.1 ms: read one flag, return.
- Watchdog: callbacks slower than 8 ms are logged (same as HTR). **Frame times are measured in
  game before any release.**

## 10. Risks and unknowns

| # | Unknown | Effect if wrong | How Phase 0 settles it |
|---|---|---|---|
| R1 | `AddDominanceVariableToSystem` replaces a line with the same ID | duplicates pile up | call twice, read the list |
| R2 | `CalculateDominance` keeps or drops foreign lines | line vanishes until re-applied; first window shows old data | open the window, read the list |
| R3 | `StartDominance` re-snapshotted while the line exists | the line becomes part of the baseline | watch `StartDominance` across days |
| R4 | AI picks raid targets by dominance | if not, the effect is mostly on your own raids and the UI | compare AI attacks on lowered systems (long test) |
| R5 | Out parameters of native calls from Lua | `GetFamilyByID` / `GetDominanceDataOfSystem` unusable | REPL; fallback: cap 8, parent from `CurrentSystemData.Faction_7_…` byte |
| R6 | `CompleteQuest` hook fires on its local call | missions never count | finish one contract |
| R7 | Bought_Slot → Shop_Widget outer chain | sales never count | sell one item |
| R8 | `UpdateDiplomaticRelations` bool = add | relations set instead of shifted | REPL on a test save |
| R9 | `Factions` byte table | wrong bounty targets | REPL: read a few systems |
| R10 | `"Add Remove Faction Power"` callable from Lua with out params | Power channel dead | REPL |
| R11 | Dominance data saved and restored | line lost or kept after reload | save, reload, read |
| R12 | Dungeon bosses carry `IsBoss` / `FinalBoss?`; C++ dungeons set `PlayerIsAt` = 2 | dungeons not counted, or other bosses counted | kill a dungeon boss and a field boss |
| R13 | `GetDungeons()` returns its array to Lua | weaker dedup (per system) | REPL |

## 11. Phased plan

- **Phase 0 — probe (dev REPL, test save only).** Decompile `/Game/1Galaxy/1_CPP_Dungeons/` and
  `/Game/1_Tests/DungeonFlow/` (offline, no game needed). Read-only checks of every name in
  `fp/gamedefs.lua`; R1–R13 above; locate the save folder for backups. One reversible write: add
  the line to one system, read it, set it to 0.
- **Phase 1 — core.** Ledger, model, Faction Power payouts, the dominance line, relations,
  re-apply hook, HUD, keys, cleanup, save backup on first write, missions (`CompleteQuest`,
  operations). Off by default. Frame-time test.
- **Phase 2 — more deeds.** Shop sales, dungeons, bounty faction cache.
- **Phase 3 — extras.** Commodities, status key polish.
- **Phase 4 — optional.** War-end events (`BP_OnWarConcluded`), integration in the set installer,
  Nexus/Steam docs.
- **Release gate:** every Phase 0 item green, frame times measured, save/reload/cleanup test
  passed, README and config documented.

## 12. In-game test plan

Use a copy of a save and a throwaway character. Back up the save folder first.

1. **Load:** mod off → no hooks, `factionpower.log` only has the load line. Shift+F9 → "ON" with
   the status line, hooks register on demand, no stutter (watch frame times for a minute in a
   station and in space). Shift+F9 does not also toggle HTR's ships (plain F9).
2. **Probe:** via the REPL, read `CurrentSolarID`, `FindSystemOwner`, `GetFamilyByID`,
   `GetDominanceDataOfSystem` for the current system; print the dominance lines.
3. **Line write:** `AddDominanceVariableToSystem` with `Point = 2` → open the system window: one
   "Local support +2" line; write `Point = 3` → still one line (R1). Reopen the window (R2).
4. **Mission:** take and finish a guard contract in a Falron system → HUD line, the game's
   Power counter grows, relation +2, the window shows the new value. A strike contract in a
   pirate-held system → the pirates' line goes down, relation −2. Fail a contract → nothing.
5. **Sale:** sell a ship weapon at a station → HUD line with Power; sell junk → nothing; sell 10
   weapons in a row → each counts less (fatigue); in a pirate system → half; buy → nothing.
6. **Dungeon:** clear a pirate dungeon → HUD line once (+600 Power); clear another in the same
   system the same day → nothing.
7. **Budgets:** repeat deeds until 2 000 Power in one game day → further deeds give no Power;
   same for the per-system influence budget.
8. **Fading:** wait one game day (10 min) → the line shrinks a little (1/30 of a half-life).
9. **Save/reload:** save, quit to menu, reload → the line is still there (R11); load an older
   save → the ledger rolls back (log line) and the window shows the older value.
10. **Cleanup:** `Cleanup = true`, load → every line 0, no deed counts; set it back to false.
11. **Frame times:** compare with the mod off: station, space battle, dungeon fight; no hook in
    the watchdog log.

## 13. Decisions and open questions

Decided by the author (2026-10-30):

1. "Faction power" = the **Faction Power currency**. It is the main effect; influence and
   relations are consequences.
2. Missions may **lower** a rival's hold, depending on the mission (table in 3.3).
3. Selling weapons in a pirate-held system strengthens the pirates **slightly** (× 0.5).
4. Speed: cap ±25 %, half-life ~5 h of play, 3 influence points per system per day: **OK**.
5. Keys: coordinate with the other mods of the set, laptop-safe (section 8): Shift+F9.
6. **Diplomatic relations on** (realism).

Still open:

1. **Strategic items and weights** (table in 3.2): no answer yet; the defaults stand.
2. **Power amounts** (600 per dungeon, 300 per mission, 150 per 10 000 credits, 2 000 per game
   day): calibrate in Phase 0 against a real station's `DailyPowerIncome`.
3. **Before founding a faction:** should deeds already earn Power (vanilla story missions do),
   or only once your faction exists?
4. **Uninstall:** cleanup step acceptable, or should the line vanish on its own (only possible
   if the game drops it — R2)? Faction Power already earned stays either way.

## 14. Status / next steps (paused 2026-10-30 22:00)

Paused at the user's request (usage limit), right after the first in-game probe.

**Done since the groundwork**
- Dungeon logic decompiled offline (`/Game/1Galaxy/1_CPP_Dungeons`, `/Game/1_Tests/DungeonFlow`):
  the real end-of-floor moment is `Q1_DungeonManager_C:InteractedWithDoor(DoorRole, DoorRef)`
  with role 2 (the manager then calls native `CurrentFloorCleared()`); `GetCurrentDungeon()` /
  `GetCurrentFloor()` give `DungeonID`, `DungeonType`, `DungeonLevel`, `SystemID`, `Floors[]`
  (`FloorIndex`, `bIsBossLevel`, `bCleared`). Wired in `sources.lua` (`S.onDungeonDoor`), boss
  death kept as fallback; both share the dedup key `dungeon:<system>`.
- Hooks register at the main menu without errors: quest completed, shop sale, dungeon floor
  cleared, boss death, creature boss death (factionpower.log, run 1).
- Probe 1 (read-only, test slot `FPTest` from the pretest CheckPoint backup):
  - `PlayerController.GameBuilderRef` works; `CurrentSolarID` = "116", `FindSystemOwner` = "Shadow",
    `FactionPower` = 8963, `CurrentGameTime` 89207 → `Day` 148 (600 per day confirmed).
  - **Out parameters of native calls:** the Lua table passed is filled with the struct's fields
    directly (`out.StartDominance`, `out.FamilyParentType`, ...), not under `out.OutData` /
    `out.OutFamily`. Arrays come back as Lua tables of params (use `:get()` per element).
    StartDominance 50.8, RaidRequiredDominance 30.8, total 50.8, 5 dominance lines.
  - **`Q1GameInstance.CharacterID` is None and `CharacterName` empty** on this save: the ledger
    needs another key.
- Save safety procedure used and verified: full copy of `SaveGames` (`SB2Realism_SaveBackup_20261030_fptest`),
  SHA-256 of every file before; after the run the test slot and the game's own
  `SB2Backups\FPTest_bak1*` were deleted, and all 68 files matched the hashes. mods.txt restored.

**Next (on resume)**
1. `world.lua`: read out-params from the table itself (`out.StartDominance`, `out.FamilyParentType`),
   keeping `OutData`/`OutFamily` as fallback.
2. Ledger key: CharacterID is empty → use the player faction's name (`Game_Builder.PlayerFactionData`)
   or the save slot (`Q1GameInstance.LoadSaveFile`) + rollback by game clock; decide after probe 2.
3. Probe 2 (`fp_probe2.lua`, refuses any slot but FPTest): dominance line write/replace (R1),
   survival of `CalculateDominance` (R2), `Add Remove Faction Power` from Lua (R10),
   `UpdateDiplomaticRelations` bool (R8).
4. Deed tests in the test slot (mission, sale, dungeon door), HUD, Shift+F9 via keybd_event with
   the game in the foreground, frame times mod on vs off (SB2HOTAS : 0).
5. Save isolation check again (hashes), then package (repo `hubertdungen/SpaceBourne2-FactionPower`,
   banner `Faction Power - v2.png`, README links to HTR mods/4, Split Controls mods/5, Silent Ops
   mods/6, Gear Without Levels mods/7), and ask the user for the final "sim" before publishing.

Test procedure for every run: check no SpaceBourne 2 / SB2-HOTAS process runs; message Tactical
Engineering "taking the game"; copy + hash `SaveGames`; create `FPTest*` from
`SB2Realism_SaveBackup_20261030_pretest\CheckPoint*`; install `FactionPower` + `SB2DevRepl` in
Mods and set mods.txt; afterwards close the game, restore mods.txt, remove both mods, delete
`FPTest*` and `SB2Backups\FPTest_bak*`, re-hash, message "game free".

## 15. Test results, 0.1.0 (2026-10-31, test slot FPTest, Steam install)

Procedure as in §14 (saves copied and hashed before; afterwards the test slot and the game's
`SB2Backups\FPTest_bak1*` deleted; all 81 save files byte-identical; mods.txt restored).

| Item | Result |
|---|---|
| R1 `AddDominanceVariableToSystem` | **appends** (2 then 3 → two lines). The mod now recalculates the system first, then adds one line |
| R2 `CalculateDominance` | **rebuilds the list and drops foreign lines**. Re-added once after every recalculation (post-hook); uninstall cleans itself |
| R3 StartDominance | unchanged by the line (50.8 before and after) |
| R5 native out params | the passed table gets the struct's fields directly; arrays as tables of params |
| R6 `CompleteQuest` hook on the internal call from `CompleteSubGoal` | **fires**. But `Completed?` reads false in the post-hook even on success → success = not `Fail?` and the quest is in `CompletedQuests` |
| R8 `UpdateDiplomaticRelations(..., 1, true)` | additive (−6 → −5) |
| R10 `"Add Remove Faction Power"` from Lua | works (8963 → 9063) |
| Ledger key | `CharacterID` empty on this save → falls back to `slot_<LoadSaveFile>` |
| Side quest (KillOne, system 651, Troccits/Xeghan) | +225 Power, +1.12 local support, relation +2; mail contract skipped (vanilla paid +1062) |
| Debug deeds in pirate system 116 | +100 Power each, influence +1.00 then +0.92 (saturation) |
| Ledger vs game | one line per system, values equal (1.92 / 1.12), totals +1.92 / +1.12 |
| Shift+F9 | toggles the mod; HTR's plain F9 (ships) unchanged |
| Frames, on foot, 20 s | mod on: median 22.0 ms, p99 36 ms, 0 spikes; mod off: median 23.0 ms, p99 41 ms, 0 spikes |
| Slow hook | one 9 ms call on the first quest completion (opens the ledger, recalculates the system); out of combat |

Not yet seen in game: shop sale toast hook, dungeon door / boss death, the HUD line on screen,
bounty target faction (not cached yet), commodities (not wired).
