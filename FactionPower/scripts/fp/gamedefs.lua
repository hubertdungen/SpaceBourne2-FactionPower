--[[
  Every SpaceBourne 2 internal name Faction Power depends on lives in this file.
  When a game update renames something, this is the only file to fix.
  Names come from the decompiled Blueprints (UE 4.27, build of 2026-10-26).
  Verified in game (2026-10-31): Game_Builder hooks, CompleteQuest, the family manager calls,
  the dominance line, Faction Power, relations. Not yet seen firing: shop toast, dungeon door,
  boss deaths (DESIGN.md section 14).
]]

local G = {}

-- Classes ---------------------------------------------------------------------
G.GameBuilder   = "/Game/1Data/Game_Builder.Game_Builder_C"     -- world/stat manager (one per session)
G.FamilyManager = "/Game/1Data/Q1FamiliyManager_BP.Q1FamiliyManager_BP_C" -- BP child of native /Script/SB2.Q1FamilyManager
G.ShopWidget    = "/Game/1Data/Bazaar/Widgets/Shop_Widget.Shop_Widget_C"
G.BoughtSlot    = "/Game/1Data/Bazaar/Widgets/Bought_Slot.Bought_Slot_C" -- "sold/bought" toast inside the shop
G.Shooter       = "/Game/1Data/11_AI/Q1_Shooter_AI.Q1_Shooter_AI_C"     -- every on-foot NPC with a gun

-- Short class names for FindFirstOf (rare lookups only, ~50 ms each)
G.GameBuilderShort   = "Game_Builder_C"
G.FamilyManagerShort = "Q1FamiliyManager_BP_C"
G.GameInstanceShort  = "Q1GameInstance_C"

-- Hooked Blueprint functions (post-hooks) -------------------------------------
G.Fn = {
    -- Dominance recalculation (runs when a system/faction window opens): re-apply our line after it.
    -- (System:Name, GameStartCalculete:Bool, out RaidRequiredValue, out OutData, out L_StationCount1)
    CalculateDominance = G.GameBuilder .. ":CalculateDominance",
    -- Every quest success/failure: (Tag:Str, Fail?:Bool, out Completed?:Bool)
    CompleteQuest      = G.GameBuilder .. ":CompleteQuest",
    -- Quest accepted: (QuestToAdd:S_Quest_Info_1, ForceToAdd?:Bool, NoCContractSpawner?:Bool, out QuestTtOAdd)
    AddNewQuest        = G.GameBuilder .. ":AddNewQuest",
    -- Shop sale/purchase toast: (Texture, InText:Text, Sell?:Bool, Price:Text); Sell? = true on a sale
    ShopToast          = G.BoughtSlot .. ":UpdateItem",
    -- Commodity market stock change: (GridIndex, ItemIndex, BuyAmount (<0 = player sold), out OutData)
    -- Phase 3. The name contains '/' and spaces: check that RegisterHook accepts it.
    SectorStock        = G.GameBuilder .. ":Reduce/ Add Stock From Sector",
    -- Dungeon floor done: the player uses a dungeon door; role 2 makes the manager call the
    -- native CurrentFloorCleared(). (DoorRole:ECPP_DungeonDoorRole, DoorRef:CPP_DungeonDoor)
    DungeonDoor        = "/Game/1Galaxy/1_CPP_Dungeons/Q1_DungeonManager.Q1_DungeonManager_C:InteractedWithDoor",
    -- Fallback for dungeons outside the dungeon manager (contract dungeons, surface dungeons):
    -- On-foot NPC death (HTR hooks the same function): () ; self = the NPC
    NpcDead            = G.Shooter .. ":OnDeadEvent",
    -- Cave creature death: () ; self = the creature
    CreatureDead       = "/Game/11Misc/1_1_1_HalilAICreature/BP_Creatures/Q1_BP_Creature.Q1_BP_Creature_C:OnDead",
    -- Called by name, not hooked:
    AddFactionPower    = "Add Remove Faction Power", -- Game_Builder: (Amount:Int, out Success?, out CurrentPower)
}

