local async = require("openmw.async")
local ui = require("openmw.ui")
local util = require("openmw.util")
local core = require("openmw.core")
local I = require("openmw.interfaces")
local storage = require("openmw.storage")

local customTemplates = require("scripts.advanced_world_map.ui.templates")
local uiUtils = require("scripts.advanced_world_map.ui.utils")

local commonData = require("scripts.advanced_world_map.common")
local config = require("scripts.advanced_world_map.config.configLib")
local realTimer = require("scripts.advanced_world_map.realTimer")
local menuMode = require("scripts.advanced_world_map.ui.menuMode")
local menuHandler = require("scripts.advanced_world_map.menuHandler")

local tooltip = require("scripts.advanced_world_map.ui.tooltip")
local borders = require("scripts.advanced_world_map.ui.borders")
local button = require("scripts.advanced_world_map.ui.button")
local interval = require("scripts.advanced_world_map.ui.interval")
local checkBox = require("scripts.advanced_world_map.ui.checkBox")

local mapMenu = require("scripts.advanced_world_map.ui.menu.map")


local l10n = core.l10n(commonData.l10nKey)


local this = {}

---@class advancedWorldMap.ui.menu.firstInit.params
---@field size any?
---@field relativePosition any?
---@field fontSize number?
---@field yesCallback fun()?


local function getPreviewTooltipContent(imSize, imageIds, labels)
    labels = labels or {"On", "Off"}

    local content = ui.content{
        {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
            },
            content = ui.content{}
        }
    }

    for i, imId in ipairs(imageIds) do
        content[1].content:add{
            type = ui.TYPE.Widget,
            props = {
                size = util.vector2(imSize, imSize)
            },
            content = ui.content{
                {
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture{ path = string.format("%s%dp.png", commonData.previewImagesDir, imId) },
                        size = util.vector2(imSize, imSize),
                    }
                },
                {
                    type = ui.TYPE.Text,
                    props = {
                        text = l10n(labels[i] or ""),
                        textSize = config.data.ui.fontSize * 1.75,
                        textColor = config.data.ui.whiteColor,
                        position = util.vector2(8, imSize * 0.05),
                    }
                },
            }
        }
    end

    return content
end


