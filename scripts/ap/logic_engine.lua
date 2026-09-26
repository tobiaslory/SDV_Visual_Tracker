-- Evaluates the Archipelago Stardew Valley logic exported by
-- _build/export_ap_logic.py (scripts/ap/logic_data.lua).
--
-- State comes from the AP item names received via autotracking (onItem),
-- plus slot_data (options, bundles, trash bear requests, entrance swaps).
-- Reachability mirrors AP's CollectionState: a region BFS over the entrance
-- graph and a sweep over logic events, repeated until nothing changes.
--
-- Public API (used by access rules and archipelago.lua):
--   ap_logic_reset()               onClear
--   ap_logic_receive(item_name)    onItem
--   ap_logic_checked(location_id)  onLocation
--   ap_location_ok(id)             true if AP considers the location in logic
--   $ap|<id>  /  $ap_any|<id>|<id>|...   access rule entry points

ScriptHost:LoadScript("scripts/ap/logic_data.lua")

AP_RECEIVED = {}
AP_CHECKED = {}
AP_CONNECTED = false

local NODES = AP_NODES
local LOCS = AP_LOCATIONS
local ENTS = AP_ENTRANCES

for name, l in pairs(AP_EXTRA_LOCATIONS or {}) do
    if not LOCS[name] then
        LOCS[name] = {l[1], nil, l[2], nil}
    end
end

