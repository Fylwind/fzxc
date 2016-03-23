-- Debugging utilities
-- ===================

local DEBUG

-- Prints a diagnostic message.  This is suppressed if `DEBUG` is false-like.
local function dprint(...)
    if DEBUG then
        print("fzxc:", ...)
    end
end

-- Dumps the contents of a table.
local function dump(var)
    if DEBUG then
        UIParentLoadAddOn("Blizzard_DebugTools")
        DevTools_Dump(var)
    end
end

------------------------------------------------------------------------------

local ipairs = ipairs
local pairs = pairs
local unpack = unpack

local string_find = string.find
local string_format = string.format
local string_lower = string.lower
local string_gmatch = string.gmatch
local string_gsub = string.gsub
local string_match = string.match
local string_sub = string.sub

local BNGetFriendInfo = BNGetFriendInfo
local BNGetFriendIndex = BNGetFriendIndex
local BNGetNumFriends = BNGetNumFriends
local BNGetGameAccountInfo = BNGetGameAccountInfo
local GetChannelName = GetChannelName
local GetChannelList = GetChannelList
local GetIgnoreName = GetIgnoreName
local GetNumIgnores = GetNumIgnores
local GetTime = GetTime
local SlashCmdList_JOIN = SlashCmdList["JOIN"]
local SendChatMessage = SendChatMessage
local UnitFactionGroup = UnitFactionGroup

local FZMP = FZMP
local FZMP_SendMessage = FZMP.SendMessage
local FZMP_RegisterMessageListener = FZMP.RegisterMessageListener
local FZMP_UnregisterMessageListener = FZMP.UnregisterMessageListener

local playerName = UnitName("player")
local playerRealm = GetRealmName()
local playerFaction
local playerNameRealm = string_format("%s-%s", playerName,
                                      string_gsub(playerRealm, " ", ""))

local version = "@project-version@"
local timestamp = tonumber("@project-timestamp@")
local frame = CreateFrame("Frame")
local messageArchive = {}

-- Localization placeholder
local L = function(...) return ... end

-- Prints the `text` in a special color.  Each line is printed as a separated
-- message.
local function cprint(text)
    for line in string_gmatch(text .. "\n", "([^\n]*)\n") do
        DEFAULT_CHAT_FRAME:AddMessage(line, .7, 1, .4)
    end
end

-- Prints a message with formatted arguments.
local function cprintf(format, ...)
    cprint(string_format(format, ...))
end

-- Prints an error message with formatted arguments.
local function cerrorf(format, ...)
    cprintf(L"fzxc: |cffff3300error:|r %s", string_format(format, ...))
end

-- Prints a warning message with formatted arguments.
local function cwarnf(format, ...)
    cprintf(L"fzxc: |cffff9900warning:|r %s", string_format(format, ...))
end

local isConnectedRealm
local function isConnectedRealm_init()
    if isConnectedRealm ~= nil then
        return
    end
    isConnectedRealm = {[string_gsub(playerRealm, " ", "")] = true}
    local connectedRealms = GetAutoCompleteRealms()
    if connectedRealms == nil then
        return
    end
    for _, realm in ipairs(connectedRealms) do
        isConnectedRealm[realm] = true
    end
end

local sources
local function updateSources()
    isConnectedRealm_init()
    sources = {}
    for friendIndex = 1, BNGetNumFriends() do
        local bnetIDAccount, _, _, _, _, bnetIDGameAccount, client, _, _, _, _, _, note
            = BNGetFriendInfo(friendIndex)
        if note then
            for source, separator, dest in string_gmatch(
                string_lower(note),
                "#([^:#%s]+)(:?)([^:#%s]*)")
            do
                if separator ~= ":" then
                    dest = source
                end
                local dests = sources[source]
                if not dests then
                    dests = {}
                    sources[source] = dests
                end
                local bnetIDAccounts = dests[dest]
                if not bnetIDAccounts then
                    bnetIDAccounts = {}
                    dests[dest] = bnetIDAccounts
                end

                local online = false
                if bnetIDGameAccount ~= nil and bnetIDGameAccount ~= 0 then
                    local _, name, _, realm, _, faction = BNGetGameAccountInfo(bnetIDGameAccount)
                    if client == "WoW" and (not isConnectedRealm[realm] or
                                            faction ~= playerFaction) then
                        bnetIDAccounts[bnetIDAccount] = {
                            connected = true,
                            name = name,
                            realm = realm,
                            faction = faction,
                            bnetIDGameAccount = bnetIDGameAccount
                        }
                        online = true
                    end
                end

                if not online then
                    bnetIDAccounts[bnetIDAccount] = { connected = false }
                end
            end
        end
    end
