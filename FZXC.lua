-- Copyright (c) 2013 Fylwind <fylwind314@gmail.com>
--
-- This program is free software: you can redistribute it and/or modify it
-- under the terms of the GNU General Public License as published by the Free
-- Software Foundation, either version 3 of the License, or (at your option)
-- any later version.
--
-- This program is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
-- more details.
--
-- You should have received a copy of the GNU General Public License along
-- with this program.  If not, see <http://www.gnu.org/licenses/>.
--
------------------------------------------------------------------------------

-- Debugging utilities
-- ===================

local DEBUG

local function dprint(...)
    if DEBUG then
        print("fzxc:", ...)
    end
end

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
local string_sub = string.sub

local BNGetFriendInfo = BNGetFriendInfo
local BNGetFriendIndex = BNGetFriendIndex
local BNGetNumFriends = BNGetNumFriends
local BNGetToonInfo = BNGetToonInfo
local GetChannelName = GetChannelName
local GetTime = GetTime
local SlashCmdList_JOIN = SlashCmdList["JOIN"]
local SendChatMessage = SendChatMessage
local UnitFactionGroup = UnitFactionGroup

local FZMP = FZMP
local FZMP_SendMessage = FZMP.SendMessage
local FZMP_RegisterMessageListener = FZMP.RegisterMessageListener

local playerName = UnitName("player")
local playerRealm = GetRealmName()
local playerFaction

local version = "@project-version@"
local timestamp = tonumber("@project-timestamp@")
local sources
local messageArchive = {}

-- Localization placeholder
local L = function(...) return ... end

local function cprint(text)
    DEFAULT_CHAT_FRAME:AddMessage(text, .7, 1, .4)
end

local function updateSources()
    sources = {}
    for friendIndex = 1, BNGetNumFriends() do
        local presenceID, _, _, _, _, _, _, _, _, _, _, _, note
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
                local presenceIDs = dests[dest]
                if not presenceIDs then
                    presenceIDs = {}
                    dests[dest] = presenceIDs
                end
                local _, name, client, realm, _, faction
                    = BNGetToonInfo(presenceID)
                if client == "WoW" and (realm ~= playerRealm or
                                        faction ~= playerFaction) then
                    presenceIDs[presenceID] = {
                        connected = true,
                        name = name,
                        realm = realm,
                        faction = faction
                    }
                else
                    presenceIDs[presenceID] = {
                        connected = false
                    }
                end
            end
        end
    end
end

-- Ensure message is not just another duplicate from a different player
local function checkMessageSent(presenceID, counter, sender, channel, text)
    local hash = string_format("%s#%s#%s", channel, sender, text)
    local archive = messageArchive
    local messages = archive[hash]
    if not messages then
        archive[hash] = {{presenceID = presenceID, time = GetTime()}}
        return
    end
    for _, message in pairs(messages) do
        if message.presenceID ~= presenceID then
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
    messages[counter] = {presenceID = presenceID, time = GetTime()}
end

local versionChecked
local function checkVersion(data, data2)
    if versionChecked then
        return
    end
    local otherTimestamp = tonumber(data2)
    if timestamp and otherTimestamp and timestamp < otherTimestamp then
        cprint(string_format(
                   L("fzxc: a new version (%s) is available."),
                   data))
        versionChecked = true
    end
end

local ECHO_REQUEST = 1
local ECHO_REPLY = 2
local VERSION_REQUEST = 3
local VERSION_REPLY = 4

local function replyMessage(presenceID, request, data, _, data2)
    dprint("SYS_MSG", presenceID, request, data, data2)
    request = tonumber(request)
    if request == ECHO_REQUEST then
        FZMP_SendMessage(
            "FZX",
            {ECHO_REPLY, data, ""},
            "BN_WHISPER",
            presenceID)
    elseif request == ECHO_REPLY then
        local prevTime = tonumber(data)
        if prevTime and DEBUG then
            dprint("ECHO", GetTime() - prevTime)
        end
    elseif request == VERSION_REQUEST then
        FZMP_SendMessage(
            "FZX",
            {VERSION_REPLY, version, "", tostring(timestamp)},
            "BN_WHISPER",
            presenceID)
        checkVersion(data, data2)
    elseif request == VERSION_REPLY then
        checkVersion(data, data2)
    end
end

local function receiveTransmission(_, data, _, presenceID)
    local counter, sender, channel, text, realm, faction = unpack(data)
    if channel == "" then
        replyMessage(presenceID, unpack(data))
    end
    if not realm then                   -- Backward compatibility: previous
        local _                         -- versions didn't send realm & faction
        _, _, _, realm, _, faction = BNGetToonInfo(presenceID)
        if realm == "" then
            realm = "??"
        end
    end
    dprint("RECEIVE", presenceID, counter, sender, channel, text)
    if checkMessageSent(presenceID, counter, sender, channel, text) then
        return
    end
    if realm == playerRealm and faction == playerFaction then
        return
    end
    sender = string_format("%s-%s", sender, realm)
    local channelNum = GetChannelName(channel)
    if not channelNum or channelNum <= 4 then -- Forbid public channels
        return
    end
    text = string_gsub(text, "\027", "|")
    local fullText = string_format("[%s]: %s", sender, text)
    SendChatMessage(fullText, "CHANNEL", nil, channelNum)
    if #fullText > 255 then
        SendChatMessage(string_format("[%s] (...): %s",
                                      sender, string_sub(fullText, 256)),
                        "CHANNEL", nil, channelNum)
    end
