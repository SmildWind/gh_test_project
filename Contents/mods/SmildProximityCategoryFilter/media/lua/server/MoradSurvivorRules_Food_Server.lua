require "MoradSurvivorRules_Config"
require "MoradSurvivorRules_Utils"

local MSR = MoradSurvivorRules
local C = MSR.Config
local carryModifierRegistered = false

local function getProteinRatio(player)
    local proteinPower = MSR.pruneProteinContributions(player)
    local maxProtein = tonumber(C.Food.ProteinEffectMax) or 60
    if maxProtein <= 0 then
        return 0, proteinPower
    end
    return MSR.clamp(proteinPower / maxProtein, 0, 1), proteinPower
end

local function registerCarryWeightModifier()
    if carryModifierRegistered then
        return
    end

    if not UnifiedCarryWeightFramework or not UnifiedCarryWeightFramework.registerMaxModifier then
        MSR.log("UnifiedCarryWeightFramework not found; ProteinFed carry weight bonus inactive")
        return
    end

    UnifiedCarryWeightFramework.registerMaxModifier({
        id = "MoradSurvivorRules_ProteinFed",
        resolve = function(context)
            local player = context and context.player
            if not player then
                return nil
            end

            local ratio = getProteinRatio(player)
            local add = (tonumber(C.Food.ProteinCarryWeightMax) or 0) * ratio
            if add <= 0 then
                return nil
            end
            return { add = add }
        end,
    })

    carryModifierRegistered = true
    MSR.log("ProteinFed carry weight modifier registered")
end

local function recomputeCarryWeight(player)
    if UnifiedCarryWeightFramework and UnifiedCarryWeightFramework.recomputeAll then
        UnifiedCarryWeightFramework.recomputeAll(player)
    end
end

local function applyPassiveFoodEffects(player)
    if not player then return end

    local md = player:getModData()
    local stats = player:getStats()
    if not stats then return end

    local proteinRatio, proteinPower = getProteinRatio(player)
    local freshPower = MSR.pruneFreshContributions(player)
    local comfortPower = MSR.pruneComfortContributions(player)
    local poorPower = MSR.prunePoorDietContributions(player)

    if proteinPower > 0 then
        MSR.addEndurance(player, C.Food.ProteinEnduranceDeltaMax * proteinRatio)
        MSR.addFatigue(player, -C.Food.ProteinFatigueReductionDeltaMax * proteinRatio)
        recomputeCarryWeight(player)
    end

    local positivePower = freshPower + comfortPower
    if positivePower > 0 then
        local scale = 1 + (positivePower / 10)
        MSR.addBoredom(player, -C.Food.PassiveBoredomDelta * scale)
        MSR.addUnhappiness(player, -C.Food.PassiveUnhappinessDelta * scale)
        MSR.addStress(player, -C.Food.PassiveStressDelta * scale)
    end

    if poorPower > 0 then
        local scale = 1 + (poorPower / 10)
        MSR.addUnhappiness(player, C.Food.PoorDietUnhappinessDelta * scale)
        MSR.addStress(player, C.Food.PoorDietStressDelta * scale)
    end

    md.MSR_LastFoodEffectTick = MSR.getGameHours()
end

registerCarryWeightModifier()

local function onEveryTenMinutes()
    registerCarryWeightModifier()

    if getOnlinePlayers then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            applyPassiveFoodEffects(players:get(i))
        end
        return
    end

    if getNumActivePlayers and getSpecificPlayer then
        for i = 0, getNumActivePlayers() - 1 do
            applyPassiveFoodEffects(getSpecificPlayer(i))
        end
    end
end

Events.EveryTenMinutes.Add(onEveryTenMinutes)