end

local ignoreList = {}
local function updateIgnoreList()
    ignoreList = {}
    for i = 1, GetNumIgnores() do
        ignoreList[GetIgnoreName(i)] = true
    end
end

-- Ensure message is not just another duplicate from a different player
local function checkMessageSent(bnetIDGameAccount, counter, sender, channel, text)
    dprint(bnetIDGameAccount)
    local hash = string_format("%s#%s#%s", channel, sender, text)
    local archive = messageArchive
    local messages = archive[hash]
    if not messages then
        archive[hash] = {{bnetIDGameAccount = bnetIDGameAccount, time = GetTime()}}
        return
    end
    for _, message in pairs(messages) do
        if message.bnetIDGameAccount ~= bnetIDGameAccount then
            -- Message sent by a different player which we'll ignore since
            -- it's most likely a duplicate (it's hard to tell)
            return true
        end
        break
    end
    if messages[counter] then
        -- Probably a duplicate message from the same player (?)
        -- or maybe the player's client got reset somehow
        -- (Assuming the former case ...)
        return true
    end
    messages[counter] = {bnetIDGameAccount = bnetIDGameAccount, time = GetTime()}
end

local versionChecked
local function checkVersion(data, data2)
    if versionChecked then
        return
    end
    local otherTimestamp = tonumber(data2)
    if timestamp and otherTimestamp and timestamp < otherTimestamp then
        cprintf(L"fzxc: a new version (%s) is available.", data)
        versionChecked = true
    end
end

local ECHO_REQUEST = 1
local ECHO_REPLY = 2
local VERSION_REQUEST = 3
local VERSION_REPLY = 4

local function replyMessage(bnetIDGameAccount, request, data, _, data2)
    dprint("replyMessage: ")
    dump({bnetIDGameAccount, destID, request, data, data2})
    request = tonumber(request)
    if request == ECHO_REQUEST then
        dprint("replyMessage: received ECHO_REQUEST")
        FZMP_SendMessage(
            "FZXC",
            {ECHO_REPLY, data, ""},
            "BN_CHAT_MSG_ADDON",
            bnetIDGameAccount)
    elseif request == ECHO_REPLY then
        local prevTime = tonumber(data)
        if prevTime then
            cprintf("fzxc: ping = %.3f s from %d",
                    GetTime() - prevTime, bnetIDGameAccount)
        else
            dprint("replyMessage: received invalid ECHO_REPLY from",
                   bnetIDGameAccount)
        end
    elseif request == VERSION_REQUEST then
        FZMP_SendMessage(
            "FZXC",
            {VERSION_REPLY, version, "", tostring(timestamp)},
            "BN_CHAT_MSG_ADDON",
            bnetIDGameAccount)
        checkVersion(data, data2)
    elseif request == VERSION_REPLY then
        checkVersion(data, data2)
    end
end

-- channel is assumed to be in lowercase
local function parseChannel(channel)
    local num = GetChannelName(channel)
    if num and num > 0 then
        return "CHANNEL", num
    end
    -- Public channels have a zone suffix so GetChannelName won't work
    num = nil
    for _, name in pairs({GetChannelList()}) do
        if num then
            local _, _, name = string_find(name, "([^%s]*)")
            if string_lower(name) == channel then
                return "CHANNEL", num
            end
            num = nil
        else
            num = name
        end
    end
end

