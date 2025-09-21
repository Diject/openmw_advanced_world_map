
local this = {}

---@type table<string, any>
this.activeMenus = {}


function this.registerMenu(menuId, menu)
    if this.activeMenus[menuId] then
        for id, handler in pairs(this.activeMenus) do
            handler.menu:destroy()
            this.activeMenus[id] = nil
        end
    end

    this.activeMenus[menuId] = menu
end


function this.getMenu(menuId)
    return this.activeMenus[menuId]
end


function this.destroyAllMenus()
    for id, handler in pairs(this.activeMenus) do
        handler.menu:destroy()
        this.activeMenus[id] = nil
    end
end


function this.onMouseReleaseCallback(buttonId)
    for _, menu in pairs(this.activeMenus) do
        if menu.onMouseClick then
            menu:onMouseClick(buttonId)
        end
    end
end


function this.onMouseWheelCallback(vertical)
    for _, menu in pairs(this.activeMenus) do
        menu:onMouseWheel(vertical)
    end
end


return this