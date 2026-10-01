local util = require("openmw.util")
local ui = require("openmw.ui")
local vfs = require("openmw.vfs")
local core = require("openmw.core")

local commonData = require("scripts.advanced_world_map.common")
local uiUtils = require("scripts.advanced_world_map.ui.utils")
local keyModule = require("scripts.advanced_world_map.input.keys")
local config = require("scripts.advanced_world_map.config.config")
local menuMode = require("scripts.advanced_world_map.ui.menuMode")
local menuHandler = require("scripts.advanced_world_map.menuHandler")
local realTimer = require("scripts.advanced_world_map.realTimer")

local interval = require("scripts.advanced_world_map.ui.interval")

local l10n = core.l10n(commonData.l10nKey)


local this = {}

this.menu = nil
this.menuType = nil

local function addPlus(tb)
    table.insert(tb, {
        type = ui.TYPE.Text,
        props = {
            text = l10n("+"),
            autoSize = true,
            textSize = 16,
            textColor = config.data.ui.defaultColor,
            anchor = util.vector2(0.5, 0.5),
            textAlignH = ui.ALIGNMENT.Center,
            textAlignV = ui.ALIGNMENT.Center,
        },
    })
end

local function addBtnInfoLay(tb, keyComb, str, withoutPlus)
    if not keyModule.isKeyValidToShow(keyComb) then return end

    local keys = keyModule.splitKeyCombinationSorted(keyComb)
    if not keys then return end
    local isSingle = #keys == 1

    local btnsContent = {}
    for _, key in ipairs(keys) do
        local image = keyModule.keyImage[key]
        if not image and keyModule.isDpadBtn(key) and isSingle then
            image = keyModule.keyImage["C_DPAD"]
        end

        if image and vfs.fileExists(image) then
            if not withoutPlus and next(btnsContent) then addPlus(btnsContent) end

            table.insert(btnsContent, {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture{ path = image },
                    color = config.data.ui.defaultColor,
                    size = util.vector2(1, 1) * math.floor(config.data.ui.fontSize * 1.5),
                    anchor = util.vector2(0.5, 0.5),
                },
            })

        else
            local name = keyModule.keyCombinationToString(key)
            if not withoutPlus and next(btnsContent) then addPlus(btnsContent) end

            table.insert(btnsContent, {
                type = ui.TYPE.Text,
                props = {
                    text = "["..name.."]",
                    autoSize = true,
                    textSize = 16,
                    textColor = config.data.ui.defaultColor,
                    anchor = util.vector2(0.5, 0.5),
                },
            })
        end
    end

    local lay = {
        type = ui.TYPE.Flex,
        props = {
            autoSize = true,
            horizontal = true,
            align = ui.ALIGNMENT.Center,
            arrange = ui.ALIGNMENT.Center,
            anchor = util.vector2(0.5, 0.5),
        },
        content = ui.content{
            {
                type = ui.TYPE.Flex,
                props = {
                    autoSize = true,
                    horizontal = true,
                    align = ui.ALIGNMENT.Center,
                    arrange = ui.ALIGNMENT.Center,
                    anchor = util.vector2(0.5, 0.5),
                },
                content = ui.content(btnsContent)
            },
            interval(4, 0),
            {
                type = ui.TYPE.Text,
                props = {
                    text = str,
                    autoSize = true,
                    textSize = config.data.ui.fontSize,
                    textColor = config.data.ui.defaultColor,
                    multiline = true,
                    wordWrap = false,
                    textAlignH = ui.ALIGNMENT.Start,
                    textAlignV = ui.ALIGNMENT.Center,
                    anchor = util.vector2(0.5, 0.5),
                },
            }
        }
    }

    if next(tb) then table.insert(tb, interval(10, 0)) end
    table.insert(tb, lay)
end


local lastShowOpenMenuState = nil

