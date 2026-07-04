require "MoradSurvivorRules_Config"
require "MoradSurvivorRules_Utils"

local MSR = MoradSurvivorRules
local C = MSR.Config

MSR.log("continuity server module loaded")

local function getStore()
    return ModData.getOrCreate(C.ServerModDataKey)
end

local function applyStarterSkills(player)
    local md = player:getModData()
    if md[C.ModData.StarterApplied] then
        return
    end

    for _, perk in pairs(C.StarterSkills) do
        if perk then
            MSR.raisePerkToLevel(player, perk, 1)
        end
    end

    md[C.ModData.StarterApplied] = true
    MSR.log("starter crafting skills raised to level 1 for " .. tostring(player:getUsername()) .. " without XP changes")
end

local function collectSkillLevels(player)
    local levels = {}
    for _, perk in pairs(C.VanillaSkills) do
        if perk then
            local id = MSR.getPerkId(perk)
            if id then
                levels[id] = MSR.getPerkLevel(player, perk)
            end
        end
    end
    return levels
end

local function recordDeath(player)
    local key = MSR.getPlayerKey(player)
    if not key then
        MSR.log("death record skipped: missing player key")
        return
    end

    local store = getStore()
    store[key] = {
        consumed = false,
        timestamp = MSR.getGameHours(),
        username = player:getUsername(),
        skills = collectSkillLevels(player),
    }

    if ModData and ModData.add then
        ModData.add(C.ServerModDataKey, store)
    end

    MSR.log("death skills recorded for " .. key)
end

local function applyContinuity(player)
    local md = player:getModData()
    if md[C.ModData.ContinuityApplied] then
        return
    end

    local key = MSR.getPlayerKey(player)
    if not key then
        return
    end

    local store = getStore()
    local record = store[key]
    if not record or record.consumed or not record.skills then
        return
    end

    for _, perk in pairs(C.VanillaSkills) do
        local id = MSR.getPerkId(perk)
        local deadLevel = tonumber(record.skills[id] or 0) or 0
        if deadLevel > 0 then
            local inheritedLevel = math.max(1, deadLevel - 1)
            local currentLevel = MSR.getPerkLevel(player, perk)
            if inheritedLevel > currentLevel then
                MSR.raisePerkToLevel(player, perk, inheritedLevel)
            end
        end
    end

    record.consumed = true
    record.consumedAt = MSR.getGameHours()
    md[C.ModData.ContinuityApplied] = true

    if ModData and ModData.add then
        ModData.add(C.ServerModDataKey, store)
    end

    MSR.log("death continuity applied to " .. key)
end

local function onCreatePlayer(playerNum, player)
    if not player then return end

    applyStarterSkills(player)
    applyContinuity(player)
end

local function checkOnlinePlayers()
    if getOnlinePlayers then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            local player = players:get(i)
            if player then
                applyStarterSkills(player)
                applyContinuity(player)
            end
        end
        return
    end

    if getNumActivePlayers and getSpecificPlayer then
        for i = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(i)
            if player then
                applyStarterSkills(player)
                applyContinuity(player)
            end
        end
    end
end

Events.OnCreatePlayer.Add(onCreatePlayer)
Events.EveryOneMinute.Add(checkOnlinePlayers)

if Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(recordDeath)
end

if Events.OnCharacterDeath then
    Events.OnCharacterDeath.Add(function(character)
        if character and character.isPlayer and character:isPlayer() then
            recordDeath(character)
        end
    end)
end
