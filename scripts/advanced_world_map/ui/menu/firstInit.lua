local async = require("openmw.async")
local ui = require("openmw.ui")
local util = require("openmw.util")
local core = require("openmw.core")
local I = require("openmw.interfaces")

local customTemplates = require("scripts.advanced_world_map.ui.templates")
local uiUtils = require("scripts.advanced_world_map.ui.utils")

local commonData = require("scripts.advanced_world_map.common")
local config = require("scripts.advanced_world_map.config.configLib")
local realTimer = require("scripts.advanced_world_map.realTimer")
local menuMode = require("scripts.advanced_world_map.ui.menuMode")

local borders = require("scripts.advanced_world_map.ui.borders")
local button = require("scripts.advanced_world_map.ui.button")
local interval = require("scripts.advanced_world_map.ui.interval")
local checkBox = require("scripts.advanced_world_map.ui.checkBox")


local l10n = core.l10n(commonData.l10nKey)


local this = {}

---@class advancedWorldMap.ui.menu.firstInit.params
---@field size any?
---@field relativePosition any?
---@field fontSize number?
---@field yesCallback fun()?


local function getPreviewTooltipContent(imSize, im1Id, im2Id)
    return ui.content{
        {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
            },
            content = ui.content{
                {
                    type = ui.TYPE.Widget,
                    props = {
                        size = util.vector2(imSize, imSize)
                    },
                    content = ui.content{
                        {
                            type = ui.TYPE.Image,
                            props = {
                                resource = ui.texture{ path = string.format("%s%dp.png", commonData.previewImagesDir, im1Id) },
                                size = util.vector2(imSize, imSize),
                            }
                        },
                        {
                            type = ui.TYPE.Text,
                            props = {
                                text = l10n("On"),
                                textSize = config.data.ui.fontSize * 2,
                                textColor = config.data.ui.whiteColor,
                                position = util.vector2(8, 24),
                            }
                        },
                    }
                },
                {
                    type = ui.TYPE.Widget,
                    props = {
                        size = util.vector2(imSize, imSize)
                    },
                    content = ui.content{
                        {
                            type = ui.TYPE.Image,
                            props = {
                                resource = ui.texture{ path = string.format("%s%dp.png", commonData.previewImagesDir, im2Id) },
                                size = util.vector2(imSize, imSize),
                            }
                        },
                        {
                            type = ui.TYPE.Text,
                            props = {
                                text = l10n("Off"),
                                textSize = config.data.ui.fontSize * 2,
                                textColor = config.data.ui.whiteColor,
                                position = util.vector2(8, 24),
                            }
                        },
                    }
                }
            }
        }
    }
end


