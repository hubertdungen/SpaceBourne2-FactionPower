--[[
  Shared helpers (subset of HTR's htr/util.lua). Safety rules used everywhere:
   * Game objects are only touched inside hook callbacks or right after an engine
     lookup. No object is kept from one frame to the next, except the Game_Builder
     cache in world.lua, which is re-checked with IsValid() before every use.
   * Never call RegisterLoadMapPreHook/PostHook: they crash this game.
   * Hooks are only placed on Blueprint functions.
   * Never scan all objects (FindAllOf/FindFirstOf) in frequent code: ~50 ms each.
]]

local U = {}

do
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    local lower = src:lower()
    local cut
    for i in lower:gmatch("()[\\/]scripts[\\/]") do cut = i end
    U.Dir = cut and src:sub(1, cut) or ".\\Mods\\FactionPower\\"
end
U.LogFile = U.Dir .. "factionpower.log"
U.Verbose = false

function U.log(...)
    if not U.Verbose then return end
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    local f = io.open(U.LogFile, "a")
    if f then f:write(os.date("%H:%M:%S "), table.concat(t, " "), "\n"); f:close() end
end

-- Always printed (UE4SS.log) and logged.
function U.warn(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    local msg = table.concat(t, " ")
    print("[FactionPower] " .. msg .. "\n")
    local f = io.open(U.LogFile, "a")
    if f then f:write(os.date("%H:%M:%S "), "WARN ", msg, "\n"); f:close() end
end

function U.valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v
end

function U.get(o, prop, default)
    local ok, v = pcall(function() return o[prop] end)
    if ok and v ~= nil then return v end
    return default
end

-- FName / FString / FText -> Lua string ("" on failure).
function U.str(v)
    if v == nil then return "" end
    if type(v) == "string" then return v end
    local ok, s = pcall(function() return v:ToString() end)
    return ok and s or ""
end

function U.clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

local GS
function U.gameplayStatics()
    if not U.valid(GS) then GS = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
    return GS
end

-- The player's pawn from any live object in the world (instant).
function U.playerPawn(ctx)
    if ctx == nil then return nil end
    local ok, p = pcall(function() return U.gameplayStatics():GetPlayerPawn(ctx, 0) end)
    if ok and U.valid(p) then return p end
    return nil
end

-- On-screen message (same channels HTR verified in game): on foot the HUD warning
-- line (TMWPerkWarning); otherwise the red cursor warning of Q1FunctionLibary.
local MSG_LIB = "/Game/1Data/FunctionsMacros/Q1FunctionLibary.Default__Q1FunctionLibary_C"
function U.notify(text, ctx)
    local p = U.playerPawn(ctx)
    if U.valid(p) and pcall(function() p:TMWPerkWarning(FText(text)) end) then return true end
    local lib = StaticFindObject(MSG_LIB)
    local wc = U.valid(p) and p or ctx
    if not (U.valid(lib) and U.valid(wc)) then return false end
    return pcall(function() lib:CursorWarningWidget(FText(text), wc) end)
end

return U
