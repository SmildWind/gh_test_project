require "MoradSurvivorRules_Config"
require "MoradSurvivorRules_Utils"
require "TimedActions/ISEatFoodAction"

local MSR = MoradSurvivorRules
local C = MSR.Config

local originalPerform = ISEatFoodAction and ISEatFoodAction.perform

local function addScore(md, key, amount)
    md[key] = (tonumber(md[key]) or 0) + amount
end

local function notifyFoodStatus(player, status, amount, effective)
    if not player or not C.UI or not C.UI.UseHaloNotifications then
        return
    end

    local textData = C.UI.Text and C.UI.Text[status]
    if not textData then
        return
    end

    local md = player:getModData()
    local now = MSR.getGameHours()
    local cooldown = tonumber(C.UI.NotificationCooldownHours) or 0
    local key = "MSR_Notify_" .. status
    if (tonumber(md[key]) or -9999) + cooldown > now then
        return
    end

    md[key] = now

    local colors = {
        ProteinFed = {120, 220, 255},
        FreshDiet = {120, 255, 150},
        ComfortMeal = {255, 220, 120},
        PoorDiet = {255, 120, 120},
    }
    local color = colors[status] or {255, 255, 255}
    local label = textData.Name or status
    local message = "[MSR] " .. label

    if amount and effective then
        message = message .. "  +" .. string.format("%.1f", amount) .. " / 当前 " .. string.format("%.1f", effective)
    end

    if player.setHaloNote then
        player:setHaloNote(message, color[1], color[2], color[3], 300)
    end
end

local function isPoorFood(item)
    if not item then return false end

    local calories = MSR.getNumber(item, "getCalories", 0)
    local proteins = MSR.getNumber(item, "getProteins", 0)
    local stale = MSR.getBool(item, "isStale")
    local rotten = MSR.getBool(item, "isRotten")
    local alcohol = MSR.getNumber(item, "getAlcoholPower", 0) > 0
    local unhappy = MSR.getNumber(item, "getUnhappyChange", 0)
    local boredom = MSR.getNumber(item, "getBoredomChange", 0)

    return rotten or stale or alcohol or (calories > 120 and proteins < 4 and unhappy >= 0 and boredom >= 0)
end

local function getFreshScore(item)
    if not item then return 0 end
    if MSR.getBool(item, "isRotten") or MSR.getBool(item, "isStale") then return 0 end

    local score = 0
    local unhappy = MSR.getNumber(item, "getUnhappyChange", 0)
    local boredom = MSR.getNumber(item, "getBoredomChange", 0)

    if unhappy < 0 then score = score + math.min(3, math.abs(unhappy) / 5) end
    if boredom < 0 then score = score + math.min(3, math.abs(boredom) / 5) end
    if item.isCooked and item:isCooked() then score = score + 1 end
    if item.getAge and item.getOffAgeMax and item:getOffAgeMax() > 0 and item:getAge() < item:getOffAgeMax() * 0.5 then
        score = score + 1
    end

    return score
end

local function isComfortMeal(item)
    if not item then return false end

    local hot = MSR.getBool(item, "isHot")
    local cooked = MSR.getBool(item, "isCooked")
    local unhappy = MSR.getNumber(item, "getUnhappyChange", 0)
    local boredom = MSR.getNumber(item, "getBoredomChange", 0)
    local name = item.getDisplayName and tostring(item:getDisplayName()) or ""
    local mealName = string.find(string.lower(name), "soup") or string.find(string.lower(name), "stew") or string.find(string.lower(name), "salad")

    return (hot or cooked) and (unhappy <= -10 or boredom <= -10 or mealName ~= nil)
end

local function applyFoodQuality(player, item, percentage)
    if not player or not item then return end

    local md = player:getModData()
    local now = MSR.getGameHours()
    local eatenRatio = tonumber(percentage) or 1
    if eatenRatio <= 0 then eatenRatio = 1 end

    if (tonumber(md[C.ModData.LastEatTime]) or 0) < now - 24 then
        md[C.ModData.ProteinScore24h] = 0
        md[C.ModData.FreshScore24h] = 0
        md[C.ModData.PoorDietScore24h] = 0
    end

    local protein = MSR.getNumber(item, "getProteins", 0) * eatenRatio
    local freshScore = getFreshScore(item) * eatenRatio
    local poor = isPoorFood(item)
    local comfort = isComfortMeal(item)

    md[C.ModData.LastEatTime] = now
    md[C.ModData.OverfullRefreshTime] = now
    addScore(md, C.ModData.ProteinScore24h, protein)
    addScore(md, C.ModData.FreshScore24h, freshScore)
    if poor then
        addScore(md, C.ModData.PoorDietScore24h, 1)
    end

    local effectiveProtein = MSR.addProteinContribution(player, protein, C.Food.ProteinFedDurationHours)
    if protein > 0 then
        MSR.log("protein contribution added: +" .. tostring(protein) .. ", effective=" .. tostring(effectiveProtein))
        notifyFoodStatus(player, "ProteinFed", protein, effectiveProtein)
    end

    local effectiveFresh = MSR.addFreshContribution(player, freshScore, C.Food.FreshDietDurationHours)
    if freshScore > 0 then
        MSR.log("fresh contribution added: +" .. tostring(freshScore) .. ", effective=" .. tostring(effectiveFresh))
        notifyFoodStatus(player, "FreshDiet", freshScore, effectiveFresh)
    end

    if comfort then
        local comfortAmount = math.max(1, freshScore)
        local effectiveComfort = MSR.addComfortContribution(player, comfortAmount, C.Food.ComfortMealDurationHours)
        MSR.log("comfort contribution added: +" .. tostring(comfortAmount) .. ", effective=" .. tostring(effectiveComfort))
        notifyFoodStatus(player, "ComfortMeal", comfortAmount, effectiveComfort)

        MSR.addStress(player, -C.Food.ComfortStressReduction)
        MSR.addUnhappiness(player, -C.Food.ComfortUnhappinessReduction)
    end

    if poor then
        local effectivePoor = MSR.addPoorDietContribution(player, 1, C.Food.PoorDietDurationHours)
        MSR.log("poor diet contribution added: +1, effective=" .. tostring(effectivePoor))
        notifyFoodStatus(player, "PoorDiet", 1, effectivePoor)
    end

    if player.transmitModData then
        player:transmitModData()
    end

    MSR.log("food quality updated for " .. tostring(player:getUsername()))
end

if originalPerform then
    function ISEatFoodAction:perform()
        local item = self.item
        local character = self.character
        local percentage = self.percentage or self.eatPercentage or 1

        originalPerform(self)
        applyFoodQuality(character, item, percentage)
    end
else
    MSR.log("ISEatFoodAction.perform not found; food quality hook inactive")
end