-- Displays a message in a chat channel prefixed by the player name and realm.
local function displayMessage(sender, text, channelType, channelNum)
    local outputFormat = FZXC_DB.outputFormat
    local fullText = string_format(outputFormat, sender, text)
    SendChatMessage(fullText, channelType, nil, channelNum)
    if #fullText > 255 then
        SendChatMessage(string_format(outputFormat, sender,
                                      string_sub(fullText, 256)),
                        channelType, nil, channelNum)
    end
end

local function isPrimaryRecipient(recipients)
    isConnectedRealm_init()
    for _, recipient in ipairs(recipients) do
        local _, _, realm = string_find(recipient, "-([^-]*)")
        if isConnectedRealm[realm] and recipient > playerNameRealm then
            return false
        end
    end
    return true
end

local function receiveTransmission(_, data, _, bnetIDGameAccount)
    dprint("receiveTransmission: data =")
    dump(data)
    local counter, sender, channel, text, realm, faction, recipients
        = unpack(data)
    if channel == "" then
        replyMessage(bnetIDGameAccount, unpack(data))
        return
    end
    if not sources[channel] then        -- Reject if channel tag absent
        dprint("receiveTransmission: rejected (absent channel tag):",
               bnetIDGameAccount, counter, sender, channel, text)
        return
    end
    if not realm then
        dprint("receiveTransmission: rejected (realm missing):")
        return
    end
    dprint("receiveTransmission:", bnetIDGameAccount, counter, sender, channel, text)
    if checkMessageSent(bnetIDGameAccount, counter, sender, channel, text) then
        return
    end
    if realm == playerRealm and faction == playerFaction then
        return
    end
    channel = string_lower(channel)
    local channelType, channelNum = parseChannel(channel)
    if not channelType then
        return
    end
    if recipients and not isPrimaryRecipient(recipients) then
        return
    end
    displayMessage(sender, string_gsub(text, "\027", "|"),
                   channelType, channelNum)
end

local function onChatMsgChannel(text, sender, _, _, _, _, _,
                                channelNum, channelName, _, counter)
    if not (channelName and text) then
        return
    end
    if string_sub(text, 1, 1) == "[" then
        return
    end
    local _, _, source = string_find(channelName, "([^%s]*)")
    source = string_lower(source)
    updateSources()
    local dests = sources[source]
    if not dests then
        return
    end
    text = string_gsub(text, "|", "\027")
    local messages = {}
    for dest, bnetIDAccounts in pairs(dests) do
        for bnetIDAccount, info in pairs(bnetIDAccounts) do
            if info.connected then
                local name = info.name
                local hash = string_format(
                    "%s#%s#%s",
                    info.realm,
                    info.faction,
                    dest)
                local message = messages[hash]
                if message then
                    -- The player with the "Z"-most name gets to broadcast it
                    if message.name < name then
                        message.name = name
                        message.bnetIDAccount = bnetIDAccount
                    end
                else
                    message = {
                        dest = dest,
                        name = name,
                        bnetIDAccount = bnetIDAccount
                    }
                    messages[hash] = message
                end
            end
        end
    end
    local recipients = {}               -- FactionDest -> NameRealm
    for _, message in pairs(messages) do
        local dest = message.dest
        local bnetIDAccounts = dests[dest]
        local info = bnetIDAccounts[message.bnetIDAccount]
        local factionDest = string_format("%s#%s", info.faction, dest)

        -- append to recipients[factionDest]
        local recipients_factionDest = recipients[factionDest]
        if recipients_factionDest == nil then
            recipients_factionDest = {[0] = 0}
            recipients[factionDest] = recipients_factionDest
        end
        local i = recipients_factionDest[0] + 1
        recipients_factionDest[i] =
            string_format("%s-%s", info.name,
                          string_gsub(info.realm, " ", ""))
        recipients_factionDest[0] = i
    end
    recipients[0] = nil
    for _, message in pairs(messages) do
        local dest = message.dest
        local info = dests[dest][message.bnetIDAccount]
        local destID = info.bnetIDGameAccount
        if destID == nil or destID == 0 then destID = message.bnetIDAccount end
        local factionDest = string_format("%s#%s", info.faction, dest)
        local data = {counter, sender, dest, text, playerRealm, playerFaction,
                      recipients[factionDest]}
        dprint("onChatMsgChannel: sending message to", destID, "with data =")
        dump(data)
        FZMP_SendMessage("FZXC", data, "BN_CHAT_MSG_ADDON", destID)
    end