---@param params advancedWorldMap.ui.menu.firstInit.params
---@return advancedWorldMap.ui.menu.firstInit
function this.new(params)
    params = params or {}

    local screenSize = uiUtils.getScaledScreenSize()

    params.fontSize = params.fontSize or config.data.ui.fontSize

    params.size = params.size or util.vector2(800, params.fontSize * (commonData.isSaveBloatFixed() and 17 or 23))
    params.relativePosition = util.vector2(0.5, 0.5)

    local previewImageSize = math.floor(screenSize.x / 4 / 128) * 128


    ---@class advancedWorldMap.ui.menu.firstInit
    local meta = setmetatable({}, {})

    meta.params = params
    meta.update = function ()
        meta.menu:update()
    end

    function meta:close()
        if not self.menu then return end
        self.menu:destroy()
        I.DijectKeyBindings.keybind.unregister("C_Y", meta.controllerBCallback, 100)
        I.DijectKeyBindings.keybind.unregister("Y", meta.controllerBCallback, 100)
    end


    local mainSize = util.vector2(params.size.x, params.size.y)

    local mainLayout
    mainLayout = {
        type = ui.TYPE.Widget,
        props = {
            size = mainSize,
        },
        userData = {

        },
        content = ui.content {
            {
                type = ui.TYPE.Image,
                props = {
                    resource = uiUtils.whiteTexture,
                    relativeSize = util.vector2(1, 1),
                    color = config.data.ui.backgroundColor,
                }
            },
            {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = false,
                    position = util.vector2(3, 0),
                },
                userData = {},
                content = ui.content{
                    {
                        type = ui.TYPE.Text,
                        props = {
                            text = l10n("firstInitMenuMessage"),
                            textSize = params.fontSize,
                            autoSize = false,
                            size = util.vector2(mainSize.x - 3, params.fontSize * 3),
                            textColor = config.data.ui.defaultColor,
                            multiline = true,
                            wordWrap = true,
                            textAlignH = ui.ALIGNMENT.Center,
                            textAlignV = ui.ALIGNMENT.Center,
                        },
                    },
                    interval(0, params.fontSize / 2),
                    checkBox{
                        updateFunc = meta.update,
                        text = l10n("SettingTilesetOnlyDiscoveredDescription").." "..l10n("HoverToPreview"),
                        textSize = config.data.ui.fontSize,
                        textElementSize = util.vector2(mainSize.x - params.fontSize * 2, params.fontSize * 2),
                        textAlignV = ui.ALIGNMENT.Center,
                        tooltipContent = getPreviewTooltipContent(previewImageSize, 1, 2),
                        tooltipDelay = 1.5,
                        checked = config.data.tileset.onlyDiscovered,
                        event = function (checked, layout)
                            config.setValue("tileset.onlyDiscovered", checked)
                        end
                    },
                    interval(0, params.fontSize / 2),
                    checkBox{
                        updateFunc = meta.update,
                        text = l10n("SettingLegendOnlyDiscoveredDescription").." "..l10n("HoverToPreview"),
                        textSize = config.data.ui.fontSize,
                        textElementSize = util.vector2(mainSize.x - params.fontSize * 2, params.fontSize * 2),
                        textAlignV = ui.ALIGNMENT.Center,
                        tooltipContent = getPreviewTooltipContent(previewImageSize, 2, 3),
                        tooltipDelay = 1.5,
                        checked = config.data.legend.onlyDiscovered,
                        event = function (checked, layout)
                            config.setValue("legend.onlyDiscovered", checked)
                        end
                    },
                    interval(0, params.fontSize / 2),
                    checkBox{
                        updateFunc = meta.update,
                        text = l10n("SettingLegendLocalMarkerBackgroundDescriptionInMenu").." "..l10n("HoverToPreview"),
                        textSize = config.data.ui.fontSize,
                        textElementSize = util.vector2(mainSize.x - params.fontSize * 2, params.fontSize * 2),
                        textAlignV = ui.ALIGNMENT.Center,
                        tooltipContent = getPreviewTooltipContent(previewImageSize, 3, 4),
                        tooltipDelay = 1.5,
                        checked = config.data.legend.localMarkerBackground,
                        event = function (checked, layout)
                            config.setValue("legend.localMarkerBackground", checked)
                        end
                    },
                    interval(0, params.fontSize / 2),
                    checkBox{
                        updateFunc = meta.update,
                        text = l10n("SettingFastTravelEnabledDescriptionInMenu"),
                        textSize = config.data.ui.fontSize,
                        textElementSize = util.vector2(mainSize.x - params.fontSize * 2, params.fontSize * 2),
                        textAlignV = ui.ALIGNMENT.Center,
                        checked = config.data.fastTravel.enabled,
                        event = function (checked, layout)
                            config.setValue("fastTravel.enabled", checked)
                        end
                    },
                    -- interval(0, params.fontSize / 2),
                    -- {
                    --     type = ui.TYPE.Text,
                    --     props = {
                    --         text = l10n("firstInitMenuDataSourceNote"),
                    --         textSize = params.fontSize,
                    --         autoSize = false,
                    --         size = util.vector2(mainSize.x - 3, params.fontSize * 3),
                    --         textColor = config.data.ui.defaultColor,
                    --         multiline = true,
                    --         wordWrap = true,
                    --         textAlignH = ui.ALIGNMENT.Center,
                    --         textAlignV = ui.ALIGNMENT.Center,
                    --     },
                    -- },
                    interval(0, params.fontSize),
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            autoSize = false,
                            horizontal = true,
                            anchor = util.vector2(0.5, 0),
                            size = util.vector2(mainSize.x - 3, params.fontSize * 2),
                            align = ui.ALIGNMENT.Center,
                            arrange = ui.ALIGNMENT.Center,
                        },
                        content = ui.content {
                            button{
                                updateFunc = meta.update,
                                textSize = params.fontSize,
                                text = l10n("YesY"),
                                event = function (layout)
                                    meta:close()
                                    if params.yesCallback then params.yesCallback() end
                                end
                            },
                        }
                    },
                },
            },
            borders(),
        },
    }

    if not commonData.isSaveBloatFixed() then
        mainLayout.content[2].content:insert(3, checkBox{
            updateFunc = meta.update,
            text = l10n("SettingSafeInitDescription"),
            textSize = config.data.ui.fontSize,
            textElementSize = util.vector2(mainSize.x - params.fontSize * 2, params.fontSize * 6),
            textAlignV = ui.ALIGNMENT.Center,
            checked = config.data.data.safeInit,
            event = function (checked, layout)
                config.setValue("data.safeInit", checked)
            end
        })
        mainLayout.content[2].content:insert(4, interval(0, params.fontSize / 2))
    end


    local layout = {
        type = ui.TYPE.Widget,
        layer = commonData.messageLayer,
        props = {
            size = params.size,
            anchor = util.vector2(0.5, 0.5),
            relativePosition = params.relativePosition,
        },
        userData = {
            meta = meta,
        },
        events = {
            mousePress = async:callback(function(coord, layout)
                layout.userData.lastMousePos = util.vector2(coord.position.x / screenSize.x, coord.position.y / screenSize.y)
            end),

            mouseRelease = async:callback(function(_, layout)
                layout.userData.lastMousePos = nil
            end),

            mouseMove = async:callback(function(coord, layout)
                if not layout.userData.lastMousePos then return end

                local props = meta.menu.layout.props
                local relativePos = util.vector2(coord.position.x / screenSize.x, coord.position.y / screenSize.y)

                props.relativePosition = props.relativePosition - (layout.userData.lastMousePos - relativePos)
                meta:update()

                layout.userData.lastMousePos = relativePos
            end),
        },
        content = ui.content {
            mainLayout,
        }
    }

    meta.controllerBCallback = function ()
        meta:close()
        if params.yesCallback then params.yesCallback() end
    end

    I.DijectKeyBindings.keybind.register("C_Y", meta.controllerBCallback, 100)
    I.DijectKeyBindings.keybind.register("Y", meta.controllerBCallback, 100)

    meta.menu = ui.create(layout)

    local function timerCallback()
        if not meta.menu.layout then return end
        if not menuMode.isMenuInteractive() then
            meta:close()
        else
            realTimer.newTimer(0.25, timerCallback)
        end
    end
    realTimer.newTimer(0.25, timerCallback)

    return meta
end


return this