function has(item, amount)
    local count = Tracker:ProviderCountForCode(item)
    amount = tonumber(amount)
    if not amount then
        return count > 0
    else
        return count >= amount
    end
end

function spring()
    return has("spring")
end

function summer()
    return has("summer")
end

function fall()
    return has("fall")
end

function winter()
    return has("winter")
end

-- Pickaxe stage codes are mutually exclusive (only one is active at a time
-- per progressive-item stage), so "has at least Copper" must check every
-- tier from Copper upward.
function has_at_least_copper_pickaxe()
    return has("CopperPick") or has("SteelPick") or has("GoldPick") or has("IridiumPick")
end

function has_at_least_iron_pickaxe()
    return has("SteelPick") or has("GoldPick") or has("IridiumPick")
end

function has_at_least_gold_pickaxe()
    return has("GoldPick") or has("IridiumPick")
end

function has_at_least_iridium_pickaxe()
    return has("IridiumPick")
end

-- Elevator is a 24-stage progressive item; only the current stage's "eN"
-- code is active at any time, so we can't check a single threshold with
-- has("eN"). Helper checks any stage at or above the requested floor.
-- PopTracker access rules don't support $func(arg) syntax, so we expose
-- per-threshold no-arg wrappers below (has_at_least_elevator_5, ..._10,
-- etc.) for use from JSON. The parametrized version stays for Lua callers.
function has_at_least_elevator(min_floor)
    min_floor = tonumber(min_floor) or 0
    for floor = min_floor, 120, 5 do
        if has("e" .. floor) then return true end
    end
    return false
end

for threshold = 5, 115, 5 do
    _G["has_at_least_elevator_" .. threshold] = function()
        return has_at_least_elevator(threshold)
    end
end

function can_mine_copper()
    return has_at_least_copper_pickaxe() or has_at_least_elevator(5)
end

function can_mine_iron()
    return has_at_least_iron_pickaxe() or has_at_least_elevator(40)
end

function can_mine_gold()
    return has_at_least_gold_pickaxe() or has_at_least_elevator(80)
end

-- Axe / Hoe / Watering Can / Trash Can / Pan use the same pattern.
function has_at_least_copper_axe()    return has("CopperAxe") or has("SteelAxe") or has("GoldAxe") or has("IridiumAxe") end
function has_at_least_steel_axe()     return has("SteelAxe") or has("GoldAxe") or has("IridiumAxe") end
function has_at_least_gold_axe()      return has("GoldAxe") or has("IridiumAxe") end
function has_at_least_iridium_axe()   return has("IridiumAxe") end

function has_at_least_copper_hoe()    return has("CopperHoe") or has("SteelHoe") or has("GoldHoe") or has("IridiumHoe") end
function has_at_least_steel_hoe()     return has("SteelHoe") or has("GoldHoe") or has("IridiumHoe") end
function has_at_least_gold_hoe()      return has("GoldHoe") or has("IridiumHoe") end
function has_at_least_iridium_hoe()   return has("IridiumHoe") end

function has_at_least_copper_can()    return has("CopperCan") or has("SteelCan") or has("GoldCan") or has("IridiumCan") end
function has_at_least_steel_can()     return has("SteelCan") or has("GoldCan") or has("IridiumCan") end
function has_at_least_gold_can()      return has("GoldCan") or has("IridiumCan") end
function has_at_least_iridium_can()   return has("IridiumCan") end

function has_at_least_copper_pan()    return has("CopperPan") or has("SteelPan") or has("GoldPan") or has("IridiumPan") end
function has_at_least_steel_pan()     return has("SteelPan") or has("GoldPan") or has("IridiumPan") end
function has_at_least_gold_pan()      return has("GoldPan") or has("IridiumPan") end
function has_at_least_iridium_pan()   return has("IridiumPan") end

function has_at_least_copper_trash()  return has("trashcan") end  -- stage 1+ has "trashcan" code
function has_at_least_steel_trash()   return has("steeltrash") or has("goldtrash") or has("iridiumtrash") end
function has_at_least_gold_trash()    return has("goldtrash") or has("iridiumtrash") end
function has_at_least_iridium_trash() return has("iridiumtrash") end

