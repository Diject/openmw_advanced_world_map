local ui = require("openmw.ui")
local util = require("openmw.util")
local core = require("openmw.core")
local playerRef = require("openmw.self")

local config = require("scripts.advanced_world_map.config.configLib")
local dynamicDataHandler = require("scripts.advanced_world_map.dynamicDataHandler")

local eventSys = require("scripts.advanced_world_map.eventSys")


local this = {}


local nameLayout

function this.updateLabel(mapWidget)
    if not nameLayout or not mapWidget then return end
    local text
    if mapWidget.cellId then
        local cellName = dynamicDataHandler.cellNameById[mapWidget.cellId]
        if cellName then
            text = string.format(" %s ", cellName)
        end
    elseif playerRef.cell.isExterior then
        local cellName = dynamicDataHandler.cellNameById[playerRef.cell.id]
        if cellName then
            text = string.format(" %s ", cellName)
        end
    end
    nameLayout.props.text = text or ""
end


---@param menu advancedWorldMap.ui.menu.map
local function create(menu)

    nameLayout = {
        type = ui.TYPE.Text,
        props = {
            text = "",
            textSize = menu.headerHeight - 6,
            anchor = util.vector2(0.5, 0.5),
            textColor = config.data.ui.defaultColor,
        },
    }
    this.updateLabel(menu.mapWidget)


    menu:addWidget{
        id = "AdvancedWorldMap:CellName",
        layout = nameLayout,
        showWhenMenuInactive = true,
    }

end


eventSys.registerHandler(eventSys.events.onMapShown, function (e)
    this.updateLabel(e.mapWidget)
end)

eventSys.registerHandler(eventSys.events.onMenuOpened, function (e)
    create(e.menu)
end, -1000)


return this