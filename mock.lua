function UnitName(unit)
    if unit == "player" then
        return "Testplayer"
    end
end

function GetRealmName()
    return "Testrealm"
end

Frame = {}
Frame.meta = {__index = Frame}

function Frame:SetScript(...)
    print("Frame:SetScript", ...)
end

function Frame:RegisterEvent(...)
    print("Frame:RegisterEvent", ...)
end

function CreateFrame()
    local self = {}
    setmetatable(self, Frame.meta)
    return self
end

DEFAULT_CHAT_FRAME = CreateFrame()
function DEFAULT_CHAT_FRAME:AddMessage(text, red, green, blue,
                                       messageId, holdTime)
    print(text)
end

function ChatFrame_AddMessageEventFilter(...)
    print("ChatFrame_AddMessageEventFilter", ...)
end

function UIParentLoadAddOn(...)
    print("Blizzard_DebugTools", ...)
end

function RegisterAddonMessagePrefix(prefix)
    return true
end

function DevTools_Dump(t)
    require("pl.pretty").dump(t)
end
