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
        print(...)
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

-- Localization placeholder
local L = function(...) return ... end

local playerFaction
local function getPlayerFaction()
    local faction = playerFaction
    if not faction then
        faction = UnitFactionGroup("player")
        playerFaction = faction
    end
    return faction
end

local channels
local function updateChannels()
    if not channels then
        channels = {}
    end
    for _, info in pairs(channels) do
        info.presenceIDs = {}
        info.presenceIDsEnd = 1
    end
    for friendIndex = 1, BNGetNumFriends() do
        local presenceID, _, _, _, _, _, _, _, _, _, _, _, note
            = BNGetFriendInfo(friendIndex)
        if note then
            for channelName in string_gmatch(note, "#(%w+)") do
                channelName = string_lower(channelName)
                local info = channels[channelName]
                if not info then
                    info = {
                        messageArchive = {},
                        presenceIDs = {},
                        presenceIDsEnd = 1
                    }
                    channels[channelName] = info
                end
                local presenceIDs = info.presenceIDs
                local presenceIDsEnd = info.presenceIDsEnd
                presenceIDs[presenceIDsEnd] = presenceID
                info.presenceIDsEnd = presenceIDsEnd + 1
            end
        end
    end
    return channels
end

-- Ensure message is not just another duplicate from a different player
local function checkMessageSent(presenceID, counter, sender, info, text)
    local hash = string_format("%s:%s", sender, text)
    local archive = info.messageArchive
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

local realmNullErrorTimer = -1 / 0      -- Minus infinity
local function receiveTransmission(_, data, _, presenceID)
    local counter, sender, channelName, text, realm, faction = unpack(data)
    if not realm then                   -- Backward compatibility: previous
        local _                         -- versions didn't send realm & faction
        _, _, _, realm, _, faction = BNGetToonInfo(presenceID)
        if realm == "" then
            realm = "??"
        end
    end
    local info = channels[channelName]
    if not info then
        return
    end
    dprint("receiveTrans", presenceID, counter, sender, channelName, text)
    -- Check if player is an "alpha" who is designated to post messages
    -- This player shall have a name that is placed last in alphabetical order
    local playerFaction = getPlayerFaction()
    for _, presenceID in ipairs(info.presenceIDs) do
        local _, name, client, realm, _, faction = BNGetToonInfo(presenceID)
        if client == "WoW" then
            if realm == "" then         -- [bug:dupmsg]
                local time = GetTime()
                if time - realmNullErrorTimer > 300 then
                    realmNullErrorTimer = time
                    DEFAULT_CHAT_FRAME:AddMessage(
                        ("fzxc: Due to a Battle.Net bug, I can't determine " ..
                         "the realm of your friends.  As a result, you may " ..
                         "broadcast duplicate messages.  To fix this, you " ..
                         "will need to re-log. [bug:dupmsg]"), 1, 0, 0)
                end
            elseif (realm == playerRealm and faction == playerFaction and
                    name > playerName) then
                return
            end
        end
    end
    dprint("receiveTrans2")
    if checkMessageSent(presenceID, counter, sender, info, text) then
        return
    end
    SlashCmdList_JOIN(channelName)
    if realm == playerRealm and faction == playerFaction then
        return
    end
    sender = string_format("%s-%s", sender, realm)
    local channelNum = GetChannelName(channelName)
    if not channelNum then
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

local timer = 0
local messageExpiryTime = 15
local function onUpdate(_, elapsed)
    local newTimer = timer + elapsed
    if newTimer < messageExpiryTime then
        timer = newTimer
        return
    else
        timer = 0
    end
    -- Clear the expired messages
    local time = GetTime()
    updateChannels()
    for _, info in pairs(channels) do
        local archive = info.messageArchive
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
end

local function onEvent(_, _, text, sender, _, _, _, _, _,
                       _, channelName, _, counter)
    if not (channelName and text) then return end
    if string_sub(text, 1, 1) == "[" then return end
    local channelName = string_lower(channelName)
    local info = channels[channelName]
    if not info then return end
    text = string_gsub(text, "|", "\027")
    local playerFaction = getPlayerFaction()
    for _, presenceID in pairs(info.presenceIDs) do
        local _, _, client, realm, _, faction = BNGetToonInfo(presenceID)
        if (client == "WoW" and
            (realm ~= playerRealm or
             faction ~= playerFaction)) then
            FZMP_SendMessage(
                "FZX",
                {counter,
                 sender,
                 channelName,
                 text,
                 playerRealm,
                 playerFaction},
                "BN_WHISPER",
                presenceID)
        end
    end
end

updateChannels()
FZMP_RegisterMessageListener("FZX", receiveTransmission)
local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", onUpdate)
frame:SetScript("OnEvent", onEvent)
frame:RegisterEvent("CHAT_MSG_CHANNEL")

SLASH_FZXC1 = "/fzxc"
function SlashCmdList.FZXC(str)
    local print = function(text)
        DEFAULT_CHAT_FRAME:AddMessage(text, .7, 1, .4)
    end

    if str == "version" then
        -- Display all the current channels
        print(L("fzxc version %s"):format("@project-version@"))

    elseif str == "info" then
        -- Display all the current channels
        print(L("fzxc: displaying all channels ..."))
        for channel, info in pairs(channels) do
            print(L("* Channel: %s"):format(channel))
            for _, presenceID in pairs(info.presenceIDs) do
                local _, name = BNGetFriendInfo(BNGetFriendIndex(presenceID))
                local _, _, client = BNGetToonInfo(presenceID)
                local status = ("|cff999999%s|r"):format(L("offline"))
                if client == "WoW" then
                    status = ("|cff00ff00%s|r"):format(L("online"))
                end
                print(L("  - %s [%s]"):format(name, status))
            end
        end

    elseif str == "debug" then
        DEBUG = not DEBUG
        print(("fzxc: debug %s"):format(DEBUG and "on" or "off"))

    elseif str == "trace" then
        if not DEBUG then print("Debug mode must be on first!") end
        dump(channels)

    else
        local usage = {
            L("Usage:"),
            L("    /fzxc <command>"),
            L("where <command> is one of:"),
            L("    info"),
            L("    version"),
        }
        for _, line in ipairs(usage) do print(line) end
    end
end
