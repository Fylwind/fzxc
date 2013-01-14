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

-- Debug ONLY
-- ==========

-- FZXC_DEBUG = true

local function dprint(...)
    if FZXC_DEBUG then
        print(...)
    end
end

local function dump(var)
    if FZXC_DEBUG then
        UIParentLoadAddOn("Blizzard_DebugTools")
        DevTools_Dump(var)
    end
end

-- TODO: Allow players to act as delegates for other players.
-- E.g. A => B => C (A and C are not connected)

------------------------------------------------------------------------------

local ipairs = ipairs
local pairs = pairs
local unpack = unpack
local string_format = string.format
local string_lower = string.lower
local string_gmatch = string.gmatch
local string_match = string.match
local string_sub = string.sub
local BNGetFriendInfo = BNGetFriendInfo
local BNGetNumFriends = BNGetNumFriends
local BNGetToonInfo = BNGetToonInfo
local BNSendWhisper = BNSendWhisper
local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter
local GetAutoCompletePresenceID = GetAutoCompletePresenceID
local GetChannelName = GetChannelName
local GetTime = GetTime
local SlashCmdList_JOIN = SlashCmdList["JOIN"]
local SendChatMessage = SendChatMessage

local playerName = UnitName("player")
local playerRealm = GetRealmName()

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

-- Check if the player is an "alpha" who is designated to post messages
local function checkReceiverAlpha(info)
    for _, presenceID in ipairs(info.presenceIDs) do
        local _, name, client, realm = BNGetToonInfo(presenceID)
        if client == "WoW" and realm == playerRealm and name > playerName then
            return
        end
    end
    return true
end

local function receiveTransmission(presenceID, counter, sender,
                                   channelName, text)
    local info = channels[channelName]
    if not info then return end
    dprint("receiveTrans", presenceID, counter, sender, channelName, text)
    if not checkReceiverAlpha(info) then
        return
    end
    dprint("receiveTrans2")
    if checkMessageSent(presenceID, counter, sender, info, text) then
        return
    end
    SlashCmdList_JOIN(channelName)
    local _, _, _, realm = BNGetToonInfo(presenceID)
    sender = string_format("%s-%s", sender, realm)
    local channelNum = GetChannelName(channelName)
    if not channelNum then return end
    local fullText = string_format("[%s]: %s", sender, text)
    SendChatMessage(fullText, "CHANNEL", nil, channelNum)
    if #fullText > 255 then
        SendChatMessage(string_format("[%s] (cont'd): %s",
                                      sender, string_sub(fullText, 256)),
                        "CHANNEL", nil, channelNum)
    end
end

local function sendTransmission(presenceID, ...)
    local transmission = {...}
    BNSendWhisper(presenceID, string_format("|HFZX:%i|h |h", #transmission))
    for _, data in ipairs(transmission) do
        dprint("sendTrans", presenceID, ...)
        BNSendWhisper(presenceID, data)
    end
end

local transmissionIndex = 0
local function bnFilter(_, _, text)
    local index = transmissionIndex
    local data = string_match(text, "|HFZX:(.*)|h[^|]*|h")
    if data then
        local count = tonumber(data)
        if count then
            transmissionIndex = index + count
        end
        return true
    end
    if index > 0 then
        transmissionIndex = index - 1
        return true
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

local lastCounter
local transmission
local transmissionCount
local transmissionIndex = 0
local function bnReceiver(text, _, _, _, _, _, _, _, _,
                          _, counter, _, presenceID)
    -- Ignore redundant messages
    if lastCounter == counter then
        error("repeated message filtered in bnReceiver -- " ..
            "file a bug report to Fylwind, author of FZXC please!")
        return
    end
    lastCounter = counter

    local index = transmissionIndex
    if index > 0 then
        local count = transmissionCount
        transmissionIndex = index - 1
        transmissionCount = count + 1
        transmission[count] = text
        if index == 1 then
            receiveTransmission(presenceID, unpack(transmission))
        end
    end
    local data = string_match(text, "|HFZX:(.*)|h[^|]*|h")
    if data then
        local count = tonumber(data)
        if count then
            transmission = {}
            transmissionCount = 1
            transmissionIndex = count
        end
    end
end

local lastCounter
local function chFilter(text, sender, _, _, _, _, _,
                        _, channelName, _, counter)
    -- Ignore redundant messages
    if lastCounter == counter then
        error("repeated message filtered in chFilter -- " ..
            "file a bug report to Fylwind, author of FZXC please!")
        return
    end
    lastCounter = counter

    if not (channelName and text) then return end
    if string_sub(text, 1, 1) == "[" then return end
    local channelName = string_lower(channelName)
    local info = channels[channelName]
    if not info then return end
    for _, presenceID in pairs(info.presenceIDs) do
        local _, _, client, realm = BNGetToonInfo(presenceID)
        if client == "WoW" and realm ~= playerRealm then
            sendTransmission(presenceID, counter, sender, channelName, text)
        end
    end
end

local function onEvent(_, event, ...)
    if event == "CHAT_MSG_BN_WHISPER" then
        bnReceiver(...)
    elseif event == "CHAT_MSG_CHANNEL" then
        chFilter(...)
    end
end

updateChannels()
FZXC_DEBUG_channels = channels
local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", onUpdate)
frame:SetScript("OnEvent", onEvent)
frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
frame:RegisterEvent("CHAT_MSG_CHANNEL")
ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER", bnFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER_INFORM", bnFilter)
