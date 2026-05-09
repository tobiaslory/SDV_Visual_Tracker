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

    -- Existing toggles (kept in sync with slot data so the UI matches the seed).
    set_active("fishsanity_on",  is_enabled(get_value(slot_data, "fishsanity")))
    set_active("cropsanity_on",  is_enabled(get_value(slot_data, "cropsanity")))
    set_active("cooksanity_on",  is_enabled(get_value(slot_data, "cooksanity")))
    set_active("chefsanity_on",  is_enabled(get_value(slot_data, "chefsanity")))
    set_active("booksanity_on",  is_enabled(get_value(slot_data, "booksanity")))

    -- Shipsanity is multi-valued; expose both a generic on and per-mode flags.
    local shipsanity = get_value(slot_data, "shipsanity")
    local ship_on = is_enabled(shipsanity)
    set_active("shipsanity_on",   ship_on)
    set_active("shipsanity_crops",     ship_on and (shipsanity == "crops" or shipsanity == "crops_and_fish"))
    set_active("shipsanity_fish",      ship_on and (shipsanity == "fish" or shipsanity == "crops_and_fish" or shipsanity == "full_shipment_with_fish"))
    set_active("shipsanity_full",      ship_on and (shipsanity == "full_shipment" or shipsanity == "full_shipment_with_fish"))
    set_active("shipsanity_fullwf",    ship_on and shipsanity == "full_shipment_with_fish")
    set_active("shipsanity_all",       ship_on and shipsanity == "everything")

    -- Museumsanity has three states.
    local museum = get_value(slot_data, "museumsanity")
    set_active("museum_off",       museum == "none" or museum == 0 or museum == nil)
    set_active("museum_donation",  museum == "randomized" or museum == "all")
    set_active("museum_milestone", museum == "milestones" or museum == "all")

    -- Special Orders.
    local board = get_value(slot_data, "special_order_locations")
    set_active("board_off",  board == "vanilla" or board == 0 or board == nil)
    set_active("board_on",   board == "board" or table_contains(board, "board"))
    set_active("board_qi",   board == "board_qi" or table_contains(board, "qi"))

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

    -- Friendsanity heart cap (used by Friendsanity location visibility nuance).
    local heart_size = get_value(slot_data, "friendsanity_heart_size")
    if heart_size ~= nil then
        local obj = Tracker:FindObjectForCode("friendsanity_heart_size")
        if obj and obj.Type == "consumable" then
            obj.AcquiredCount = tonumber(heart_size) or 0
        end
    end
end
