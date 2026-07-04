-- Smild Proximity Category Filter
-- Adds a row of category filter buttons to the Proximity Inventory panel

local hasProxInv, ProximityInventory = pcall(require, "ProximityInventory/ProximityInventory")

-- Helper logic to determine item category matches
local function isItemMatchFilter(item, filter)
    if filter == "All" then
        return true
    end
    
    local cat = item:getCategory()
    local displayCat = item:getDisplayCategory()
    
    if filter == "Food" then
        return cat == "Food"
    elseif filter == "Weapon" then
        return cat == "Weapon"
    elseif filter == "Tool" then
        return cat == "Tool" or displayCat == "Tools" or displayCat == "Tool"
    elseif filter == "Medical" then
        return cat == "Medical" or cat == "FirstAid" or displayCat == "Medical" or displayCat == "FirstAid"
    elseif filter == "Literature" then
        return cat == "Literature"
    elseif filter == "Ammo" then
        -- Matches Ammo display category, WeaponParts, or types containing "ammo"
        return displayCat == "Ammo" or cat == "WeaponPart" or string.find(string.lower(item:getType() or ""), "ammo") ~= nil
    elseif filter == "Material" then
        -- Matches Materials or items commonly classified as Normal that serve as crafting ingredients
        return cat == "Material" or displayCat == "Materials" or displayCat == "Material" or cat == "Normal"
    end
    
    return false
end

-- Inject hook to override ProximityInventory item population
if hasProxInv and ProximityInventory then
    local old_OnButtonsAdded = ProximityInventory.OnButtonsAdded
    if old_OnButtonsAdded then
        function ProximityInventory.OnButtonsAdded(invSelf)
            local proximityButtonRef = ProximityInventory.inventoryButtonRef[invSelf.player]
            if not proximityButtonRef then return end

            local playerNum = invSelf.player
            local playerObj = getSpecificPlayer(invSelf.player)

            -- Handle force selected
            if ProximityInventory.isForceSelected[playerNum] then
                invSelf:setForceSelectedContainer(ProximityInventory.GetItemContainer(playerNum))
            end

            -- Read active filter category
            local filter = ProximityInventory.SelectedCategoryFilter or "All"

            -- Populate matched items
            for i = 1, #invSelf.backpacks do
                local invToAdd = invSelf.backpacks[i].inventory
                if ProximityInventory.CanBeAdded(invToAdd, playerObj) then
                    local items = invToAdd:getItems()
                    if filter == "All" then
                        proximityButtonRef.inventory:getItems():addAll(items)
                    else
                        for j = 0, items:size() - 1 do
                            local item = items:get(j)
                            if item and isItemMatchFilter(item, filter) then
                                proximityButtonRef.inventory:getItems():add(item)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Inject into ISInventoryPage UI creation to add category filter buttons
local old_ISInventoryPage_createChildren = ISInventoryPage.createChildren
function ISInventoryPage:createChildren()
    old_ISInventoryPage_createChildren(self)
    
    if not hasProxInv or not ProximityInventory then
        return
    end

    -- Create horizontal panel for filter buttons
    self.proxFilterPanel = ISPanel:new(0, 34, 10, 22)
    self.proxFilterPanel:initialise()
    self.proxFilterPanel:instantiate()
    self.proxFilterPanel:setVisible(false)
    self.proxFilterPanel.background = false
    self:addChild(self.proxFilterPanel)
    
    self.proxFilterButtons = {}
    
    local categories = {"全部", "食物", "武器", "工具", "医疗", "书籍", "弹药", "材料"}
    local categoryInternal = {"All", "Food", "Weapon", "Tool", "Medical", "Literature", "Ammo", "Material"}
    
    for i = 1, #categories do
        local btn = ISButton:new(0, 0, 35, 18, categories[i], self, function()
            ProximityInventory.SelectedCategoryFilter = categoryInternal[i]
            ISInventoryPage.dirtyUI()
        end)
        btn:initialise()
        btn:instantiate()
        btn.internalCat = categoryInternal[i]
        
        btn.borderColor = {r=0.3, g=0.3, b=0.3, a=0.7}
        
        self.proxFilterPanel:addChild(btn)
        table.insert(self.proxFilterButtons, btn)
    end
    
    self.originalPaneY = self.inventorypane:getY()
end

-- Update layout and styles dynamically to fit UI size and show active filter state
local old_ISInventoryPage_update = ISInventoryPage.update
function ISInventoryPage:update()
    old_ISInventoryPage_update(self)
    
    if self.proxFilterPanel then
        local isProx = self.inventory and self.inventory:getType() == "proxInv"
        if isProx and not self.isCollapsed then
            self.proxFilterPanel:setVisible(true)
            self.inventorypane:setY(self.originalPaneY + 22)
            self.inventorypane:setHeight(self.height - self.inventorypane:getY())
            
            -- Adapt buttons layout to panel width
            local totalWidth = self.width
            self.proxFilterPanel:setWidth(totalWidth)
            
            local btnCount = #self.proxFilterButtons
            local btnW = math.floor((totalWidth - (btnCount + 1) * 2) / btnCount)
            local currentFilter = ProximityInventory.SelectedCategoryFilter or "All"
            
            for i = 1, btnCount do
                local btn = self.proxFilterButtons[i]
                local x = 2 + (i - 1) * (btnW + 2)
                btn:setX(x)
                btn:setWidth(btnW)
                
                -- Highlight active filter, dim others
                if btn.internalCat == currentFilter then
                    btn.backgroundColor = {r=0.15, g=0.4, b=0.25, a=0.9} -- Vibrant Forest Green for active state
                    btn.textColor = {r=1.0, g=1.0, b=1.0, a=1.0}
                else
                    btn.backgroundColor = {r=0.15, g=0.15, b=0.15, a=0.8} -- Sleek dark background
                    btn.textColor = {r=0.8, g=0.8, b=0.8, a=0.9}
                end
            end
        else
            self.proxFilterPanel:setVisible(false)
            if self.originalPaneY then
                self.inventorypane:setY(self.originalPaneY)
                self.inventorypane:setHeight(self.height - self.inventorypane:getY())
            end
        end
    end
end
