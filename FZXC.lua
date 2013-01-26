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

local version = {1, 0, 1}

-- Debug ONLY
-- ==========

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

-- TODO: Allow players to act as delegates for other players.
-- E.g. A => B => C (A and C are not connected)

-- TODO: Versioning conflict -- if a newer version needs to replace an older
-- version that is ALREADY initialized, how do you unregister all of its event
-- handlers?  Or is there a better way -- don't initialize until all possible
-- versions have loaded?  Read up on this.  Maybe Ace3 has a way.

------------------------------------------------------------------------------

local ipairs = ipairs
local pairs = pairs
local type = type
local unpack = unpack
local string_format = string.format
local string_lower = string.lower
local string_gmatch = string.gmatch
local string_match = string.match
local string_sub = string.sub
local BNGetFriendInfo = BNGetFriendInfo
local BNGetNumFriendToons = BNGetNumFriendToons
local BNGetToonInfo = BNGetToonInfo
local BNSendWhisper = BNSendWhisper
local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter
local GetChannelName = GetChannelName
local GetTime = GetTime
local SendAddonMessage = SendAddonMessage

-- TODO: Implement these
local playerName = UnitName("player")   -- If a message is being sent directly
                                        -- to the same player *toon*, bypass
                                        -- all the chat channels and just send
                                        -- it to the same client.
local playerRealm = GetRealmName()      -- Use SendChatMessage if the player
                                        -- is already on the same realm
                                        -- (i.e. don't unnecessarily use
                                        -- BNSendWhisper)
-- TODO: Check if it's possible to SendAddonMessage with WHISPER to a hostile
--       player.

local dataIndex = 0
local function bnFilter(_, _, text)

    -- FZM protocol
    if string_match(text, "^|HFZM:") then
        return true
    end

    -- FZX protocol
    local index = dataIndex
    local data = string_match(text, "^|HFZX:([^|]*)")
    if data then
        local count = tonumber(data)
        if count then dataIndex = index + count end
        dprint("bnFilter: filtered FZX data.")
        return true
    end
    if index > 0 then
        dataIndex = index - 1
        dprint("bnFilter: filtered FZX header.")
        return true
    end

end

local timer = 0
local function onUpdate(_, elapsed)
    local newTimer = timer + elapsed
    if newTimer < 1 then
        timer = newTimer
        return
    else
        timer = 0
    end

    -- Message dispatcher

    -- Use a counter to keep track of how many messages are being sent.  If
    -- above threshold, additional messages will be sent to the message queue
    -- instead.  The counter slowly decreases if the message queue is not
    -- full.

    -- TEMPORARY: just send the message!
end

local listeners = {}

-- For FZX protocol
local data
local dataCount
local dataIndex = 0

-- Message receiver
local function onEvent(_, event, arg1, arg2, arg3, arg4, _,
                       _, _, _, _, _, _, _, arg13)

    if event == "CHAT_MSG_ADDON" then
        if arg1 ~= "FZM" then return end
        -- Handle realm-local message
        -- (prefix, message, channel, sender)

        -- NOTE: Messages that use CHAT_MSG_ADDON in lieu of BN_WHISPER will
        --       need to be dealt with separately.

        -- TODO: not implemented

    else
        -- Handle cross-realm message
        -- arg1 = data, arg13 = sender's presenceID

        -- FZX protocol
        dprint("FZM event: BN_WHISPER", arg1, arg13)
        local index = dataIndex
        if index > 0 then
            local count = dataCount
            dataIndex = index - 1
            dataCount = count + 1
            data[count] = arg1
            if index == 1 then
                local prefix = "FZX"
                local prefixListeners = listeners[prefix]
                if prefixListeners then
                    for listener, _ in pairs(prefixListeners) do
                        listener(prefix, data, "BN_WHISPER", arg13)
                    end
                end
            end
        end
        local header = string_match(arg1, "^|HFZX:([^|]*)")
        if header then
            local count = tonumber(header)
            if count then
                data = {}
                dataCount = 1
                dataIndex = count
            end
        end

        -- FZM protocol
        local data = string_match(arg1, "^|HFZM:([^|]*)")
        if data then
            -- TODO: to be implemented
        end
    end
end

local FZMP = CreateFrame("Frame")
FZMP:SetScript("OnUpdate", onUpdate)
FZMP:SetScript("OnEvent", onEvent)
FZMP:RegisterEvent("CHAT_MSG_ADDON")
FZMP:RegisterEvent("CHAT_MSG_BN_WHISPER")
ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER", bnFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER_INFORM", bnFilter)
if not RegisterAddonMessagePrefix("FZM") then
    DEFAULT_CHAT_FRAME:AddMessage("libFZMP: failed to load properly.", 1, 0, 0)
    error('RegisterAddonMessagePrefix("FZM") returned nil.')
end

local function sendPacket(prefix, payload)
end

-- For now, payload is assumed to be an array of strings (or just a string)
-- prefix must be 16 chars or less
local function FZMP_SendMessage(prefix, data, channel, recipient)
    if channel == "BN_WHISPER" then

        -- FZX protocol
        if prefix == "FZX" then


            if type(data) == "string" then
                data = {data}
            end
            BNSendWhisper(recipient, string_format("|HFZX:%i|h |h", #data))
            dprint("FZMP_SendMessage", recipient, unpack(data))
            for _, item in ipairs(data) do
                BNSendWhisper(recipient, item)
            end

        else
            -- TODO: other prefixes are not supported yet
        end

    else
         -- TODO: other channels are not supported yet
    end
end

-- The listener is of the form: (prefix, data, channel, sender)
local function FZMP_RegisterMessageListener(prefix, listener)
    local prefixListeners = listeners[prefix]
    if not prefixListeners then
        prefixListeners = {}
        listeners[prefix] = prefixListeners
    end
    prefixListeners[listener] = true
end

local function FZMP_UnregisterMessageListener(prefix, listener)
    local prefixListeners = listeners[prefix]
    if prefixListeners then
        prefixListeners[listener] = nil
        if #prefixListeners == 0 then
            listeners[prefix] = nil
        end
    end
end

------------------------------------------------------------------------------

local ipairs = ipairs
local pairs = pairs
local unpack = unpack
local string_format = string.format
local string_lower = string.lower
local string_gmatch = string.gmatch
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

local playerName = UnitName("player")
local playerRealm = GetRealmName()

-- Localization placeholder
local L = function(...) return ... end

local playerFaction
local function getPlayerFaction()
    -- TODO: Refactor the player faction so it's not being checked
    --       every single time (note that this only happens after the
    --       PLAYER_ENTERING_WORLD event)
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
        if realm == "" then
            local time = GetTime()
            if time - realmNullErrorTimer > 300 then
                -- BUG: BNGetToonInfo can return "" for realm.  How should
                --      this be handled? [bug:dupmsg]
                realmNullErrorTimer = time
                DEFAULT_CHAT_FRAME:AddMessage(
                    ("fzxc: Due to a Battle.Net bug, I can't determine " ..
                     "the realm of your friends.  As a result, you may " ..
                     "broadcast duplicate messages.  To fix this, you will " ..
                     "need to re-log. [bug:dupmsg]"), 1, 0, 0)
            end
        end
        if (client == "WoW" and realm == playerRealm and
            faction == playerFaction and name > playerName) then
            return
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
    local fullText = string_format("[%s]: %s", sender, text)
    -- BUG: weird latency bugs can happen here, causing "|" to appear in `text`
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
        print(L("fzxc version %i.%i.%i"):format(unpack(version)))

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