-- Naming aliases. Original pack uses inconsistent tier names: Pickaxe
-- uses "iron" (has_at_least_iron_pickaxe), Axe/Hoe/Can/Pan/Trash use
-- "steel". AP source uses ToolMaterial.iron uniformly. Aliases below let
-- access rules use either convention without surprises.
function has_at_least_steel_pickaxe() return has_at_least_iron_pickaxe() end
function has_at_least_iron_axe()      return has_at_least_steel_axe() end
function has_at_least_iron_hoe()      return has_at_least_steel_hoe() end
function has_at_least_iron_can()      return has_at_least_steel_can() end
function has_at_least_iron_pan()      return has_at_least_steel_pan() end
function has_at_least_iron_trash()    return has_at_least_steel_trash() end

function has_weapon()
    return has("sword") or has("club") or has("dagger") or has("slingshot")
end

function can_walk_to_mines_floor_5()
    -- AP's can_progress_in_the_mines_from_floor(5): basic weapon + copper-tier pickaxe.
    return has_weapon() and has_at_least_copper_pickaxe()
end

function can_walk_to_mines_floor_45()
    return has_weapon() and has_at_least_iron_pickaxe()
end

function can_walk_to_mines_floor_85()
    return has_weapon() and has_at_least_gold_pickaxe()
end

-- AP's can_have_earned_total approximations. The pack can't model gold
-- earnings precisely, so we proxy money progression on having received
-- progression milestones (any tool stage past base = some money flowed).
function can_earn_money_modest()
    -- ~5000g territory: needs a fishing rod or any tool upgrade.
    return has("rod") or has_at_least_copper_pickaxe() or has_at_least_copper_axe()
end