end

local frame = CreateFrame("Frame")

local function onPlayerEnteringWorld()
    frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    playerFaction = UnitFactionGroup("player")
    updateSources()
    local connectedPresenceIDs = {}
    for source, dests in pairs(sources) do
        for dest, presenceIDs in pairs(dests) do
            for presenceID, info in pairs(presenceIDs) do
                if info.connected then
                    connectedPresenceIDs[presenceID] = true
                end
            end
        end
    end
    for presenceID, _ in pairs(connectedPresenceIDs) do
        FZMP_SendMessage("FZX", {VERSION_REQUEST, version, "", timestamp},
                         "BN_WHISPER", presenceID)
    end
    FZMP_RegisterMessageListener("FZX", receiveTransmission)
end

local function onChatMsgChannel(text, sender, _, _, _, _, _,
                                _, channelName, _, counter)
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
    for dest, presenceIDs in pairs(dests) do
        for presenceID, info in pairs(presenceIDs) do
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
                        message.presenceID = presenceID
                    end
                else
                    message = {
                        dest = dest,
                        name = name,
                        presenceID = presenceID
                    }
                    messages[hash] = message
                end
            end
        end
    end
    for _, message in pairs(messages) do
        FZMP_SendMessage(
            "FZX",
            {counter,
             sender,
             message.dest,
             text,
             playerRealm,
             playerFaction},
            "BN_WHISPER",
            message.presenceID)
    end
end

local timer = 0
local messageExpiryTime = 15
local function onUpdate(_, elapsed)
    local newTimer = timer + elapsed
    if newTimer < messageExpiryTime then
        timer = newTimer
        return
    end
    timer = 0
    -- Clear the expired messages
    updateSources()
    local time = GetTime()
    local archive = messageArchive
    for hash, messages in pairs(archive) do
        for counter, message in pairs(messages) do
            if message.time + messageExpiryTime < time then
                messages[counter] = nil
            end
        end
        if #archive[hash] == 0 then
            archive[hash] = nil
        end
    end
end
frame:SetScript("OnUpdate", onUpdate)

frame:RegisterEvent("CHAT_MSG_CHANNEL")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
local function onEvent(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        onPlayerEnteringWorld(...)
    elseif event == "CHAT_MSG_CHANNEL" then
        onChatMsgChannel(...)
    end
end
frame:SetScript("OnEvent", onEvent)

SLASH_FZXC1 = "/fzxc"
function SlashCmdList.FZXC(str)

    if str == "version" then
        -- Display all the current channels
        cprint(L("fzxc version %s [%i]"):format(version, timestamp or 0))

    elseif str == "info" then
        -- Display all the current channels
        cprint(L("fzxc: displaying all channels ..."))
        updateSources()
        for source, dests in pairs(sources) do
            for dest, presenceIDs in pairs(dests) do
                if source == dest then
                    cprint(("* #%s"):format(source))
                else
                    cprint(("* #%s:%s"):format(source, dest))
                end
                for presenceID, info in pairs(presenceIDs) do
                    local _, name =
                        BNGetFriendInfo(BNGetFriendIndex(presenceID))
                    local status
                    if info.connected then
                        status = ("|cff00ff00%s|r"):format(L("connected"))
                    else
                        status = ("|cff999999%s|r"):format(L("not connected"))
                    end
                    cprint(("  - %s [%s]"):format(name, status))
                end
            end
        end

    elseif str == "debug" then
        DEBUG = not DEBUG
        FZMP_DEBUG = DEBUG
        cprint(("fzxc: debug %s"):format(DEBUG and "on" or "off"))

    elseif str == "trace" then
        if not DEBUG then
            cprint("Debug mode must be on first!")
        end
        dump(sources)

    elseif str:sub(1, 5) == "ping " then
        if not DEBUG then
            cprint("Debug mode must be on first!")
        end
        local presenceID = GetAutoCompletePresenceID(str:sub(6))
        if presenceID then
            FZMP_SendMessage(
                "FZX",
                {ECHO_REQUEST, tostring(GetTime()), ""},
                "BN_WHISPER",
                presenceID)
        end

    else
        local usage = {
            L("Usage:"),
            L("    /fzxc <command>"),
            L("where <command> is one of:"),
            L("    info"),
            L("    version"),
        }
        for _, line in ipairs(usage) do
            cprint(line)
        end
    end
end