local function HoverToPreviewBlock(imSize, imageIds, labels, cbLayout)
    local tooltipContent = getPreviewTooltipContent(imSize, imageIds, labels)
    return {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            arrange = ui.ALIGNMENT.Center,
        },
        content = ui.content {
            cbLayout,
            {
                type = ui.TYPE.Text,
                props = {
                    text = l10n("HoverToPreview"),
                    textSize = config.data.ui.fontSize,
                    textColor = config.data.ui.defaultColor,
                    size = util.vector2(80, config.data.ui.fontSize * 2),
                    textAlignV = ui.ALIGNMENT.Center,
                    textAlignH = ui.ALIGNMENT.Center,
                    multiline = true,
                },
                events = {
                    mouseMove = async:callback(function(e, layout)
                        tooltip.createOrMove(e, layout, tooltipContent)
                    end),

                    focusLoss = async:callback(function(e, layout)
                        tooltip.destroy(layout)
                    end),
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
    local isGridmapPresent = core.contentFiles.has(commonData.gridmapModFileName)

    params.fontSize = params.fontSize or config.data.ui.fontSize

    local heightInFontSizes = commonData.isSaveBloatFixed() and 19 or 24.5
    heightInFontSizes = isGridmapPresent and heightInFontSizes + 2 or heightInFontSizes
    params.size = params.size or util.vector2(800, params.fontSize * heightInFontSizes)
    params.relativePosition = util.vector2(0.5, 0.5)

    local previewImageSize = math.floor(screenSize.x / 4 / 32) * 32
    local previewAltImageSize = math.floor(screenSize.x / 6 / 32) * 32


    ---@class advancedWorldMap.ui.menu.firstInit
    local meta = setmetatable({}, {})

    meta.params = params
    meta.update = function ()
        meta.menu:update()
    end

    function meta:close()
        if not self.menu then return end
        if params.yesCallback then params.yesCallback() end
        self.menu:destroy()
        I.DijectKeyBindings.keybind.unregister("C_Y", meta.controllerBCallback, 100)
        I.DijectKeyBindings.keybind.unregister("Y", meta.controllerBCallback, 100)
    end


    local mainSize = util.vector2(params.size.x, params.size.y)

    local longHorizontalLineThin = {
        props = {
            size = util.vector2(mainSize.x, math.floor(params.fontSize * 0.5))
        },
        content = ui.content{
            {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture{ path = "textures/menu_thin_border_top.dds" },
                    tileH = true,
                    tileV = false,
                    size = util.vector2(0, 1),
                    relativeSize = util.vector2(1, 0),
                    anchor = util.vector2(0, 0.5),
                    relativePosition = util.vector2(0, 0.5),
                },
            }
        }
    }


    local ftCurrencyLayout = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            align = ui.ALIGNMENT.Center,
        },
        content = ui.content {
            {
                type = ui.TYPE.Text,
                props = {
                    text = l10n("FirstInitFastTravelCurrency"),
                    textSize = params.fontSize,
                    textColor = config.data.ui.defaultColor,
                    autoSize = true,
                },
            },
            interval(10, params.fontSize * 1.5),
            button{
                updateFunc = meta.update,
                textSize = params.fontSize,
                text = l10n(config.data.fastTravel.currency),
                event = function (layout)
                    local currentIndex = 1
                    for i, currency in ipairs(commonData.fastTravelCurrencyTypes) do
                        if currency == config.data.fastTravel.currency then
                            currentIndex = i
                            break
                        end
                    end

                    local nextIndex = currentIndex + 1
                    if nextIndex > #commonData.fastTravelCurrencyTypes then
                        nextIndex = 1
                    end

                    local nextCurrency = commonData.fastTravelCurrencyTypes[nextIndex]
                    if nextCurrency == "FTCurrencyMagicka" then
                        config.setValue("fastTravel.passTime", false)
                    else
                        config.setValue("fastTravel.passTime", true)
                    end

                    config.setValue("fastTravel.currency", nextCurrency)

                    layout.content[1].content[1].props.text = l10n(nextCurrency)
                    meta:update()
                end
            },
        }
    }


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
                            size = util.vector2(mainSize.x - 3, params.fontSize * 2),
                            textColor = config.data.ui.defaultColor,
                            multiline = true,
                            wordWrap = true,
                            textAlignH = ui.ALIGNMENT.Center,
                            textAlignV = ui.ALIGNMENT.Start,
                        },
                    },
                    longHorizontalLineThin,
                    HoverToPreviewBlock(previewImageSize, {5, 6}, nil, checkBox{
                        updateFunc = meta.update,
                        text = l10n("SettingUseTilemapDescriptionInMenu"),
                        textSize = params.fontSize,
                        textElementSize = util.vector2(mainSize.x - params.fontSize * 2 - 80, params.fontSize * 2),
                        textAlignV = ui.ALIGNMENT.Center,
                        anchor = util.vector2(0, 0.5),
                        checked = config.data.data.useTilemap,
                        event = function (checked, layout)
                            config.setValue("data.useTilemap", checked)
                            if checked then
                                config.setValue("legend.worldMarkerShadow", true)
                                config.setValue("legend.alpha.city", 80)
                            else
                                config.setValue("legend.worldMarkerShadow", false)
                                config.setValue("legend.alpha.city", 70)
                            end
                        end
                    }),
                    longHorizontalLineThin,
                    HoverToPreviewBlock(previewImageSize, {1, 2}, nil, checkBox{
                        updateFunc = meta.update,
                        text = l10n("SettingTilesetOnlyDiscoveredDescription"),
                        textSize = params.fontSize,
                        textElementSize = util.vector2(mainSize.x - params.fontSize * 2 - 80, params.fontSize * 2),
                        textAlignV = ui.ALIGNMENT.Center,
                        anchor = util.vector2(0, 0.5),
                        checked = config.data.tileset.onlyDiscovered,
                        event = function (checked, layout)
                            config.setValue("tileset.onlyDiscovered", checked)
                        end
                    }),
                    longHorizontalLineThin,
                    HoverToPreviewBlock(previewImageSize, {2, 3}, nil, checkBox{
                        updateFunc = meta.update,
                        text = l10n("SettingLegendOnlyDiscoveredDescription"),
                        textSize = params.fontSize,
                        textElementSize = util.vector2(mainSize.x - params.fontSize * 2 - 80, params.fontSize * 2),
                        textAlignV = ui.ALIGNMENT.Center,
                        checked = config.data.legend.onlyDiscovered,
                        event = function (checked, layout)
                            config.setValue("legend.onlyDiscovered", checked)
                        end
                    }),
                    longHorizontalLineThin,
                    HoverToPreviewBlock(previewImageSize, {3, 4}, nil, checkBox{
                        updateFunc = meta.update,
                        text = l10n("SettingLegendLocalMarkerBackgroundDescriptionInMenu"),
                        textSize = params.fontSize,
                        textElementSize = util.vector2(mainSize.x - params.fontSize * 2 - 80, params.fontSize * 2),
                        textAlignV = ui.ALIGNMENT.Center,
                        checked = config.data.legend.localMarkerBackground,
                        event = function (checked, layout)
                            config.setValue("legend.localMarkerBackground", checked)
                        end
                    }),
                    longHorizontalLineThin,
                    checkBox{
                        updateFunc = meta.update,
                        text = l10n("SettingFastTravelEnabledDescriptionInMenu"),
                        textSize = params.fontSize,
                        textElementSize = util.vector2(mainSize.x - params.fontSize * 2, params.fontSize * 2),
                        textAlignV = ui.ALIGNMENT.Center,
                        checked = config.data.fastTravel.enabled,
                        event = function (checked, layout)
                            config.setValue("fastTravel.enabled", checked)
                        end
                    },
                    interval(0, params.fontSize / 2),
                    ftCurrencyLayout,
                    longHorizontalLineThin,
                },
            },
            {
                type = ui.TYPE.Flex,
                props = {
                    autoSize = false,
                    horizontal = true,
                    anchor = util.vector2(0.5, 1),
                    relativePosition = util.vector2(0.5, 1),
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
                            -- if params.yesCallback then params.yesCallback() end
                        end
                    },
                }
            },
            borders(),
        },
    }

    if isGridmapPresent then
        local gridmapStorage = storage.playerSection(commonData.gridmapSettingSectionName)
        local function getCurrentType()
            local isEnambed = gridmapStorage:get("enableOldMapOverlay")
            local alpha = gridmapStorage:get("oldMapOverlayAlpha")
            if isEnambed == false or (alpha or 9) == 0 then
                return "FirstInitGridmapPresetOff"
            elseif alpha < 90 then
                return "FirstInitGridmapPresetTransparent"
            else
                return "FirstInitGridmapPresetOpaque"
            end
        end

        local function resetGridmapColorSettingsToDefault()
            config.data.ui.worldDefaultColor = util.color.rgb(0, 0, 0)
            gridmapStorage:set("worldDefaultColor", config.data.ui.worldDefaultColor)
            config.data.ui.worldDefaultDarkColor = util.color.rgb(0.15, 0.15, 0)
            gridmapStorage:set("worldDefaultDarkColor", config.data.ui.worldDefaultDarkColor)
            config.data.ui.worldMarkerShadowLightColor = util.color.rgb(0.760784, 0.631372, 0.494117)
            gridmapStorage:set("worldMarkerShadowLightColor", config.data.ui.worldMarkerShadowLightColor)
            config.data.ui.markerBackgroundAltColor = util.color.rgb(0.55, 0.55, 0.55)
            gridmapStorage:set("markerBackgroundColor", config.data.ui.markerBackgroundAltColor)
            config.data.legend.alpha.backgroundAlt = 80
            gridmapStorage:set("alpha.background", config.data.legend.alpha.backgroundAlt)
        end

        local function setNextType()
            mapMenu.clearMapWidgetCache()
            local isEnambed = gridmapStorage:get("enableOldMapOverlay")
            local alpha = gridmapStorage:get("oldMapOverlayAlpha")
            if isEnambed == false or (alpha or 10) == 0 then
                gridmapStorage:set("enableOldMapOverlay", true)
                gridmapStorage:set("oldMapOverlayAlpha", 10)
                resetGridmapColorSettingsToDefault()
            elseif alpha < 90 then
                gridmapStorage:set("enableOldMapOverlay", true)
                gridmapStorage:set("oldMapOverlayAlpha", 100)
                config.data.ui.worldDefaultColor = commonData.defaultColor
                gridmapStorage:set("worldDefaultColor", config.data.ui.worldDefaultColor)
                config.data.ui.worldDefaultDarkColor = commonData.defaultDarkColor
                gridmapStorage:set("worldDefaultDarkColor", config.data.ui.worldDefaultDarkColor)
                config.data.ui.worldMarkerShadowLightColor = util.color.rgb(0, 0, 0)
                gridmapStorage:set("worldMarkerShadowLightColor", config.data.ui.worldMarkerShadowLightColor)
                config.data.ui.markerBackgroundAltColor = config.default.ui.markerBackgroundColor
                gridmapStorage:set("markerBackgroundColor", config.data.ui.markerBackgroundAltColor)
                config.data.legend.alpha.backgroundAlt = config.default.legend.alpha.background
                gridmapStorage:set("alpha.background", config.data.legend.alpha.backgroundAlt)
            else
                gridmapStorage:set("enableOldMapOverlay", false)
                resetGridmapColorSettingsToDefault()
            end
        end

        mainLayout.content[2].content:insert(4, HoverToPreviewBlock(
            previewAltImageSize,
            {7, 8, 9},
            {"FirstInitGridmapPresetOff", "FirstInitGridmapPresetTransparent", "FirstInitGridmapPresetOpaque"},
            {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                    autoSize = false,
                    size = util.vector2(mainSize.x - params.fontSize * 1 - 74, params.fontSize * 2),
                    align = ui.ALIGNMENT.Center,
                    arrange = ui.ALIGNMENT.Center
                },
                content = ui.content{
                    {
                        type = ui.TYPE.Text,
                        props = {
                            text = l10n("FirstInitGridmapMessage"),
                            textSize = params.fontSize,
                            textColor = config.data.ui.defaultColor,
                            autoSize = false,
                            size = util.vector2(mainSize.x - params.fontSize * 1 - 174, params.fontSize * 3),
                            anchor = util.vector2(0.5, 0.5),
                            multiline = true,
                            wordWrap = true,
                            textAlignH = ui.ALIGNMENT.Start,
                            textAlignV = ui.ALIGNMENT.Center,
                        }
                    },
                    button{
                        updateFunc = meta.update,
                        textSize = params.fontSize * 0.8,
                        anchor = util.vector2(0.5, 0.5),
                        text = l10n(getCurrentType()),
                        event = function (layout)
                            setNextType()

                            layout.content[1].content[1].props.text = l10n(getCurrentType())
                            meta:update()
                        end
                    },
                }
            }
        ))
    end

    if not commonData.isSaveBloatFixed() then
        mainLayout.content[2].content:insert(3, checkBox{
            updateFunc = meta.update,
            text = l10n("SettingSafeInitDescription"),
            textSize = params.fontSize,
            textElementSize = util.vector2(mainSize.x - params.fontSize * 2, params.fontSize * 5),
            textAlignV = ui.ALIGNMENT.Center,
            checked = config.data.data.safeInit,
            event = function (checked, layout)
                config.setValue("data.safeInit", checked)
            end
        })
        mainLayout.content[2].content:insert(4, longHorizontalLineThin)
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