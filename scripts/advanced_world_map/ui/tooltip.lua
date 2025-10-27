local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local core = require('openmw.core')
local time = require('openmw_aux.time')
local UI = require('openmw.interfaces').UI
local customTemplates = require("scripts.advanced_world_map.ui.templates")
local uiUtils = require("scripts.advanced_world_map.ui.utils")

local this = {}

function this.calcTooltipPosAnchor(cursorPos)
    local screenSize = uiUtils.getScaledScreenSize()

    local halfWidth = screenSize.x / 2
    local halfHeight = screenSize.y / 2

    local anchorX = cursorPos.x > halfWidth and 1 or 0
    local anchorY = cursorPos.y > halfHeight and 1 or 0
    local anchor = util.vector2 (anchorX, anchorY)

    local posX = cursorPos.x
    if anchorX <= 0 and anchorY <= 0 then
        posX = posX + 30
    end
    local tooltipPos = util.vector2(posX, cursorPos.y)

    return tooltipPos, anchor
end

---@return boolean? new
function this.createOrMove(coord, parent, layoutContent)
    if not parent.userData then parent.userData = {} end

    local position, anchor = this.calcTooltipPosAnchor(coord.position)

    if not parent.userData.tooltip then
        if not layoutContent or #layoutContent == 0 then return end

        local tooltipLayout = {
            template = customTemplates.boxSolid,
            layer = "Notification",
            name = "QGL:tooltip",
            props = {
                position = position,
                anchor = anchor,
            },
            content = ui.content {
                {
                    type = ui.TYPE.Flex,
                    props = {
                        horizontal = false,
                        align = ui.ALIGNMENT.Center,
                    },
                    content = layoutContent,
                }
            }
        }

        parent.userData["tooltip"] = ui.create(tooltipLayout)

        if core.isWorldPaused() then
            local timer = async:newUnsavableSimulationTimer(0.1, function ()
                if not parent.userData.tooltip then return end
                local tooltipHandler = parent.userData.tooltip
                parent.userData.tooltip = nil
                tooltipHandler:destroy()
            end)
        else
            local timer
            timer = time.runRepeatedly(function ()
                if UI.getMode() == nil then
                    timer()
                    if not parent.userData.tooltip then return end
                    local tooltipHandler = parent.userData.tooltip
                    parent.userData.tooltip = nil
                    tooltipHandler:destroy()
                end
            end, 0.2)
        end

        return true
    end


    if not parent.userData.tooltip then return end

    local props = parent.userData.tooltip.layout.props

    props.position, props.anchor = position, anchor

    parent.userData.tooltip:update()
end


function this.destroy(parent)
    if not parent.userData or not parent.userData.tooltip then return end
    local tooltipHandler = parent.userData.tooltip
    parent.userData.tooltip = nil
    tooltipHandler:destroy()
end


function this.isExists(parent)
    return parent and parent.userData and parent.userData.tooltip and parent.userData.tooltip.valid
end


function this.get(parent)
    return parent and parent.userData and parent.userData.tooltip
end


return this