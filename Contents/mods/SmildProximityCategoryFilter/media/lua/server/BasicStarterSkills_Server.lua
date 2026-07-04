local MODDATA_KEY = "BasicStarterSkills_Applied"

local STARTER_SKILLS = {
    PerkFactory.Perks.MetalWelding,
    PerkFactory.Perks.Farming,
    PerkFactory.Perks.PlantScavenging,
    PerkFactory.Perks.Woodwork,
}

local STARTER_ITEM_TYPE = "Base.HandTorch"

local function addOneLevel(player, perk)
    if not player or not perk then
        return
    end

    player:LevelPerk(perk)
end

local function addStarterItem(player)
    if not player or not player.getInventory then
        return
    end

    local inventory = player:getInventory()
    if not inventory then
        return
    end

    local item = inventory:AddItem(STARTER_ITEM_TYPE)
    if not item then
        return
    end

    if item.setUsedDelta then
        item:setUsedDelta(1.0)
    end

    if item.setActivated then
        item:setActivated(true)
    end
end

local function giveStarterSkillBonus(player)
    if not player then
        return
    end

    local modData = player:getModData()
    if modData[MODDATA_KEY] then
        return
    end

    for _, perk in ipairs(STARTER_SKILLS) do
        addOneLevel(player, perk)
    end

    addStarterItem(player)

    modData[MODDATA_KEY] = true

    local username = "unknown"
    if player.getUsername then
        username = tostring(player:getUsername())
    end
    print("[BasicStarterSkills] Applied one-time starter skill bonus to " .. username)
end

local function onCreatePlayer(playerNum, player)
    giveStarterSkillBonus(player)
end

Events.OnCreatePlayer.Remove(onCreatePlayer)
Events.OnCreatePlayer.Add(onCreatePlayer)