local ID_TO_NAME = {}
local EVENT_LOCS = {}
for name, l in pairs(LOCS) do
    if l[3] then
        ID_TO_NAME[l[3]] = name
    elseif l[4] then
        EVENT_LOCS[#EVENT_LOCS + 1] = name
    end
end
table.sort(EVENT_LOCS)

local EXITS = {}
for name, e in pairs(ENTS) do
    local list = EXITS[e[1]]
    if not list then
        list = {}
        EXITS[e[1]] = list
    end
    list[#list + 1] = name
end
for _, list in pairs(EXITS) do table.sort(list) end

local WEAPONS = {"Progressive Weapon", "Progressive Sword", "Progressive Club", "Progressive Dagger"}
local MONTH_COEFFICIENT = 5   -- 64 // 12 in time_logic.py
local MAX_MONTHS = 12

local dirty = true
local REG = {}
local EVT = {}
local COLLECTED = {}
local SPECIAL = {}
local memo = {}
local ALWAYS = {}
local OVERRIDE_LOC = {}   -- location name -> function() -> bool
local OVERRIDE_ENT = {}   -- entrance name -> function() -> bool
local total_progression = 1

---------------------------------------------------------------------------
-- options
---------------------------------------------------------------------------
local function opt(name)
    local v = SLOT_DATA and SLOT_DATA[name]
    if v == nil then return AP_BASE_OPTIONS[name] end
    return v
end

local function set_has(set, flag)
    if type(set) ~= "table" then return false end
    for _, x in pairs(set) do
        if x == flag then return true end
    end
    return false
end

local axis_cache = {}
local function axis_value(axis)
    local v = axis_cache[axis]
    if v ~= nil then return v end
    local o, flag = axis:match("^([^:*]+):([^*]+)$")
    if axis:find("*", 1, true) then
        -- composite axis "a*b*opt:Flag" -> "1|4|true"
        local parts = {}
        for part in axis:gmatch("[^*]+") do
            parts[#parts + 1] = tostring(axis_value(part))
        end
        v = table.concat(parts, "|")
    elseif o then
        v = set_has(opt(o), flag)
    else
        v = opt(axis)
        if type(v) == "number" then v = math.tointeger(v) or v end
    end
    axis_cache[axis] = v
    return v
end

---------------------------------------------------------------------------
-- item counts
---------------------------------------------------------------------------
local function count(name)
    local c = (AP_RECEIVED[name] or 0) + (EVT[name] or 0)
    local s = SPECIAL[name]
    if s and s > c then c = s end
    return c
end

local PROGRESSION = AP_PROGRESSION_ITEMS

-- Classification + AP's total_progression_items (not in slot_data) are
-- rebuilt from the exporter's minimal-options base plus the variants that
-- match this slot's options.
local function build_progression_table()
    PROGRESSION = {}
    for name, k in pairs(AP_PROGRESSION_ITEMS) do PROGRESSION[name] = k end
    local total = AP_PROGRESSION_MIN_TOTAL
    for _, v in ipairs(AP_PROGRESSION_VARIANTS) do
        if axis_value(v[1]) == v[2] then
            total = total + v[3]
            for name, d in pairs(v[4]) do
                PROGRESSION[name] = (PROGRESSION[name] or 0) + d
            end
        end
    end
    total_progression = math.max(1, total)
end

local function update_special()
    local prog, walnuts, gems = 0, 0, 0
    for name, n in pairs(AP_RECEIVED) do
        local k = PROGRESSION[name]
        if k and k > 0 then prog = prog + math.min(n, k) end
        local w = AP_WALNUT_ITEMS[name]
        if w then walnuts = walnuts + w * n end
        local g = AP_QI_GEM_ITEMS[name]
        if g then gems = gems + g * n end
    end
    for _, n in pairs(EVT) do prog = prog + n end
    local weapon = 0
    for _, w in ipairs(WEAPONS) do
        local n = AP_RECEIVED[w] or 0
        if n > weapon then weapon = n end
    end
    SPECIAL["Received Progression Item"] = prog
    SPECIAL["Received Progression Percent"] = (prog * 100) // math.max(1, total_progression)
    SPECIAL["Received Walnuts"] = walnuts
    SPECIAL["Received Qi Gems"] = gems
    SPECIAL["Received Progressive Weapon"] = weapon
end

---------------------------------------------------------------------------
-- rule evaluation
---------------------------------------------------------------------------
local ev
local loc_ok
local entrance_ok

local function reach_region(r)
    return REG[r] == true or ALWAYS[r] == true
end

local function reach_location(name)
    local l = LOCS[name]
    if not l then return false end
    if not reach_region(l[1]) then return false end
    return loc_ok(name)
end

---------------------------------------------------------------------------
-- relationships (port of relationship_logic.has_hearts / can_earn_relationship;
-- the exporter replaces both by "__hearts:<npc>:<n>" / "__earn:<npc>:<n>")
---------------------------------------------------------------------------
local helper
local has_item
local hearts
local earn
local pattern_match

local function max_randomized_heart(v)
    local fs = tonumber(opt("friendsanity")) or 0
    if fs == 2 then
        if not v.bachelor then return nil end
        return 8
    elseif fs == 3 then
        if not v.available then return nil end
        return v.bachelor and 8 or 10
    elseif fs == 4 then
        return v.bachelor and 8 or 10
    elseif fs == 5 then
        return v.bachelor and 14 or 10
    end
    return nil
end

local function villager(npc)
    local v = AP_VILLAGERS[npc]
    if v and v.island and tonumber(opt("exclude_ginger_island")) == 1 then return nil end
    return v
end

local function heart_size()
    return tonumber(opt("friendsanity_heart_size")) or 1
end

hearts = function(npc, n)
    local key = "__h:" .. npc .. ":" .. n
    local c = memo[key]
    if c ~= nil then return c end
    memo[key] = false
    local v = villager(npc)
    local r
    if not v then
        r = false
    elseif n <= 0 then
        r = true
    else
        local max = max_randomized_heart(v)
        if not max or n > max then
            r = earn(npc, n)
        else
            r = count(npc .. " <3") >= math.ceil(n / heart_size()) and helper("meet:" .. npc)
        end
    end
    memo[key] = r
    return r
end

earn = function(npc, n)
    local key = "__e:" .. npc .. ":" .. n
    local c = memo[key]
    if c ~= nil then return c end
    memo[key] = false
    local v = villager(npc)
    local r = true
    if not v then
        r = false
    elseif n > 0 then
        r = helper("meet:" .. npc)
        local max = max_randomized_heart(v)
        if r and max then
            local prev = (n > max) and (n - 1) or math.max(n - heart_size(), 0)
            r = hearts(npc, prev)
        end
        if r then r = helper("bday:" .. v.birthday) end
        if r and v.birthday == "Any" then r = helper("bday_any_extra") end
        if r and v.bachelor then
            if n > 10 then
                r = hearts(npc, 10) and has_item("Mermaid's Pendant")
            elseif n > 8 then
                r = hearts(npc, 8) and has_item("Bouquet")
            end
        end
    end
    memo[key] = r
    return r
end

-- Composite switch cases may use "*" for a part ("*|*|*|-1|*").
local split_cache = {}
local function split_parts(s)
    local p = split_cache[s]
    if p then return p end
    p = {}
    for part in (s .. "|"):gmatch("([^|]*)|") do p[#p + 1] = part end
    split_cache[s] = p
    return p
end

pattern_match = function(pattern, value)
    if type(value) ~= "string" then return false end
    local pp, vp = split_parts(pattern), split_parts(value)
    if #pp ~= #vp then return false end
    for i = 1, #pp do
        if pp[i] ~= "*" and pp[i] ~= vp[i] then return false end
    end
    return true
end

local function special_received(item, need)
    local kind, npc, n = item:match("^__(%a+):(.+):(%d+)$")
    if kind == "hearts" then return hearts(npc, tonumber(n)) end
    if kind == "earn" then return earn(npc, tonumber(n)) end
    return false
end

local function eval_node(i)
    local n = NODES[i]
    local t = n[1]
    if t == "A" then
        for k = 2, #n do
            if not ev(n[k]) then return false end
        end
        return true
    elseif t == "O" then
        for k = 2, #n do
            if ev(n[k]) then return true end
        end
        return false
    elseif t == "R" then
        local item = n[2]
        if item:sub(1, 2) == "__" then return special_received(item, n[3]) end
        return count(item) >= n[3]
    elseif t == "H" then
        local r = AP_ITEM_RULES[n[2]]
        if r == nil then return false end
        return ev(r)
    elseif t == "RE" then
        local hint, spot = n[2], n[3]
        if hint == "Region" then return reach_region(spot) end
        if hint == "Location" then return reach_location(spot) end
        local e = ENTS[spot]
        return e ~= nil and reach_region(e[1]) and entrance_ok(spot)
    elseif t == "P" then
        return count("Received Progression Percent") >= n[2]
    elseif t == "S" then
        local v = axis_value(n[2])
        local cases = n[3]
        for k = 1, #cases, 2 do
            local c = cases[k]
            if c == v or (type(c) == "string" and c:find("*", 1, true) and pattern_match(c, v)) then
                return ev(cases[k + 1])
            end
        end
        return ev(n[4])
    elseif t == "C" then
        local need, have = n[2], 0
        local list = n[3]
        local remaining = 0
        for k = 2, #list, 2 do remaining = remaining + list[k] end
        for k = 1, #list, 2 do
            local m = list[k + 1]
            if ev(list[k]) then
                have = have + m
                if have >= need then return true end
            end
            remaining = remaining - m
            if have + remaining < need then return false end
        end
        return have >= need
    elseif t == "TR" then
        local need, have = n[2], 0
        for _, item in ipairs(n[3]) do
            have = have + count(item)
            if have >= need then return true end
        end
        return false
    elseif t == "T" then
        return true
    end
    return false
end

ev = function(i)
    local v = memo[i]
    if v ~= nil then return v end
    memo[i] = false   -- cycle guard
    v = eval_node(i)
    memo[i] = v
    return v
end

loc_ok = function(name)
    local o = OVERRIDE_LOC[name]
    if o then return o() end
    local node = LOCS[name][2]
    if node == nil then return false end
    return ev(node)
end

entrance_ok = function(name)
    local o = OVERRIDE_ENT[name]
    if o then return o() end
    return ev(ENTS[name][3])
end

helper = function(name)
    local i = AP_HELPERS[name]
    if not i then return false end
    return ev(i)
end

has_item = function(item)
    local r = AP_ITEM_RULES["item_rules|" .. item]
    if r == nil then return false end
    return ev(r)
end

---------------------------------------------------------------------------
-- runtime-built rules (bundles, raccoons, trash bear) - see bundle_logic.py
---------------------------------------------------------------------------
local function has_lived_months(n)
    if n <= 0 then return true end
    if n > MAX_MONTHS then n = MAX_MONTHS end
    return count("Received Progression Percent") >= n * MONTH_COEFFICIENT
end

local function can_have_earned_total(amount)
    if amount <= 1000 then return true end
    if amount <= 2000 then return helper("earned:2000") end
    if amount <= 3000 then return helper("earned:3000") end
    if amount <= 5000 then return helper("earned:5000") end
    if amount <= 10000 then return helper("earned:10000") end
    if amount <= 40000 then return helper("earned:40000") end
    local pct = math.min(90, amount // 20000)
    return helper("earned:40000") and count("Received Progression Percent") >= pct
end

local function can_spend(amount)
    if opt("starting_money") == -1 then return true end
    return can_have_earned_total(amount * 5)
end

local function qi_board_enabled()
    local so = tonumber(opt("special_order_locations")) or 0
    return (so & 2) ~= 0 and tonumber(opt("exclude_ginger_island")) ~= 1
end

local CURRENCIES = {
    ["Money"] = true, ["Qi Coin"] = true, ["Golden Walnut"] = true, ["Qi Gem"] = true, ["Star Token"] = true,
}

local function can_trade(currency, amount)
    if amount == 0 then return true end
    if currency == "Money" then return can_spend(amount) end
    if currency == "Star Token" then return helper("fair") end
    if currency == "Qi Coin" then return helper("casino") and has_lived_months(amount // 1000) end
    if currency == "Qi Gem" then
        if qi_board_enabled() then return count("Received Qi Gems") >= amount * 3 end
        return helper("qi_room_and_saloon") and can_have_earned_total(5000)
    end
    if currency == "Golden Walnut" then return false end
    return true
end

local QUALITY_ORDER = {"Iridium", "Gold", "Silver"}

local function parse_bundle(bundle)
    local items = {}
    local i = 0
    while bundle[tostring(i)] ~= nil do
        local name, amount, quality = bundle[tostring(i)]:match("^(.*)|(%-?%d+)|(.*)$")
        items[#items + 1] = {name = name, amount = tonumber(amount), quality = quality}
        i = i + 1
    end
    return items, tonumber(bundle.number_required) or #items
end

local function make_bundle_rule(bundle)
    local items, number_required = parse_bundle(bundle)
    for _, it in ipairs(items) do
        if CURRENCIES[it.name] then
            local name, amount = it.name, it.amount
            return function() return helper("junimo") and can_trade(name, amount) end
        end
    end
    local needed = {}
    local qualities = {}
    local grind = 0
    local needs_well = false
    for _, it in ipairs(items) do
        if it.name == "Well" then
            needs_well = true
            number_required = number_required - 1
        else
            needed[#needed + 1] = it.name
        end
        if it.amount > 50 then grind = it.amount // 50 end
        qualities[it.quality] = true
    end
    local quality_helpers = {}
    for _, kind in ipairs({"Crop", "Fish", "Forage"}) do
        for _, q in ipairs(QUALITY_ORDER) do
            if qualities[q .. " " .. kind] then
                quality_helpers[#quality_helpers + 1] = string.lower(kind) .. "_quality:" .. q .. " " .. kind
                break
            end
        end
    end
    for _, q in ipairs(QUALITY_ORDER) do
        if qualities[q .. " Artisan"] then
            quality_helpers[#quality_helpers + 1] = "cask"
            break
        end
    end
    return function()
        if not helper("junimo") then return false end
        for _, h in ipairs(quality_helpers) do
            if not helper(h) then return false end
        end
        if not has_lived_months(grind) then return false end
        if needs_well and not helper("well") then return false end
        if number_required <= 0 then return true end
        local have = 0
        for _, item in ipairs(needed) do
            if has_item(item) then
                have = have + 1
                if have >= number_required then return true end
            end
        end
        return false
    end
end

local function build_slot_rules()
    OVERRIDE_LOC = {}
    OVERRIDE_ENT = {}
    if not SLOT_DATA then return end
    local bundles = SLOT_DATA.modified_bundles
    if type(bundles) == "table" then
        local extra_raccoons = ((tonumber(opt("quest_locations")) or 0) >= 0) and 1 or 0
        for room, room_bundles in pairs(bundles) do
            local rules = {}
            for bundle_name, bundle in pairs(room_bundles) do
                local rule = make_bundle_rule(bundle)
                if room == "Raccoon Requests" then
                    local num = tonumber(bundle_name:sub(-1)) or 1
                    OVERRIDE_ENT["Can Complete " .. bundle_name] = function()
                        return count("Progressive Raccoon") >= num + extra_raccoons and rule()
                    end
                else
                    OVERRIDE_LOC[bundle_name] = rule
                    rules[#rules + 1] = rule
                end
            end
            if room ~= "Raccoon Requests" and room ~= "Abandoned Joja Mart" then
                OVERRIDE_LOC["Complete " .. room] = function()
                    for _, r in ipairs(rules) do
                        if not r() then return false end
                    end
                    return true
                end
            end
        end
    end
    local bear = SLOT_DATA.trash_bear_requests
    if type(bear) == "table" then
        for request_type, items in pairs(bear) do
            local list = {}
            for _, it in pairs(items) do list[#list + 1] = it end
            OVERRIDE_LOC["Trash Bear " .. request_type] = function()
                if not helper("trash_bear") then return false end
                for _, it in ipairs(list) do
                    if not has_item(it) then return false end
                end
                return true
            end
        end
    end
end

---------------------------------------------------------------------------
-- reachability sweep
---------------------------------------------------------------------------
local function destination(entrance)
    local swaps = SLOT_DATA and SLOT_DATA.randomized_entrances
    if type(swaps) == "table" then
        local repl = swaps[entrance]
        if repl and ENTS[repl] then return ENTS[repl][2] end
    end
    return ENTS[entrance][2]
end

local function sweep()
    REG = {Menu = true}
    EVT = {}
    COLLECTED = {}
    SPECIAL = {}
    ALWAYS = AP_ALWAYS_REGIONS[math.tointeger(tonumber(opt("entrance_randomization")) or 0) or 0] or {}
    update_special()
    local changed = true
    while changed do
        changed = false
        -- region BFS; repeat passes because entrance rules may Reach() regions
        -- found later in the same pass
        local grew = true
        while grew do
            grew = false
            memo = {}
            local queue = {}
            for r in pairs(REG) do queue[#queue + 1] = r end
            table.sort(queue)
            local qi = 1
            while qi <= #queue do
                local region = queue[qi]
                qi = qi + 1
                local exits = EXITS[region]
                if exits then
                    for _, e in ipairs(exits) do
                        local dst = destination(e)
                        if dst and not REG[dst] and entrance_ok(e) then
                            REG[dst] = true
                            queue[#queue + 1] = dst
                            grew = true
                            changed = true
                        end
                    end
                end
            end
        end
        -- logic events
        memo = {}
        local got = false
        for _, name in ipairs(EVENT_LOCS) do
            if not COLLECTED[name] then
                local l = LOCS[name]
                if REG[l[1]] and loc_ok(name) then
                    COLLECTED[name] = true
                    EVT[l[4]] = (EVT[l[4]] or 0) + 1
                    got = true
                end
            end
        end
        if got then
            update_special()
            memo = {}
            changed = true
        end
    end
    dirty = false
end

local function ensure()
    if dirty then sweep() end
end

---------------------------------------------------------------------------
-- public API
---------------------------------------------------------------------------
-- PopTracker only re-evaluates access rules when tracker state changes. Many
-- AP items (seasons, recipes, ...) have no pack item, so bump a hidden
-- counter item whenever the engine's inputs change.
local function bump_revision()
    local obj = Tracker:FindObjectForCode("ap_logic_rev")
    if obj then obj.AcquiredCount = (obj.AcquiredCount + 1) % 1000000 end
end

function ap_logic_reset()
    AP_RECEIVED = {}
    AP_CHECKED = {}
    axis_cache = {}
    build_progression_table()
    build_slot_rules()
    AP_CONNECTED = SLOT_DATA ~= nil and next(SLOT_DATA) ~= nil
    dirty = true
    bump_revision()
end

function ap_logic_receive(item_name)
    if item_name == nil then return end
    AP_RECEIVED[item_name] = (AP_RECEIVED[item_name] or 0) + 1
    dirty = true
    bump_revision()
end

function ap_logic_checked(location_id)
    AP_CHECKED[location_id] = true
    bump_revision()
end

function ap_location_ok(id)
    local name = ID_TO_NAME[tonumber(id)]
    if not name then return false end
    ensure()
    return reach_location(name)
end

function ap_location_name(id)
    return ID_TO_NAME[tonumber(id)]
end

function ap_region_reachable(region)
    ensure()
    return reach_region(region)
end

-- Access rule entry points. Without an AP connection there is no item
-- state; the JSON rules then fall back to their "$ap_offline,..." branches
-- (the pack's hand-written approximations for manual tracking).
function ap(id)
    if not AP_CONNECTED then return false end
    return ap_location_ok(id)
end

function ap_any(...)
    if not AP_CONNECTED then return false end
    -- ALL_LOCATIONS (archipelago.lua) = the slot's location ids
    local in_slot = ALL_LOCATIONS ~= nil and next(ALL_LOCATIONS) ~= nil and ALL_LOCATIONS or nil
    local any_unchecked = false
    for _, id in ipairs({...}) do
        local n = tonumber(id)
        if not AP_CHECKED[n] and (in_slot == nil or in_slot[n]) then
            any_unchecked = true
            if ap_location_ok(n) then return true end
        end
    end
    -- everything already checked: keep the section green
    return not any_unchecked
end

function ap_offline()
    return not AP_CONNECTED
end

-- Debug helper: why is a location (not) in logic?
function ap_debug_location(id_or_name)
    ensure()
    local name = ID_TO_NAME[tonumber(id_or_name)] or id_or_name
    local l = LOCS[name]
    if not l then return "unknown location " .. tostring(id_or_name) end
    return string.format("%s: region %s reachable=%s rule=%s", name, l[1], tostring(reach_region(l[1])), tostring(loc_ok(name)))
end

-- Debug/testing helpers
function ap_eval_node(i)
    ensure()
    return ev(i)
end

function ap_debug_state()
    ensure()
    return total_progression, SPECIAL["Received Progression Item"], SPECIAL["Received Progression Percent"]
end

function ap_debug_is_progression(name)
    return PROGRESSION[name] or 0
end

function ap_debug_axis(axis)
    return tostring(axis_value(axis))
end