function can_earn_money_substantial()
    -- ~25000g territory (Demetrius's Breakthrough): needs the kitchen
    -- (proxy for farmhouse upgrade via house progression).
    return has("kitchen") or has("house") or has_at_least_iron_pickaxe()
end

function can_earn_money_late_game()
    -- ~100000g+ territory (Krobus Stardrop): late-game progression.
    return has("kitchen") or has_at_least_gold_pickaxe() or has("greenhouse")
end

-- Entrance Randomization & region reachability.
--
-- The heavy lifting is in scripts/autotracking/entrance_logic.lua, which
-- walks the slot-specific entrance graph (driven by AP's slot_data
-- randomized_entrances + the static graph generated from AP source) and
-- exposes can_reach("<region>") plus per-region no-arg wrappers.
--
-- The can_access_<region> helpers below stay for backwards compatibility
-- with existing JSON access rules. Each defers to can_reach when the
-- entrance_logic.lua module loaded, and OR-falls-back on the raw wallet
-- code so users without entrance randomization (or before slot connect)
-- still get sensible results.
function entrance_shuffle_active()
    return has("entrance_shuffle_on")
end

local function reach_or(region, fallback_code)
    if can_reach then
        return can_reach(region) or has(fallback_code)
    end
    return has(fallback_code) or entrance_shuffle_active()
end

function has_skull_key()        return reach_or("Skull Cavern", "skullkey") end
function can_access_sewer()     return reach_or("Sewer",         "sewerkey") end
function can_access_witch_swamp() return reach_or("Witch's Swamp", "darktalisman") end
function can_access_casino()    return reach_or("Casino",        "clubcard") end

function can_access_desert()
    if can_reach then return can_reach("Desert") or has("desertwarp") end
    return has("desertwarp") or has("bus") or entrance_shuffle_active()
end

function can_access_island()
    if can_reach then return can_reach("Island South") or has("islandwarp") end
    return has("islandwarp") or entrance_shuffle_active()
end

function can_mine_iridium()
    return (has("CopperPick") and ((can_access_desert() and has("skullkey")) or can_access_island()))
end

function can_fish()
    return has("rod")
end

function has_crab_pots()
    return (can_mine_iron() and has("fishing",3))
end

function can_chop_stumps()
    return has("SteelAxe")
end

function can_chop_logs()
    return has("GoldAxe")
end

function has_coop()
    return has("chicken")
end

function has_big_coop()
    return has("duck")
end

function has_deluxe_coop()
    return has("rabbit")
end

function has_barn()
    return has("cow")
end

function has_big_barn()
    return has("goat")
end

function has_deluxe_barn()
    return has("pig")
end

function has_bridge()
    return has("bridge")
end

function secret_notes()
    return has("notes")
end

function can_cook()
    return (has("kitchen") or has("foraging",9))
end

function can_brew()
    return has("farming",8)
end

function exoticforagebundle()
    local amt = 0
    local need = 5
    if can_access_desert() then
        amt = amt + 2
    end
    if has("foraging",3) then
        amt = amt + 3
    end
    if can_chop_logs() then
        amt = amt + 1
    end
    if has("e40") then
        amt = amt + 2
    end
    if has("e80") then
        amt = amt + 1
    end
    return (amt >= need)
end

function animalbundle()
    local amt = 0
    local need = 5
    if has_barn() then
        amt = amt + 1
    end
    if has_big_barn() then
        amt = amt + 1
    end
    if has_coop() then
        amt = amt + 2
    end
    if has_big_coop() then
        amt = amt + 1
    end
    if (has_deluxe_coop() or has_deluxe_barn()) then
        amt = amt + 1
    end
    return (amt >= need)
end

function artisanbundle()
    local amt = 2
    local need = 6
    if (has_deluxe_barn() and has("farming",8)) then
        amt = amt + 1
    end
    if ((has_deluxe_barn() or has_deluxe_coop()) and has("farming",7)) then
        amt = amt + 1
    end
    if (has_big_barn() and has("farming",6)) then
        amt = amt + 1
    end
    if (has_barn() and has("farming",6)) then
        amt = amt + 1
    end
    if has("farming",3) then
        amt = amt + 1
    end
    if has("farming",4) then
        amt = amt + 1
    end
    if summer() then
        amt = amt + 2
    end
    if fall() then
        amt = amt + 2
    end
    return (amt >= need)
end


function chefbundle()
    return (can_chop_logs() and has_deluxe_barn() and can_cook() and summer())
end

function dyebundle()
    return (has("e40") and has_big_coop() and (has("e80") or can_chop_logs()) and summer())
end

function fieldresearchbundle()
    return (has("e40") and can_fish() and winter())
end

function enchantbundle()
    -- Bundles can be vanilla (4-of-4 required) or thematic/remixed
    -- (3-of-N from an extended pool). Without parsing slot_data
    -- modified_bundles, accept either path as in-logic:
    --   * vanilla 4-of-4: deluxe coop + brew + tapper + fall
    --   * thematic/remixed 3-of-X: 2 mines minerals (floor 41-80) +
    --     any one of tapper / wine / rabbit foot. Reaching floor 81+
    --     gives 3 mines items (solar essence + frozen tear + purple
    --     mushroom).
    local thematic = can_walk_to_mines_floor_45() and (
        has("foraging", 3)                                  -- tapper -> oak resin
        or (can_brew() and (has("grape") or has_at_least_iron_pickaxe()))
        or has_deluxe_coop()                                -- rabbit foot
    )
    local thematic_alt = can_walk_to_mines_floor_85()       -- 3 mines items in floors 81+
    local vanilla = has_deluxe_coop() and can_brew() and has("foraging",3) and fall()
    return thematic or thematic_alt or vanilla
end

function farming1()
    return has("farming",1)
end

function tmmon()
    return has("monday")
end

function tmtues()
    return has("tuesday")
end

function tmwed()
    return has("wednesday")
end

function tmthurs()
    return has("thursday")
end

function tmfri()
    return has("friday")
end

function tmsat()
    return has("saturday")
end

function tmsun()
    return has("sunday")
end

function quests1()
    return has("quests",1)
end
function quests2()
    return has("quests",2)
end
function quests3()
    return has("quests",3)
end
function quests4()
    return has("quests",4)
end
function quests5()
    return has("quests",5)
end
function quests6()
    return has("quests",6)
end
function quests7()
    return has("quests",7)
end
function quests8()
    return has("quests",8)
end
function quests9()
    return has("quests",9)
end
function quests10()
    return has("quests",10)
end
function quests11()
    return has("quests",11)
end
function quests12()
    return has("quests",12)
end
function quests13()
    return has("quests",13)
end
function quests14()
    return has("quests",14)
end
function quests15()
    return has("quests",15)
end
function quests16()
    return has("quests",16)
end
function quests17()
    return has("quests",17)
end
function quests18()
    return has("quests",18)
end
function quests19()
    return has("quests",19)
end
function quests20()
    return has("quests",20)
end
function quests21()
    return has("quests",21)
end
function quests22()
    return has("quests",22)
end
function quests23()
    return has("quests",23)
end
function quests24()
    return has("quests",24)
end
function quests25()
    return has("quests",25)
end
function quests26()
    return has("quests",26)
end
function quests27()
    return has("quests",27)
end
function quests28()
    return has("quests",28)
end
function quests29()
    return has("quests",29)
end
function quests30()
    return has("quests",30)
end
function quests31()
    return has("quests",31)
end
function quests32()
    return has("quests",32)
end
function quests33()
    return has("quests",33)
end
function quests34()
    return has("quests",34)
end
function quests35()
    return has("quests",35)
end
function quests36()
    return has("quests",36)
end
function quests37()
    return has("quests",37)
end
function quests38()
    return has("quests",38)
end
function quests39()
    return has("quests",39)
end
function quests40()
    return has("quests",40)
end
function quests41()
    return has("quests",41)
end
function quests42()
    return has("quests",42)
end
function quests43()
    return has("quests",43)
end
function quests44()
    return has("quests",44)
end
function quests45()
    return has("quests",45)
end
function quests46()
    return has("quests",46)
end
function quests47()
    return has("quests",47)
end
function quests48()
    return has("quests",48)
end
function quests49()
    return has("quests",49)
end
function quests50()
    return has("quests",50)
end
function quests51()
    return has("quests",51)
end
function quests52()
    return has("quests",52)
end
function quests53()
    return has("quests",53)
end
function quests54()
    return has("quests",54)
end
function quests55()
    return has("quests",55)
end
function quests56()
    return has("quests",56)
end

function can_get_mastery()
    return (has("farming",10) and has("mining",10) and has("foraging",10) and has("fishing",10) and has("combat",10) )
end

-- Additional gating helpers used by the generated category access_rules.
-- Keep these intentionally simple — they're meant to be a reasonable
-- approximation of what AP considers "in logic", not a full port of the
-- AP world's rules engine.

function has_kitchen()
    return has("kitchen")
end

function can_access_skull_cavern()
    return (can_access_desert() and has_skull_key())
end

function can_complete_community_center()
    return has("ccdone") or has("greenhouse")
end

function has_greenhouse()
    return has("greenhouse")
end

function can_ship()
    return has("shipping") or true
end

-- Friendsanity heart access: most NPCs unlock at heart events. Without a
-- full friendship tracker we approximate "can reach heart N" as "season
-- has passed" using the simplest signal available — tracking is deferred
-- to the player ticking off hearts manually.
function can_reach_8_hearts()
    return has("spring") or has("summer") or has("fall") or has("winter")
end

-- Walnut purchases all require a stocked island trader (Island West turtle move).
function can_buy_walnut_items()
    return can_access_island() and has("turtlew")
end

-- Eatsanity: most "eat" checks require obtaining the item, which is an
-- enormous logic graph. As a pragmatic approximation, fish-based eat
-- checks need a fishing rod, cooked dishes need a kitchen, and crops
-- need at least one season. Used only when access rules must point
-- somewhere — leaves gaps for the player to manually verify.
function can_eat_fish()
    return can_fish()
end

function can_eat_cooking()
    return can_cook()
end

function can_eat_crops()
    return spring() or summer() or fall() or winter()
end

function can_eat_artisan()
    return can_brew() or has_barn() or has_coop()
end