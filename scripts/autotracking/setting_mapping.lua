-- Maps Archipelago slot data values onto the tracker setting toggles
-- (defined in items/settings.json). Called from archipelago.lua's onClear.
-- Each helper assumes the relevant settings.json entry exists. Missing
-- entries are silently skipped so the pack stays usable while older
-- slot configs are loaded.

local function set_active(code, active)
    local obj = Tracker:FindObjectForCode(code)
    if obj then
        obj.Active = active and true or false
    end
end

local function set_stage(code, stage_idx)
    local obj = Tracker:FindObjectForCode(code)
    if obj and obj.Type == "progressive" then
        obj.CurrentStage = stage_idx
        obj.Active = true
    end
end

local function get_value(slot_data, key, default)
    if slot_data == nil then return default end
    local v = slot_data[key]
    if v == nil then return default end
    return v
end

-- Many AP options are encoded as integers where 0 = disabled. Some are
-- string preset names ("disabled", "vanilla", "easy", ...). The helpers
-- below normalise to a boolean "enabled" check that matches AP's
-- semantics: treat 0/"none"/"disabled"/"vanilla" as off, anything else
-- as on. Categories that are off should NOT be visible in the tracker.
local function is_enabled(value)
    if value == nil then return false end
    if type(value) == "number" then return value ~= 0 end
    if type(value) == "boolean" then return value end
    if type(value) == "string" then
        local lower = string.lower(value)
        return not (lower == "none" or lower == "disabled" or lower == "vanilla" or lower == "off" or lower == "")
    end
    if type(value) == "table" then
        -- AP can send sets/lists of preset names (e.g. eatsanity, walnutsanity, secretsanity).
        for _, _ in pairs(value) do return true end
        return false
    end
    return false
end

local function table_contains(t, needle)
    if type(t) ~= "table" then return false end
    for _, v in pairs(t) do
        if string.lower(tostring(v)) == string.lower(needle) then return true end
    end
    return false
end

