MoradSurvivorRules = MoradSurvivorRules or {}

local MSR = MoradSurvivorRules

function MSR.log(message)
    if MSR.Config and MSR.Config.DebugLogging then
        print("[MoradSurvivorRules] " .. tostring(message))
    end
end

function MSR.getGameHours()
    local gt = getGameTime()
    if gt and gt.getWorldAgeHours then
        return gt:getWorldAgeHours()
    end
    return 0
end

function MSR.getPlayerKey(player)
    if not player then
        return nil
    end

    if player.getSteamID then
        local steamId = player:getSteamID()
        if steamId and tostring(steamId) ~= "0" then
            return "steam:" .. tostring(steamId)
        end
    end

    if player.getUsername then
        local username = player:getUsername()
        if username then
            return "user:" .. tostring(username)
        end
    end

    return nil
end

function MSR.getPerkId(perk)
    if not perk then
        return nil
    end

    if perk.getId then
        return tostring(perk:getId())
    end
    if perk.getName then
        return tostring(perk:getName())
    end

    return tostring(perk)
end

function MSR.getPerkLevel(player, perk)
    if not player or not perk or not player.getPerkLevel then
        return 0
    end
    return player:getPerkLevel(perk) or 0
end

function MSR.setPerkLevelNoXp(player, perk, targetLevel)
    if not player or not perk or not targetLevel then
        return false
    end

    local current = MSR.getPerkLevel(player, perk)
    local target = math.floor(tonumber(targetLevel) or current)
    if target <= current then
        return true
    end

    if player.setPerkLevelDebug then
        player:setPerkLevelDebug(perk, target)
        return true
    end

    MSR.log("setPerkLevelDebug missing; refusing to change perk level without a no-XP API")
    return false
end

function MSR.addPerkLevelsNoXp(player, perk, levels)
    local current = MSR.getPerkLevel(player, perk)
    return MSR.setPerkLevelNoXp(player, perk, current + (tonumber(levels) or 1))
end

function MSR.raisePerkToLevel(player, perk, targetLevel)
    return MSR.setPerkLevelNoXp(player, perk, targetLevel)
end

function MSR.getNumber(item, methodName, defaultValue)
    if item and item[methodName] then
        local ok, value = pcall(function() return item[methodName](item) end)
        if ok and value then
            return tonumber(value) or defaultValue or 0
        end
    end
    return defaultValue or 0
end

function MSR.getBool(item, methodName)
    if item and item[methodName] then
        local ok, value = pcall(function() return item[methodName](item) end)
        if ok then
            return value == true
        end
    end
    return false
end

function MSR.clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

function MSR.hasActive(player, expireKey)
    if not player then return false end
    local md = player:getModData()
    return (tonumber(md[expireKey]) or 0) > MSR.getGameHours()
end

function MSR.setExpire(player, expireKey, durationHours)
    if not player then return end
    local md = player:getModData()
    md[expireKey] = MSR.getGameHours() + durationHours
end

function MSR.addCharacterStat(player, stat, amount)
    if not player or not stat or not amount then
        return false
    end

    local stats = player:getStats()
    if not stats or not stats.add then
        return false
    end

    local ok = pcall(function()
        stats:add(stat, amount)
    end)

    return ok == true
end

function MSR.addBoredom(player, amount)
    if CharacterStat and CharacterStat.BOREDOM then
        return MSR.addCharacterStat(player, CharacterStat.BOREDOM, amount)
    end
    return false
end

function MSR.addUnhappiness(player, amount)
    if CharacterStat and CharacterStat.UNHAPPINESS then
        return MSR.addCharacterStat(player, CharacterStat.UNHAPPINESS, amount)
    end
    return false
end

function MSR.addStress(player, amount)
    if not player or not amount then
        return false
    end

    local stats = player:getStats()
    if not stats then
        return false
    end

    if CharacterStat and CharacterStat.STRESS and stats.add then
        local ok = pcall(function()
            stats:add(CharacterStat.STRESS, amount)
        end)
        if ok then
            return true
        end
    end

    if stats.getStress and stats.setStress then
        local ok = pcall(function()
            local current = tonumber(stats:getStress()) or 0
            stats:setStress(MSR.clamp(current + amount, 0, 1))
        end)
        return ok == true
    end

    return false
end

function MSR.addEndurance(player, amount)
    if CharacterStat and CharacterStat.ENDURANCE then
        return MSR.addCharacterStat(player, CharacterStat.ENDURANCE, amount)
    end
    return false
end

function MSR.addFatigue(player, amount)
    if CharacterStat and CharacterStat.FATIGUE then
        return MSR.addCharacterStat(player, CharacterStat.FATIGUE, amount)
    end
    return false
end

function MSR.getContributionCurveFactor(startTime, durationHours, now)
    startTime = tonumber(startTime)
    durationHours = tonumber(durationHours)
    now = tonumber(now) or MSR.getGameHours()

    if not startTime or not durationHours or durationHours <= 0 then
        return 1
    end

    local age = now - startTime
    if age <= 0 then
        return 0
    end
    if age >= durationHours then
        return 0
    end

    local foodConfig = MSR.Config and MSR.Config.Food or {}
    local rampRatio = tonumber(foodConfig.ContributionRampUpRatio) or 0.25
    local peakRatio = tonumber(foodConfig.ContributionPeakRatio) or 0.35
    local decayRatio = tonumber(foodConfig.ContributionDecayRatio) or 0.40
    local totalRatio = rampRatio + peakRatio + decayRatio
    if totalRatio <= 0 then
        return 1
    end

    rampRatio = rampRatio / totalRatio
    peakRatio = peakRatio / totalRatio
    decayRatio = decayRatio / totalRatio

    local t = age / durationHours
    if t < rampRatio then
        return MSR.clamp(t / rampRatio, 0, 1)
    end

    if t < rampRatio + peakRatio then
        return 1
    end

    local decayT = (t - rampRatio - peakRatio) / decayRatio
    return MSR.clamp(1 - decayT, 0, 1)
