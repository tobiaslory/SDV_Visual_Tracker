-- Slot-aware region reachability for SDV AP.
--
-- AP's SDV apworld ships `randomized_entrances` in slot_data — a dict
-- mapping each original entrance name to the entrance whose destination
-- it now leads to (see fill_slot_data in Archipelago/worlds/stardew_valley/__init__.py).
-- The static entrance graph (REGION_EXITS, ENTRANCE_DESTS, ENTRANCE_GATES)
-- comes from _generated_entrance_graph.lua, extracted from AP source by
-- _build/generate_entrance_graph.py.
--
-- compute_reachable_regions() walks the graph from Farm using the slot's
-- actual entrance destinations + the gate helpers, yielding a set of
-- reachable region names. can_reach_<region>() helpers consult that set.
--
-- Recomputed lazily — REACHABILITY_DIRTY is flipped true whenever onClear
-- runs or an item is received, and the next can_reach_* call rebuilds it.

ScriptHost:LoadScript("scripts/autotracking/_generated_entrance_graph.lua")

REACHABLE_REGIONS = {}
REACHABILITY_DIRTY = true

-- Each can_traverse_with_* helper is the Lua side of an AP entrance gate.
-- They check the corresponding wallet/item code OR fall back to true when
-- entrance shuffle is active (without slot-level "which random entrance
-- leads here" routing, we approximate by treating shuffle as a free pass
-- through any gate — the BFS then trusts the swap dict for routing).
local function shuffle_active()
    return has("entrance_shuffle_on")
end

function can_traverse_with_rusty_key()          return has("sewerkey")        or shuffle_active() end
function can_traverse_with_skull_key()          return has("skullkey")        or shuffle_active() end
function can_traverse_with_club_card()          return has("clubcard")        or shuffle_active() end
function can_traverse_with_dark_talisman()      return has("darktalisman")    or shuffle_active() end
function can_traverse_with_beach_bridge()       return has("beachbridge")     or shuffle_active() end
function can_traverse_with_landslide_removed()  return has("landslide")       or has("railroad") or shuffle_active() end
function can_traverse_with_wizard_invitation()  return has("wizardinvitation") or shuffle_active() end
function can_traverse_with_community_center_key() return has("communitycenterkey") or shuffle_active() end
function can_traverse_with_railroad()           return has("railroad")        or shuffle_active() end
function can_traverse_with_bus_repair()         return has("bus")             or shuffle_active() end
function can_traverse_with_iron_axe()           return has_at_least_steel_axe() or shuffle_active() end
function can_traverse_with_goblin_quest()       return has("darktalisman")    or shuffle_active() end
function can_traverse_with_movie_ticket()       return has("movietheater")    or shuffle_active() end
function can_traverse_with_desert_obelisk()     return has("desertwarp")      or shuffle_active() end
function can_traverse_with_island_obelisk()     return has("islandwarp")      or shuffle_active() end
function can_traverse_with_farm_obelisk()       return has("farmwarp")        or shuffle_active() end
function can_traverse_with_boat_repair()        return has("boat")            or shuffle_active() end
function can_traverse_with_dig_site_bridge()    return has("digsite")         or shuffle_active() end
function can_traverse_with_west_turtle()        return has("westturtle")      or shuffle_active() end
function can_traverse_with_north_turtle()       return has("northturtle")     or shuffle_active() end
function can_traverse_with_island_farmhouse()   return has("islandfarmhouse") or shuffle_active() end
function can_traverse_with_snail_cave()         return has("snailcave")       or shuffle_active() end
function can_traverse_with_island_trader()      return has("islandtrader")    or shuffle_active() end
function can_traverse_with_island_resort()      return has("islandresort")    or shuffle_active() end
function can_traverse_with_qi_walnut_room()     return has("walnutroom")      or shuffle_active() end
function can_traverse_with_volcano_bridge()     return has("volcanobridge")   or shuffle_active() end


local function gate_passes(entrance_name)
    local helper_name = ENTRANCE_GATES[entrance_name]
    if helper_name == nil then return true end
    local helper = _G[helper_name]
    if helper == nil then return true end
    return helper()
end


-- The randomized_entrances dict maps {original_entrance: replacement_entrance}
-- where "the original entrance's door now leads to (the destination of the
-- replacement entrance)" — see prepare_mod_data in entrance_rando.py.
local function resolve_destination(entrance_name, swaps)
    local replacement = swaps[entrance_name]
    if replacement then
        return ENTRANCE_DESTS[replacement]
    end
    return ENTRANCE_DESTS[entrance_name]
end


function compute_reachable_regions()
    local swaps = {}
    if SLOT_DATA and SLOT_DATA.randomized_entrances then
        swaps = SLOT_DATA.randomized_entrances
    end

    local reachable = {Farm = true, Farmhouse = true, ["Stardew Valley"] = true, Menu = true}
    local frontier = {"Farm", "Farmhouse", "Stardew Valley", "Menu"}

    while #frontier > 0 do
        local region = table.remove(frontier)
        local exits = REGION_EXITS[region]
        if exits then
            for _, entrance in ipairs(exits) do
                if gate_passes(entrance) then
                    local dest = resolve_destination(entrance, swaps)
                    if dest and not reachable[dest] then
                        reachable[dest] = true
                        table.insert(frontier, dest)
                    end
                end
            end
        end
    end
    return reachable
end


function refresh_reachability_if_dirty()
    if REACHABILITY_DIRTY then
        REACHABLE_REGIONS = compute_reachable_regions()
        REACHABILITY_DIRTY = false
    end
end


function mark_reachability_dirty()
    REACHABILITY_DIRTY = true
end


function can_reach(region_name)
    refresh_reachability_if_dirty()
    return REACHABLE_REGIONS[region_name] == true
end


-- No-arg wrappers for use in PopTracker access rules (which don't
-- support $func(arg) calls). One per region we currently gate access on.
function can_reach_sewer()        return can_reach("Sewer") end
function can_reach_skull_cavern() return can_reach("Skull Cavern") end
function can_reach_casino()       return can_reach("Casino") end
function can_reach_witch_swamp()  return can_reach("Witch's Swamp") end
function can_reach_witch_hut()    return can_reach("Witch's Hut") end
function can_reach_secret_woods() return can_reach("Secret Woods") end
function can_reach_desert()       return can_reach("Desert") end
function can_reach_island()       return can_reach("Island South") end
function can_reach_railroad()     return can_reach("Railroad") end
function can_reach_tide_pools()   return can_reach("Tide Pools") end
function can_reach_community_center() return can_reach("Community Center") end
function can_reach_wizard_tower() return can_reach("Wizard Tower") end
function can_reach_adventurers_guild() return can_reach("Adventurer's Guild") end
function can_reach_mutant_bug_lair() return can_reach("Mutant Bug Lair") end
function can_reach_quarry()       return can_reach("Quarry") end
function can_reach_ranch()        return can_reach("Marnie's Ranch") end