end

local time = 0
local timer = 15
local messageCacheDuration = timer
local function onUpdate(_, elapsed)
    local newTime = time + elapsed
    if newTime < timer then
        time = newTime
        return
    end
    time = 0
    -- Clear the expired messages
    updateSources()
    local time = GetTime()
    local archive = messageArchive
    for hash, messages in pairs(archive) do
        for counter, message in pairs(messages) do
            if message.time + messageCacheDuration < time then
                messages[counter] = nil
            end
        end
        if #archive[hash] == 0 then
            archive[hash] = nil
        end
    end
    updateIgnoreList()
end

local function channelFilter(_, _, text)
    if text and string_sub(text, 1, 1) == "[" then
        -- Filter out ignored players
        return ignoreList[string_match(text, "%[([^%]]+)]")]
    end
end

local function enable()
    FZXC_DB.disabled = nil
    frame:RegisterEvent("CHAT_MSG_CHANNEL")
    FZMP_RegisterMessageListener("FZXC", receiveTransmission)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", channelFilter)
end

local function disable()
    FZXC_DB.disabled = true
    frame:UnregisterEvent("CHAT_MSG_CHANNEL")
    FZMP_UnregisterMessageListener("FZXC", receiveTransmission)
    ChatFrame_RemoveMessageEventFilter("CHAT_MSG_CHANNEL", channelFilter)
end