-- Properties (names exactly as in the Blueprints) -------------------------------
G.P = {
    -- Game_Builder
    FamilyManagerRef = "FamilyManagerRef", CurrentSolarID = "CurrentSolarID", GameTime = "CurrentGameTime",
    Day = "Day", FactionPower = "FactionPower", AllQuests = "AllQuests", CompletedQuests = "CompletedQuests",
    BountyList = "BountyList", PlayerIsAt = "PlayerIsAt", -- WhereIsPlayer below
    -- Q1_Shooter_AI_C (bosses: Q1_Boss_C has IsBoss = true by default)
    IsBoss = "IsBoss", FinalBoss = "FinalBoss?", LegendBoss = "LegandBoss?", Raider = "Raider?", Robot = "Robot?",
    Level = "Level",
    -- Q1_BP_Creature_C
    CreatureBoss = "IsBoss?",
    OperationData = "OperationData", -- Game_Builder: your faction's current operation
    -- Q1Controller (player controller)
    GameBuilderRef = "GameBuilderRef",
    -- Q1GameInstance
    CharacterID = "CharacterID", CharacterName = "CharacterName", LoadSaveFile = "LoadSaveFile",
    -- native Families struct (GetFamilyByID)
    FamilyID = "FamilyID", FamilyParentType = "FamilyParentType", FamilyName = "FamilyName",
    -- native FamilyDominanceInSystem (GetDominanceDataOfSystem)
    StartDominance = "StartDominance", RaidRequiredDominance = "RaidRequiredDominance",
    DominanceVariables = "SystemDominanceVariables",
    -- Shop_Widget
    SoldItem = "SoldItem", Amount = "Amount", MarketType = "MarketWidget", HunterMarket = "HunterMarket",
    -- Bought_Slot event parameter
    ToastSell = "Sell?",
}

G.P.CurrentSystemData = "CurrentSystemData" -- Game_Builder, Created_Solar_Data
-- Created_Solar_Data fields
G.System = {
    ID      = "ID_10_EB757AB245A9218C362B75A30991D13C",
    Faction = "Faction_7_C5C66FE84A24B6444AEFFEBA255B3DB7", -- Factions byte (G.FactionByte); may be stale
    Level   = "Systemlevel_53_38FB946B43CDA8204818C5A6004C5DA8",
}

-- S_Item_Data fields
G.Item = {
    Type  = "Type_10_BF723D5042242143C6379BB031CAA5DB",   -- Item_Types1 (below)
    Value = "Value_48_FEFCE2EF4E309330F1862F955E59864E",  -- base price (shop pays Value / 1.4)
    Level = "ItemLevel_32_36C68C8841BC84733BDEE38AC9296BF6",
    Tier  = "ItemTier_31_620BE1F64621359F21DE589574539BBB",
    Name  = "Name_2_33AAB92A40B75F3E09ACFB89586AE747",
}

-- S_Quest_Info_1 fields
G.Quest = {
    Tag      = "Contract_Tag_36_BF140E5646F3846D553C58954977A585",
    Name     = "Name_2_24DCBD6A476E3A026A901A89990F4483",
    Kind     = "C_Type_61_69D14D0B40D378615E65AEA212322BE9",  -- Quest_Action_Types
    Type     = "Type_55_DC701A10494A8B4B7887DAA3CC92CDEC",    -- Contract_Types
    Level    = "SuggestedLevel_13_2D8EF75B4E6BBC14A434B69263FF3A92",
    Tier     = "DiffuclityTier_16_659A0CAD4A650CE7AF9348B6A463E72F",
    SubGoals = "SubGoals_20_A3706A834E8BB2CA20C83A8B7E57FCA0",
    Client   = "ClintID_28_56D3662142B624F87A1169A8510F29C3", -- bounty name for bounties
    Accepted = "AcceptedTime_50_446C7C274EFB8C99D7487DBC7283BCE9",
    Mail     = "Mail?_66_F83DF4E9416340D57BEB86BC039B50D3",
    GoalLocation = "Location_5_63FE09AA49DE68CE047CC08DEB9E2E8E", -- S_Goal_Info: system ID
}
G.BountyFaction = "Faction_24_CD6A88074A2245CA988BCBB3F0A21CA2" -- BountyList entry
-- Operation_Data (Game_Builder.OperationData); the quest of an operation has the tag "Operation"
G.Operation = { Tag = "Operation", Location = "OperationLocation_37_1D073FF24C820745ECF779BFC866D7CA",
    SystemID = "StationSystemID" }

