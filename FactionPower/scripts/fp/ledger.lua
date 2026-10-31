--[[
  The mod's own memory, one file per character: <mod>\ledger-<CharacterID>.lua.
  This is NOT the game's save. The game's save is only changed through the game's own
  functions (see world.lua), and never written by this file.

  Writes are rare (at most every SaveEverySeconds, and only when something changed),
  go to a .tmp file first, and keep the previous version as .bak.
  Verified in game: written, re-read, and matching the game's dominance lines.
]]

local U = require("fp.util")
local M = require("fp.model")

local Lg = { state = nil, dirty = false, savedAt = 0, file = nil }

local function safeName(s)
    s = tostring(s or ""):gsub("[^%w%-_]", "_")
    if s == "" then s = "unknown" end
    return s:sub(1, 64)
end

local function ser(v, ind)
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        return string.format("%.6g", v)
    elseif t == "boolean" then return tostring(v)
    elseif t == "string" then return string.format("%q", v)
    elseif t == "table" then
        ind = ind or ""
        local inner, parts = ind .. "  ", {}
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", tostring(k)) .. "]")
            parts[#parts + 1] = inner .. key .. " = " .. ser(v[k], inner)
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. ind .. "}"
    end
    return "nil"
end

-- Load (or create) the ledger of `character`. Returns the state table.
function Lg.open(character)
    local name = safeName(character)
    Lg.file = U.Dir .. "ledger-" .. name .. ".lua"
    Lg.state, Lg.dirty = nil, false
    local f = io.open(Lg.file, "r")
    if f then
        local text = f:read("a"); f:close()
        local fn = load(text, "ledger", "t", {})
        local ok, data = false, nil
        if fn then ok, data = pcall(fn) end
        if ok and type(data) == "table" and data.version == 1 then
            Lg.state = data
        else
            U.warn("ledger " .. Lg.file .. " unreadable; starting a new one (old file kept as .broken)")
            os.rename(Lg.file, Lg.file .. ".broken")
        end
    end
    Lg.state = Lg.state or M.newState(character)
    return Lg.state
end

function Lg.touch() Lg.dirty = true end

-- Write if changed and at least `minGap` seconds since the last write (minGap 0 = now).
function Lg.flush(minGap)
    if not (Lg.state and Lg.dirty and Lg.file) then return end
    local now = os.clock()
    if minGap and minGap > 0 and now - Lg.savedAt < minGap then return end
    local tmp = Lg.file .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then U.warn("cannot write " .. tmp); return end
    f:write("-- FactionPower ledger (the mod's own data, not your save). Safe to delete: the mod then forgets its influence.\nreturn ", ser(Lg.state), "\n")
    f:close()
    os.remove(Lg.file .. ".bak")
    os.rename(Lg.file, Lg.file .. ".bak")
    local ok = os.rename(tmp, Lg.file)
    if not ok then U.warn("cannot replace " .. Lg.file) return end
    Lg.dirty, Lg.savedAt = false, now
end

return Lg