function applySettingsFromSlotData(slot_data)
    if slot_data == nil then return end

    -- Sanity toggles consumed by the new generated location JSONs.
    set_active("friendsanity_on",     is_enabled(get_value(slot_data, "friendsanity")))
    set_active("eatsanity_on",        is_enabled(get_value(slot_data, "eatsanity")))
    set_active("craftsanity_on",      is_enabled(get_value(slot_data, "craftsanity")))
    set_active("hatsanity_on",        is_enabled(get_value(slot_data, "hatsanity")))
    set_active("monstersanity_on",    is_enabled(get_value(slot_data, "monstersanity")))
    set_active("walnutsanity_on",     is_enabled(get_value(slot_data, "walnutsanity")))
    set_active("moviesanity_on",      is_enabled(get_value(slot_data, "moviesanity")))
    set_active("secretsanity_on",     is_enabled(get_value(slot_data, "secretsanity")))
    set_active("walnut_purchase_on",  is_enabled(get_value(slot_data, "walnutsanity"))
                                        or is_enabled(get_value(slot_data, "ginger_island")))
    set_active("endgame_on",          is_enabled(get_value(slot_data, "include_endgame_locations")))

    -- Existing UI is built around progressive items whose stage codes
    -- (cropsanity_on / fishsanity_on / cooksanity_on / chefsanity_on /
    -- shipsanity_X / museum_X / board_X) only become active when the
    -- progressive item is at the specific stage that lists them.
    -- set_active() on a progressive item activates it but doesn't move
    -- the stage, so we drive the stage explicitly from slot data.
    local function set_progressive_stage_by_code(parent_code, target_stage)
        local obj = Tracker:FindObjectForCode(parent_code)
        if obj and obj.Type == "progressive" then
            obj.Active = true
            obj.CurrentStage = target_stage
        end
    end

    -- Cropsanity: 1=autotrack, 2=on. Map to 2 when slot has it enabled.
    set_progressive_stage_by_code("cropsanity",
        is_enabled(get_value(slot_data, "cropsanity")) and 1 or 0)
    -- Fishsanity: 1=off, 2=on (existing item name has a leading-space typo).
    set_progressive_stage_by_code("fishsanity",
        is_enabled(get_value(slot_data, "fishsanity")) and 1 or 0)
    -- Cooksanity: 1=auto, 2=off, 3=on.
    set_progressive_stage_by_code("cooksanity",
        is_enabled(get_value(slot_data, "cooksanity")) and 2 or 1)
    -- Chefsanity: 1=auto, 2=off, 3=on.
    set_progressive_stage_by_code("chefsanity",
        is_enabled(get_value(slot_data, "chefsanity")) and 2 or 1)
    -- Booksanity: my added single toggle, set_active still works.
    set_active("booksanity_on", is_enabled(get_value(slot_data, "booksanity")))

    -- AP serialises Choice options as their integer enum values (option_N).
    -- This helper accepts either int or string for tolerance.
    local function value_in(value, ...)
        for _, candidate in ipairs({...}) do
            if value == candidate then return true end
        end
        return false
    end

    -- Shipsanity progressive item stages (CurrentStage is 0-indexed):
    --   0=None, 1=Crops, 2=Fish, 3=Full, 4=FullwF, 5=Everything.
    -- AP integer values for shipsanity: 0=none, 1=crops, 2=fish, 3=full,
    --   4=full_with_fish, 5=everything.
    local shipsanity = get_value(slot_data, "shipsanity")
    local ship_stage = 0
    if value_in(shipsanity, 1, "crops") then ship_stage = 1
    elseif value_in(shipsanity, 2, "fish") then ship_stage = 2
    elseif value_in(shipsanity, 3, "full_shipment") then ship_stage = 3
    elseif value_in(shipsanity, 4, "full_shipment_with_fish") then ship_stage = 4
    elseif value_in(shipsanity, 5, "everything") then ship_stage = 5
    end
    set_progressive_stage_by_code("shipsanity", ship_stage)
    set_active("shipsanity_on", is_enabled(shipsanity))

    -- Museumsanity: 0=none, 1=milestones, 2=randomized, 3=all.
    -- Pack progressive stages: 0=off, 1=donation, 2=milestone.
    local museum = get_value(slot_data, "museumsanity")
    local museum_stage = 0
    if value_in(museum, 1, "milestones") then museum_stage = 2
    elseif value_in(museum, 2, 3, "randomized", "all") then museum_stage = 1
    end
    set_progressive_stage_by_code("museumsanity", museum_stage)

    -- Special Orders: 0=vanilla, 1=board, 2=board_qi (or string equivalents).
    -- Pack stages: 0=auto, 1=vanilla, 2=board, 3=qi.
    local board = get_value(slot_data, "special_order_locations")
    local board_stage = 1   -- default to vanilla
    if value_in(board, 1, "board") or table_contains(board, "board") then board_stage = 2
    elseif value_in(board, 2, "board_qi") or table_contains(board, "qi") then board_stage = 3
    end
    set_progressive_stage_by_code("board", board_stage)

    -- Arcade machine shuffling.
    local arcade = get_value(slot_data, "arcade_machine_locations")
    set_active("ashuffle",   is_enabled(arcade))
    set_active("ashuffle2",  arcade == "full_shuffling")

    -- Tool / building / skill / elevator / backpack progression hints.
    set_active("tshuffle",   is_enabled(get_value(slot_data, "tool_progression")))
    set_active("bshuffle",   is_enabled(get_value(slot_data, "building_progression")))
    set_active("eshuffleon", is_enabled(get_value(slot_data, "elevator_progression")))
    set_active("pshuffle",   is_enabled(get_value(slot_data, "backpack_progression")))
    set_active("sshuffle",   is_enabled(get_value(slot_data, "skill_progression")))

    -- Goal / island unlock used by some logic helpers.
    local exclude_island = get_value(slot_data, "exclude_ginger_island")
    if exclude_island ~= nil and is_enabled(exclude_island) then
        set_active("ginger_island_off", true)
    else
        set_active("ginger_island_on", true)
    end

    -- Festival locations toggle.
    local festival = get_value(slot_data, "festival_locations")
    set_active("festival_on", is_enabled(festival))
    set_active("festival_hard", festival == "hard")

    -- Entrance Randomization: AP encodes as Choice (option_disabled=0 plus
    -- pelican_town/non_progression/buildings*/chaos). Any non-disabled
    -- value means region-gating keys (sewer key, club card, skull key,
    -- dark talisman, etc.) might be bypassed by a reshuffled entrance.
    -- The can_access_<region> helpers in logic.lua OR this toggle in to
    -- keep those locations in-logic. Loose but safer than false negatives.
    set_active("entrance_shuffle_on",
               is_enabled(get_value(slot_data, "entrance_randomization")))

    -- Friendsanity heart cap (used by Friendsanity location visibility nuance).
    local heart_size = get_value(slot_data, "friendsanity_heart_size")
    if heart_size ~= nil then
        local obj = Tracker:FindObjectForCode("friendsanity_heart_size")
        if obj and obj.Type == "consumable" then
            obj.AcquiredCount = tonumber(heart_size) or 0
        end
    end

    -- Help Wanted quest count (consumable). Drives $quests1..56 helpers in
    -- logic.lua so Help Wanted! locations show as in-pool.
    local qcount = get_value(slot_data, "quest_locations")
    if qcount ~= nil then
        local obj = Tracker:FindObjectForCode("quests")
        if obj and obj.Type == "consumable" then
            obj.AcquiredCount = math.max(0, tonumber(qcount) or 0)
        end
    end

    -- Per-section ChestCount sizing is handled generically in
    -- archipelago.lua's onClear by counting LOCATION_MAPPING entries
    -- that appear in this slot's MissingLocations / CheckedLocations.
    -- That replaces a prior attempt here that read backpack_size and
    -- traveling_merchant_locations from slot_data — the TM field does
    -- not exist as a slot_data field (AP picks the per-day count
    -- internally based on filler/orphan heuristics), and backpack
    -- sizing is implicit in which AP IDs the seed contains.
end
