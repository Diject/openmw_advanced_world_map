local async = require('openmw.async')
local world = require('openmw.world')
local types = require("openmw.types")
local core = require("openmw.core")

local config = require("scripts.advanced_world_map.config.config")

local tableLib = require("scripts.advanced_world_map.utils.table")
local stringLib = require("scripts.advanced_world_map.utils.string")

local log = require("scripts.advanced_world_map.utils.log")

local common = require("scripts.advanced_world_map.common")

local dynamicDataHandler = require("scripts.advanced_world_map.dynamicDataHandler")

local l10n = core.l10n(common.l10nKey)


dynamicDataHandler.init()


return {
    engineHandlers = {

    },
    eventHandlers = {
        ["AdvWMap:updateConfigData"] = function (data)
            tableLib.applyChanges(config.data, data)
        end,
    },
}