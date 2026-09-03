local core = require("openmw.core")

local dialogue = core.dialogue

local this = {}

function this.getDialogueTopicInfo(diaId, infoId)
    if not dialogue then return end

    local dia = dialogue.topic.records[diaId] or dialogue.greeting.records[diaId]
    if not dia then return end

    for _, info in pairs(dia.infos or {}) do
        if info.id == infoId then
            return info
        end
    end
end


return this