local slashCommands = {
    version = {
        description = L"Displays the version of the add-on.",
        action = function()
            cprintf(L"fzxc version %s [%i]", version, timestamp or 0)
        end
    },
    info = {
        description = L"Displays the current channels.",
        action = function()
            if FZXC_DB.disabled then
                cprintf("fzxc: |cffff6600%s|r", L"disabled")
                return
            end
            cprint(L"fzxc: displaying all channels ...")
            updateSources()
            for source, dests in pairs(sources) do
                for dest, bnetIDAccounts in pairs(dests) do
                    if source == dest then
                        cprintf("#%s", source)
                    else
                        cprintf("#%s:%s", source, dest)
                    end
                    for bnetIDAccount, info in pairs(bnetIDAccounts) do
                        local _, name =
                            BNGetFriendInfo(BNGetFriendIndex(bnetIDAccount))
                        local status
                        if info.connected then
                            status = string_format("|cff00ff00%s|r",
                                                   L"connected")
                        else
                            status = string_format("|cff999999%s|r",
                                                   L"not connected")
                        end
                        cprintf("    %s [%s]", name, status)
                    end
                end
            end
        end
    },
    outputFormat = {
        description =
            L"Views/changes the chat output format.\n" ..
            L"To view, input no arguments.\n" ..
            L"To change, input a single argument in quotes.\n" ..
            L"Default value is |cffffffff'[%s]: %s'|r.\n" ..
            L"First |cffffffff%s|r is the player name and realm.\n" ..
            L"Second |cffffffff%s|r is the chat message.\n" ..
            L"Make sure the format string is not excessively long.",
        action = function(args)
            -- If no arguments, just print the current value.
            if args == "" then
                cprintf(L"fzxc: output format is currently |cffffffff'%s'|r.",
                        FZXC_DB.outputFormat)
                return
            end
            -- Check if the argument is in the correct syntax
            local len   = #args
            local first = string_sub(args, 1, 1)
            local last  = string_sub(args, len, len)
            if len < 2 or not ((first == "'" and last == "'") or
                               (first == '"' and last == '"')) then
                cerrorf(L"argument must be surrounded by matching quotes.")
                return
            end
            local arg = string_sub(args, 2, #args - 1)
            -- Save the setting
            FZXC_DB.outputFormat = arg
            cprintf(L"fzxc: output format set to |cffffffff'%s'|r.", arg)
            if arg == "" then
                cwarnf(L"output format is empty.")
            end
        end
    },
    toggle = {
        description = L"Enables / disables the add-on.",
        action = function()
            local state
            if FZXC_DB.disabled then
                enable()
                state = string_format("|cff00ff00%s|r", L"enabled")
            else
                disable()
                state = string_format("|cffff6600%s|r", L"disabled")
            end
            cprintf(L"fzxc: %s", state)
        end
    },
    enable = {
        action = function()
            local state
            if FZXC_DB.disabled then
                enable()
                state = string_format("|cff00ff00%s|r", L"enabled")
            else
                state = string_format("|cff00ff00%s|r", L"already enabled")
            end
            cprintf(L"fzxc: %s", state)
        end
    },
    disable = {
        action = function()
            local state
            if FZXC_DB.disabled then
                state = string_format("|cffff6600%s|r", L"already disabled")
            else
                disable()
                state = string_format("|cffff6600%s|r", L"disabled")
            end
            cprintf(L"fzxc: %s", state)
        end
    },
    debug = {
        action = function()
            DEBUG = not DEBUG
            FZMP_DEBUG = DEBUG
            FZMP_DEBUG_SYMB = {
                displayMessage = displayMessage
            }
            cprintf("fzxc: debug %s", DEBUG and "on" or "off")
        end
    },
    trace = {
        action = function()
            if not DEBUG then
                cprint("fzxc: must enable debug mode first")
                return
            end
            dump(sources)
        end
    },
    ping = {
        action = function(name)
            local bnetIDAccount = GetAutoCompletePresenceID(name)
            if not bnetIDAccount then
                cprint("fzxc: invalid name")
                return
            end
            FZMP_SendMessage("FZXC", {ECHO_REQUEST, tostring(GetTime()), ""},
                             "BN_CHAT_MSG_ADDON", bnetIDAccount)
        end
    },
}

local function initialize()

    -- Initialize constants
    playerFaction = UnitFactionGroup("player")

    -- Initialize saved variable
    if not FZXC_DB then
        FZXC_DB = {}
    end
    FZXC_DB.version = version
    FZXC_DB.timestamp = timestamp

    -- Set the default value for `outputFormat`
    if not FZXC_DB.outputFormat then
        FZXC_DB.outputFormat = "[%s]: %s"
    end

    -- Start the message disposer
    frame:SetScript("OnUpdate", onUpdate)
    updateSources()
    updateIgnoreList()

    -- Query version of other player's addons
    local connectedDestIDs = {}
    for source, dests in pairs(sources) do
        for dest, bnetIDAccounts in pairs(dests) do
            for bnetIDAccount, info in pairs(bnetIDAccounts) do
                if info.connected then
                    local destID = info.bnetIDGameAccount
                    if destID == nil or destID == 0 then destID = bnetIDAccount end
                    connectedDestIDs[destID] = true
                end
            end
        end
    end
    for destID, _ in pairs(connectedDestIDs) do
        FZMP_SendMessage("FZXC", {VERSION_REQUEST, version, "", timestamp},
                         "BN_CHAT_MSG_ADDON", destID)
    end

    -- Set up slash commands
    SLASH_FZXC1 = "/fzxc"
    function SlashCmdList.FZXC(str)
        local command, arguments = string_match(str, "([^%s]+)%s*(.*)")
        local commandInfo = slashCommands[command]
        if commandInfo then
            commandInfo.action(arguments)
            return
        end

        -- Display usage info if the command is not found
        cprint(L"Usage:")
        cprintf("    |cffffff00/fzxc|r |cff0099ff%s %s|r",
                L"<command>", L"<arguments>")
        cprintf(L"where the case-sensitive %s is one of:",
                string_format("|cff0099ff%s|r", L"<command>"))
        for command, commandInfo in pairs(slashCommands) do
            description = commandInfo.description
            if description then
                cprintf("    |cffffff00%s|r - %s", command,
                        string_gsub(description, "\n", "\n      "))
            end
        end
    end

end

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript(
    "OnEvent",
    function(_, event, ...)
        if event == "CHAT_MSG_CHANNEL" then
            onChatMsgChannel(...)
        elseif event == "PLAYER_ENTERING_WORLD" then
            frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
            initialize()
            if not FZXC_DB.disabled then
                enable()
            end
        end
    end)
