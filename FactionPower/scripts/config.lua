--[[
  Faction Power (SpaceBourne 2) - USER SETTINGS
  =============================================
  Edit with any text editor, then restart the game. Delete a line to use its default.
  On by default: press Shift+F9 in game to switch the mod off or on (remembered).

  What the mod does (see README.md / DESIGN.md):
    clearing dungeons, selling strategic goods and finishing missions earn your faction
    FACTION POWER, the game's own currency for operations, stations and houses.
    The same deeds also shift the local influence (the game's "dominance") of the family
    that rules the system, and your relations with it. Slowly, with diminishing returns.

  Scale: vanilla Power costs are in the thousands (a house 10 000 x houses you own, a
  station 10 000-30 000, a change of path 35 000). One game day = about 10 minutes of play.
  Influence uses the game's dominance points (a system totals roughly 30-100).
]]

return {
    -- Starting state (Shift+F9 switches it in game; the choice is remembered in state.txt).
    Enabled = true,
    -- Keys (UE4SS key names). Shared, laptop-safe key plan of the realism set: DESIGN.md
    -- section 8. Only "SHIFT" as a modifier (on foot Ctrl opens the map, Alt crouches).
    -- Never F1, F2, F5 (squad orders), F6 (quick save), F8 (quick load), F10 (bug report), F12.
    ToggleKey = "F9", ToggleModifiers = { "SHIFT" }, -- Shift+F9: mod on/off (remembered); switching
                                                     -- on also shows your Power and the balance here
    StatusKey = "", StatusModifiers = { "SHIFT" },   -- optional extra status key ("" = none)

    -- What your deeds change.
    Channels = {
        FactionPower = true, -- your faction's Power (the main effect)
        Influence    = true, -- local influence of the family that rules the system ("Local support"
                             -- line in the game's own system resistance window)
        Relations    = true, -- relation between your faction and that family
    },

    -- Which deeds count.
    Sources = {
        Dungeons    = true,  -- a dungeon's boss dies (pirate camp, scrapper colony, cave, ...)
        Sales       = true,  -- selling strategic items at a shop
        Commodities = false, -- selling trade goods at a commodity market (phase 3)
        Missions    = true,  -- contracts, bounties, guild and side quests, operations
    },

    Dungeon = {
        FactionPower = 600,   -- prestige, recruits and salvage for your faction
        Influence    = 2.0,   -- the system's ruler holds it better (+1 more for the boss)
        BossBonus    = 1.0,
        OwnerHostile = -1.5,  -- a pirate base in a pirate-held system: the pirates there weaken
        Relation     = 1,     -- with the system's ruler
        LevelScale   = true,  -- a boss above the system's level counts more, up to x1.5
    },

    Sales = {
        -- How strategic each item type is (0 = not at all). Applied to the two rates below.
        Strategic = {
            Weapon = 1.0, Rockets = 0.8, CombatDrone = 0.8, Module = 0.6, Wreck = 0.6, HandWeapon = 0.6,
            Granade = 0.5, UpgradeComponent = 0.4, Suit = 0.4, SuitModule = 0.3, Ammo = 0.3, Probes = 0.1,
        },
        FactionPowerPerTenThousand = 150, -- Power per 10 000 credits of a fully strategic item
        InfluencePerTenThousand    = 0.8, -- the buyer's local influence, same basis
        MaxPowerPerSale     = 600,
        MaxInfluencePerSale = 1.5,
        PirateFactor        = 0.5,  -- selling in a pirate-held system: the pirates gain, but only slightly
    },

    Commodities = {
        -- phase 3: trade goods are not strategic; a little influence for the buyer only
        InfluencePerTenThousand = 0.2,
    },

    Missions = {
        FactionPower    = 300,  -- per mission, times the type weight and the difficulty tier (DESIGN.md 3.3)
        HelpInfluence   = 1.5,  -- you protected the ruler's space (guard, escort, rescue...)
        StrikeInfluence = 1.5,  -- you cleared criminals from the ruler's space (kill, clear, destroy...)
        HostileInfluence = -1.5, -- the target was the ruler itself (a pirate-held system, a bounty on
                                 -- the ruler's faction, your faction's operation against it)
        Relation        = 2,    -- with the ruler you helped (minus this when you acted against it)
    },

    -- Diminishing returns: nobody flips the galaxy in an hour of play.
    Limits = {
        GameTimePerDay  = 600,  -- game clock units per game day (the game's own value)
        FactionPowerPerDay = 2000, -- most Power the mod adds per game day (~12 000 per hour of play)
        CapFraction     = 0.25, -- the mod's influence in a system stays within +-25 % of the
        CapMin          = 3,    -- system's starting dominance, and between these bounds
        CapMax          = 20,
        CapDefault      = 8,    -- when the starting dominance cannot be read
        HalfLifeDays    = 30,   -- influence fades by half in 30 game days (~5 h of play)
        DailyPerSystem  = 3,    -- most influence one system can gain or lose per game day
        DailyPerFaction = 5,    -- most influence one faction can gain or lose per game day, galaxy-wide
        FatigueScale    = 5,    -- same kind of item sold in one system on one day: after 50 000
                                -- credits the next sale counts 1/2, after 100 000 1/3 ...
        RepeatDays      = 7,    -- the same dungeon (system) counts again only after this many days
        RelationPerDay  = 4,    -- most relation change per family per game day
        JournalSize     = 400,  -- remembered deeds (to undo them if you load an older save)
    },

    Hud = {
        Notify   = true,  -- one short line on the HUD when a deed counts
        MinShown = 0.1,   -- smaller influence changes are not announced
    },

    -- Removal helper: set true, start the game and load each of your characters once. The mod
    -- sets its influence line to 0 in every system it touched (no new deeds count meanwhile).
    -- Faction Power already earned stays: it is yours. Then set it back to false, or delete the mod.
    Cleanup = false,

    Debug = {
        Log        = false, -- write FactionPower\factionpower.log (and accept debug_cmd.txt:
                            -- "test" applies a small test deed where you are, "status", "on", "off")
        SlowHookMs = 8,
    },
}