-- Enums (byte values) -----------------------------------------------------------
-- Item_Types1 (S_Item_Data.Type)
G.ItemType = {
    [0] = "Garbage", "Weapon", "Module", "UpgradeComponent", "Mine", "UsableModule", "Wreck", "Rockets",
    "Probes", "MisactorTools", "QuestItem", "CargoCrate", "HandWeapon", "Granade", "Ammo", "Suit", "Compax",
    "SuitModule", "CombatDrone", "TradeGoods",
}
-- Market_Types (Shop_Widget.MarketWidget)
G.MarketType = { [0] = "Weapon", "Upgrades", "GeneralMerchant", "Ship", "HandWeapons" }
-- Factions byte (old Blueprint layer; inferred from code, confirm in game)
G.FactionByte = { [0] = "Morthra", "Falron", "Xeghan", "Pirates", "Aliens", "Independent", "WRA" }
-- Native dungeon manager (Q1_DungeonManager_C, child of /Script/SB2.CPP_DungeonManager)
G.Dungeon = {
    FloorClearedRole = 2, -- ECPP_DungeonDoorRole value that calls CurrentFloorCleared() (verify in game)
    -- CPP_DungeonData (GetCurrentDungeon()) and CPP_DungeonFloorData fields
    ID = "DungeonID", Type = "DungeonType", Name = "DungeonName", Level = "DungeonLevel", System = "SystemID",
    Floors = "Floors", FloorIndex = "FloorIndex", Boss = "bIsBossLevel", Cleared = "bCleared",
}
-- ECPP_DungeonType as labelled by the records widget: 0 camp ("Crimson Hideout", pirates),
-- 1 salvage ("Scrapper Colony"), 2-3 caves, 4 space ("Black Orbit")
G.DungeonType = { [0] = "camp", "salvage", "cave", "cave", "space" }
-- WhereIsPlayer (Game_Builder.PlayerIsAt)
G.WhereIsPlayer = { [0] = "Space", "PlanetSurface", "Dungeon", "Wormhole", "StationTrans", "StationSubLevel" }
-- Quest_Action_Types and Contract_Types
G.QuestKind = { [0] = "Contract", "MainQuest", "SideQuest", "Bounty" }
G.ContractType = {
    [0] = "KillOne", "KillMulti", "ClearArea", "GuardAsteroid", "GuardSalvage", "GuardConvoy", "GuardTrade",
    "GuardBase", "Escord", "DestroyBase", "SavePerson", "Capture_Person", "JoinRaid", "JoinGuard", "Foot_KillOne",
    "Foot_SavePerson", "Foot_Hack", "Foot_DestroyCrates", "Foot_Planet_SkinVilliage", "Foot_Planet_Kill_Outpost",
    "Foot_Planet_ClearCity", "DLC_HelpVillage", "DLC_HelpStation", "DLC_SaveSomeone", "DLC_DestroyHive",
    "DLC_DestroyShips", "DLC_GetItem",
}

-- The player's faction in the native family manager, and the parent types it uses
G.PlayerFamilyID = "WRA"
G.Parents = { Falron = true, Xeghan = true, Morthra = true, Pirates = true, Earthling = true, WRA = true }

-- The mod's own line in a system's dominance list (shown by the game's resistance window)
G.Dom = { ID = "FP_LocalSupport", Name = "Local support", Type = "FactionPower" }

return G