function this.create(showOpenMenu)
    this.destroy("main")
    if not keyModule.isGamepad or not config.data.input.gamepadControls or
        not config.data.ui.gamepadHotkeyOverlay or not menuMode:isMenuInteractive() or
        not menuHandler.getMenu(commonData.mapMenuId) then return end

    local contentTable = {}

    if showOpenMenu == nil then
        showOpenMenu = lastShowOpenMenuState
    else
        lastShowOpenMenuState = showOpenMenu
    end

    if showOpenMenu then
        if keyModule.isKeyValidToShow(config.data.main.menuKeyAlt) then
            addBtnInfoLay(contentTable, config.data.main.menuKeyAlt, l10n("GamepadActionOpenClose"))
        elseif keyModule.isKeyValidToShow(config.data.main.menuKey) then
            addBtnInfoLay(contentTable, config.data.main.menuKey, l10n("GamepadActionOpenClose"))
        end
    end

    do
        addBtnInfoLay(contentTable, config.data.input.leftStickMode and "C_LSTICK" or "C_RSTICK", l10n("GamepadActionPan"))
    end

    do
        addBtnInfoLay(
            contentTable,
            config.data.input.leftStickMode and "C_RSTICK" or
                config.data.input.gamepadControlsBumperMode and "C_LeftShoulder + C_RightShoulder" or "C_LT + C_RT",
            l10n("GamepadActionZoom"), true
        )
    end

    do
        local dpadCount = 0
        if keyModule.isDpadBtn(config.data.input.topMarkerHotkey or "") then
            dpadCount = dpadCount + 1
        end
        if keyModule.isDpadBtn(config.data.input.rightMarkerHotkey or "") then
            dpadCount = dpadCount + 1
        end
        if keyModule.isDpadBtn(config.data.input.bottomMarkerHotkey or "") then
            dpadCount = dpadCount + 1
        end
        if keyModule.isDpadBtn(config.data.input.topMarkerHotkey or "") then
            dpadCount = dpadCount + 1
        end
        if dpadCount >= 3 then
            addBtnInfoLay(contentTable, "C_DPAD", l10n("GamepadActionSelect"))
        end
    end

    addBtnInfoLay(contentTable, "C_A", l10n("GamepadActionView"))

    if config.data.input.contextMenuHotkey then
        addBtnInfoLay(contentTable, config.data.input.contextMenuHotkey, l10n("GamepadActionContextMenu"))
    end

    if config.data.input.quickMenuHotkey then
        addBtnInfoLay(contentTable, config.data.input.quickMenuHotkey, l10n("GamepadActionQuickMenu"))
    end

    addBtnInfoLay(contentTable, "C_B", l10n("GamepadActionClose"))


    local layout = {
        layer = ui.layers.indexOf("ControllerButtons") and "ControllerButtons" or commonData.messageLayer,
        name = commonData.gamepadInfoMenuId,
        props = {
            anchor = util.vector2(0.5, 1),
            relativePosition = util.vector2(0.5, 1),
            relativeSize = util.vector2(1, 0),
            size = util.vector2(0, math.max(48, config.data.ui.fontSize * 2)),
            visible = false,
        },
        content = ui.content{
            {
                type = ui.TYPE.Image,
                props = {
                    resource = uiUtils.whiteTexture,
                    relativeSize = util.vector2(1, 1),
                    color = config.data.ui.backgroundColor,
                },
            },
            {
                type = ui.TYPE.Flex,
                props = {
                    autoSize = true,
                    horizontal = true,
                    anchor = util.vector2(0.5, 0.5),
                    relativePosition = util.vector2(0.5, 0.5),
                    align = ui.ALIGNMENT.Center,
                    arrange = ui.ALIGNMENT.Center,
                },
                content = ui.content(contentTable),
            }
        }
    }

    this.menu = ui.create(layout)
    this.menuType = "main"

    realTimer.newTimer(0.25, function ()
        if this.menu and this.menu.layout then
            this.menu.layout.props.visible = true
            this.menu:update()
        end
    end)
end


function this.createNoteEdit(editMode)
    this.destroy("note")
    if not keyModule.isGamepad or not config.data.input.gamepadControls or
        not config.data.ui.gamepadHotkeyOverlay or not menuMode:isMenuInteractive() then return end

    local contentTable = {}

    do
        local dpadCount = 0
        if keyModule.isDpadBtn(config.data.input.topMarkerHotkey or "") then
            dpadCount = dpadCount + 1
        end
        if keyModule.isDpadBtn(config.data.input.rightMarkerHotkey or "") then
            dpadCount = dpadCount + 1
        end
        if keyModule.isDpadBtn(config.data.input.bottomMarkerHotkey or "") then
            dpadCount = dpadCount + 1
        end
        if keyModule.isDpadBtn(config.data.input.topMarkerHotkey or "") then
            dpadCount = dpadCount + 1
        end
        if dpadCount >= 3 then
            addBtnInfoLay(contentTable, "C_DPAD", l10n("GamepadActionNoteSelect"))
        end
    end

    addBtnInfoLay(contentTable, "C_Y", core.getGMST("sYes"))

    if editMode then
        addBtnInfoLay(contentTable, "C_X", l10n("GamepadActionNoteRemove"))
    else
        addBtnInfoLay(contentTable, "C_X", core.getGMST("sNo"))
    end

    addBtnInfoLay(contentTable, "C_A", l10n("GamepadActionNoteChange"))

    addBtnInfoLay(contentTable, "C_RightStick", l10n("GamepadActionNoteSize"))

    addBtnInfoLay(contentTable, "C_B", l10n("GamepadActionClose"))


    local layout = {
        layer = ui.layers.indexOf("ControllerButtons") and "ControllerButtons" or commonData.messageLayer,
        name = commonData.gamepadInfoMenuId,
        props = {
            anchor = util.vector2(0.5, 1),
            relativePosition = util.vector2(0.5, 1),
            relativeSize = util.vector2(1, 0),
            size = util.vector2(0, math.max(48, config.data.ui.fontSize * 2)),
            visible = false,
        },
        content = ui.content{
            {
                type = ui.TYPE.Image,
                props = {
                    resource = uiUtils.whiteTexture,
                    relativeSize = util.vector2(1, 1),
                    color = config.data.ui.backgroundColor,
                },
            },
            {
                type = ui.TYPE.Flex,
                props = {
                    autoSize = true,
                    horizontal = true,
                    anchor = util.vector2(0.5, 0.5),
                    relativePosition = util.vector2(0.5, 0.5),
                    align = ui.ALIGNMENT.Center,
                    arrange = ui.ALIGNMENT.Center,
                },
                content = ui.content(contentTable),
            }
        }
    }

    this.menu = ui.create(layout)
    this.menuType = "note"

    realTimer.newTimer(0.25, function ()
        if this.menu and this.menu.layout then
            this.menu.layout.props.visible = true
            this.menu:update()
        end
    end)
end


function this.destroy(tp)
    if not this.menu then return end
    if tp and tp ~= this.menuType then return end
    if not this.menu.layout then
        this.menu = nil
        return
    end

    this.menu:destroy()
    this.menu = nil
end


return this