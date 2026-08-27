local util = require('openmw.util')

local commonData = require("scripts.advanced_world_map.common")
local tableLib = require("scripts.advanced_world_map.utils.table")


local this = {}

---@class questGuider.config
this.default = {
    version = 20,
    main = {
        menuKey = "M",
        relativeSize = {
            x = 70,
            y = 70,
        },
        relativePosition = {
            x = 15,
            y = 15,
        },
        minimap = {
            enabled = false,
            cellLabel = true,
            bottomHeader = false,
            relativeSize = {
                x = 0.2,
                y = 0.2,
            },
            relativePosition = {
                x = 0.8,
                y = 0,
            },
        },
        charMenu = {
            relativeSize = {
                x = 0.3,
                y = 0.3,
            },
            relativePosition = {
                x = 0.7,
                y = 0,
            },
        },
        centerOnPlayer = true,
        discoveryRadius = 1500,
        updateFrequency = 30,
        firstInitMenu = true,
        fastClose = true, -- used only for initializing the pinned state
        clearCacheOnClose = true,
        overrideDefault = false,
        preserveCloseBtn = false, -- local
        saveVisibilityStateInInterfaceMenu = false, -- deprecated
        resetSizePos = false,
        zoomingMul = 1.4,
    },
    legend = {
        markerSize = 7,
        worldMarkerSize = 14,
        playerMarkerSize = 48,
        zoomToGroup = 7,
        zoomToName = 4.2,
        onlyDiscovered = true,
        visitedCellsOnWorldMap = false, -- deprecated
        transportOnlyDiscovered = false,
        localMarkerBackground = true,
        worldMarkerShadow = false,
        alpha = {
            region = 8,
            entrance = 95,
            city = 75,
            transport = 80,
            background = 65, -- local
            backgroundAlt = nil, -- local
        },
        visibility = {
            regions = true,
            cities = true,
            playerMarker = true,
            labels = true,
            markers = true,
            transport = false,
        }
    },
    tileset = {
        onlyDiscovered = true,
        visitedCellsOnWorldMap = false,
        zoomToShow = 3.5,
    },
    fastTravel = {
        enabled = false,
        onlyDiscovered = true,
        allowToInterior = false,
        withFollowers = false,
        onlyReachable = true,
        passTime = false,
        cooldown = 3,
        baseMagickaCost = 30,
        additionalCost = 4,
        currency = "FTCurrencyMagicka", -- Magicka, Gold, Health, Free
    },
    notes = {
        mapFontSize = 10,
        markerVisibility = {
            personal = true,
            global = false,
        },
        listForAllCharacters = false,
    },
    search = {
        maxObjectResults = 20,
        inInventory = true,
    },
    data = {
        initializer = commonData.dataInitializerTypes[1],
        useTilemap = false,
        safeInit = true,
        hasSafeInitMessageBeenShown = false,
        altExMapPath = nil,
        ---@type advancedWorldMap.mapImageInfo
        altExMapInfo = nil,
        altExMapAlpha = 6,
    },
    input = {
        version = 2,
        gamepadControls = true,
        gamepadControlsBumperMode = false,
        togglePinHotkey = nil,
        toggleMapTypeHotkey = nil,
        contextMenuHotkey = "C_Y",
        moveHistoryBackHotkey = "MB4",
        moveHistoryForwardHotkey = "MB5",
        toggleTransportHotkey = "C_DPadUp",
        cycleTransportHotkey = "C_DPadRight",
        validateMHotkey = nil, -- temporary
    },
    ui = {
        fontSize = 18,
        defaultColor = commonData.defaultColor,
        markerDefaultColor = commonData.markerDefaultColor,
        defaultLightColor = commonData.defaultLightColor,
        defaultDarkColor = commonData.defaultDarkColor,
        markerBackgroundColor = commonData.backgroundColor,
        markerBackgroundAltColor = commonData.backgroundColor,
        worldDefaultColor = commonData.markerDefaultColor,
        worldDefaultLightColor = commonData.defaultLightColor,
        worldDefaultDarkColor = commonData.defaultDarkColor,
        worldMarkerShadowColor = commonData.backgroundColor,
        worldMarkerShadowLightColor = commonData.backgroundColor,
        whiteColor = commonData.whiteColor,
        backgroundColor = commonData.backgroundColor,
        -- disabledColor = commonData.disabledColor,
        foundMarkerColor = commonData.foundMarkerColor,
        foundMarkerLightColor = commonData.foundMarkerLightColor,
        textShadowColor = commonData.textShadowColor,
        defaultTextureColor = commonData.defaultTextureColor,
        travelCaravanerColor = commonData.travelCaravanerColor,
        travelShipmasterColor = commonData.travelShipmasterColor,
        travelGuildGuideColor = commonData.travelGuildGuideColor,
        travelOtherColor = commonData.travelOtherColor,
        mouseScrollAmount = 36,
        headerBackgroundAlpha = 100,
        scrollArrowSize = 16,
        resizerSize = 16,
        textHeightMul = 0.7,
        worldMarkerShadow = false, -- deprecated
        alpha = 100, -- deprecated
        minimapAlpha = 100, -- deprecated
        thickBorders = true,
        coverHeader = true,
        headerSize = 18,
    },
    message = {
        transportFeatureInfoShown = 0,
        minimapFeatureInfoShown = 0,
        firstInitMenuShown = 0,
        firstInitMenuShownCurrent = 2, -- local
    }
}

this.keyToTrigger = {
    ["input.contextMenuHotkey"] = commonData.contextMenuKeyId,
    ["input.togglePinHotkey"] = commonData.togglePinKeyId,
    ["input.toggleMapTypeHotkey"] = commonData.toggleMapTypeKeyId,
    ["input.moveHistoryBackHotkey"] = commonData.moveHistoryBackKeyId,
    ["input.moveHistoryForwardHotkey"] = commonData.moveHistoryForwardKeyId,
    ["input.toggleTransportHotkey"] = commonData.toggleTransportKeyId,
    ["input.cycleTransportHotkey"] = commonData.cycleTransportKeyId,
}


---@class questGuider.config
this.data = tableLib.deepcopy(this.default)

return this