end

function MSR.pruneContributions(player, listKey, effectiveKey, expireKey, maxValue)
    if not player then return 0 end

    local md = player:getModData()
    local now = MSR.getGameHours()
    local contributions = md[listKey]
    if type(contributions) ~= "table" then
        contributions = {}
        md[listKey] = contributions
    end

    local active = {}
    local total = 0
    for _, contribution in ipairs(contributions) do
        local amount = tonumber(contribution.amount) or 0
        local expire = tonumber(contribution.expire) or 0
        if amount > 0 and expire > now then
            local startTime = tonumber(contribution.start)
            local durationHours = tonumber(contribution.duration)
            local factor = MSR.getContributionCurveFactor(startTime, durationHours, now)
            table.insert(active, {
                amount = amount,
                expire = expire,
                start = startTime,
                duration = durationHours,
            })
            total = total + amount * factor
        end
    end

    local cappedTotal = total
    if maxValue then
        cappedTotal = MSR.clamp(total, 0, maxValue)
    end

    md[listKey] = active
    md[effectiveKey] = cappedTotal

    if cappedTotal > 0 then
        local maxExpire = 0
        for _, contribution in ipairs(active) do
            if contribution.expire > maxExpire then
                maxExpire = contribution.expire
            end
        end
        md[expireKey] = maxExpire
    else
        md[expireKey] = 0
    end

    return cappedTotal
end

function MSR.addContribution(player, listKey, effectiveKey, expireKey, amount, durationHours, multiplier, maxValue)
    if not player then return 0 end

    amount = tonumber(amount) or 0
    if amount <= 0 then
        return MSR.pruneContributions(player, listKey, effectiveKey, expireKey, maxValue)
    end

    local md = player:getModData()
    local contributions = md[listKey]
    if type(contributions) ~= "table" then
        contributions = {}
    end

    table.insert(contributions, {
        amount = amount * (multiplier or 1.0),
        start = MSR.getGameHours(),
        duration = durationHours,
        expire = MSR.getGameHours() + durationHours,
    })

    md[listKey] = contributions
    return MSR.pruneContributions(player, listKey, effectiveKey, expireKey, maxValue)
end

function MSR.pruneProteinContributions(player)
    return MSR.pruneContributions(
        player,
        MSR.Config.ModData.ProteinContributions,
        MSR.Config.ModData.ProteinEffective,
        MSR.Config.ModData.ProteinFedExpire,
        MSR.Config.Food.ProteinEffectMax
    )
end

function MSR.addProteinContribution(player, amount, durationHours)
    return MSR.addContribution(
        player,
        MSR.Config.ModData.ProteinContributions,
        MSR.Config.ModData.ProteinEffective,
        MSR.Config.ModData.ProteinFedExpire,
        amount,
        durationHours,
        MSR.Config.Food.ProteinEffectPerPoint,
        MSR.Config.Food.ProteinEffectMax
    )
end

function MSR.pruneFreshContributions(player)
    return MSR.pruneContributions(
        player,
        MSR.Config.ModData.FreshContributions,
        MSR.Config.ModData.FreshEffective,
        MSR.Config.ModData.FreshDietExpire,
        MSR.Config.Food.FreshEffectMax
    )
end

function MSR.addFreshContribution(player, amount, durationHours)
    return MSR.addContribution(
        player,
        MSR.Config.ModData.FreshContributions,
        MSR.Config.ModData.FreshEffective,
        MSR.Config.ModData.FreshDietExpire,
        amount,
        durationHours,
        MSR.Config.Food.FreshEffectPerPoint,
        MSR.Config.Food.FreshEffectMax
    )
end

function MSR.pruneComfortContributions(player)
    return MSR.pruneContributions(
        player,
        MSR.Config.ModData.ComfortContributions,
        MSR.Config.ModData.ComfortEffective,
        MSR.Config.ModData.ComfortMealExpire,
        MSR.Config.Food.ComfortEffectMax
    )
end

function MSR.addComfortContribution(player, amount, durationHours)
    return MSR.addContribution(
        player,
        MSR.Config.ModData.ComfortContributions,
        MSR.Config.ModData.ComfortEffective,
        MSR.Config.ModData.ComfortMealExpire,
        amount,
        durationHours,
        MSR.Config.Food.ComfortEffectPerPoint,
        MSR.Config.Food.ComfortEffectMax
    )
end

function MSR.prunePoorDietContributions(player)
    return MSR.pruneContributions(
        player,
        MSR.Config.ModData.PoorDietContributions,
        MSR.Config.ModData.PoorDietEffective,
        MSR.Config.ModData.PoorDietExpire,
        MSR.Config.Food.PoorDietEffectMax
    )
end

function MSR.addPoorDietContribution(player, amount, durationHours)
    return MSR.addContribution(
        player,
        MSR.Config.ModData.PoorDietContributions,
        MSR.Config.ModData.PoorDietEffective,
        MSR.Config.ModData.PoorDietExpire,
        amount,
        durationHours,
        MSR.Config.Food.PoorDietEffectPerPoint,
        MSR.Config.Food.PoorDietEffectMax
    )
end
