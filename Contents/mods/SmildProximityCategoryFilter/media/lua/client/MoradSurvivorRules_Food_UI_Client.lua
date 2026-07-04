require "MoradSurvivorRules_Config"
require "MoradSurvivorRules_Utils"
require "ISUI/ISPanel"

local MSR = MoradSurvivorRules
local C = MSR.Config

local textures = {}
MSR.FoodStatusPanel = ISPanel:derive("MSR_FoodStatusPanel")

function MSR.FoodStatusPanel:getTextureFor(status)
    if not textures[status] then
        textures[status] = getTexture(C.UI.Icons[status])
    end
    return textures[status]
end

function MSR.FoodStatusPanel:getActiveStatuses(player)
    if not player then return {} end

    local statuses = {}
    if MSR.pruneProteinContributions(player) > 0 then table.insert(statuses, "ProteinFed") end
    if MSR.pruneFreshContributions(player) > 0 then table.insert(statuses, "FreshDiet") end
    if MSR.pruneComfortContributions(player) > 0 then table.insert(statuses, "ComfortMeal") end
    if MSR.prunePoorDietContributions(player) > 0 then table.insert(statuses, "PoorDiet") end
    return statuses
end

function MSR.FoodStatusPanel:render()
    ISPanel.render(self)
    if not C.UI.Enabled then return end

    local player = getSpecificPlayer(0)
    if not player then return end

    local statuses = self:getActiveStatuses(player)
    local size = C.UI.IconSize
    local mouseX = self:getMouseX()
    local mouseY = self:getMouseY()

    for i, status in ipairs(statuses) do
        local iconY = (i - 1) * (size + C.UI.Gap)
        local texture = self:getTextureFor(status)
        if texture then
            self:drawTextureScaled(texture, 0, iconY, size, size, 1)
        end

        if mouseX >= 0 and mouseX <= size and mouseY >= iconY and mouseY <= iconY + size then
            local text = C.UI.Text[status]
            if text then
                self:drawRect(size + 8, iconY, 360, 54, 0.8, 0, 0, 0)
                self:drawText(text.Name, size + 14, iconY + 6, 1, 1, 1, 1, UIFont.Small)
                self:drawText(text.Desc, size + 14, iconY + 26, 0.9, 0.9, 0.9, 1, UIFont.Small)
            end
        end
    end
end

function MSR.FoodStatusPanel:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.borderColor = {r=0, g=0, b=0, a=0}
    return o
end

local function createPanel()
    if not C.UI.Enabled then
        return
    end

    if MSR.FoodStatusPanel.instance then
        return
    end

    local height = (C.UI.IconSize + C.UI.Gap) * 4
    local panel = MSR.FoodStatusPanel:new(C.UI.X, C.UI.Y, 430, height)
    panel:initialise()
    panel:addToUIManager()
    MSR.FoodStatusPanel.instance = panel
end

Events.OnCreatePlayer.Add(function()
    createPanel()
end)
