local _Name    = "FZMP"
local _Version = 1

--~---------------------------------------------------------------------------
--
-- Module Definition
-- =================

local _G = _G
local _M = _G[_Name]
if _M then
    if _M.Version >= _Version then
        return
    end
    if _M.Unload then
        _M.Unload()
    end
end
_M = { Version = _Version }
_G[_Name] = _M

--~---------------------------------------------------------------------------
--
-- External functions
-- ==================

local ipairs = ipairs
local pairs = pairs
local setmetatable = setmetatable
local tonumber = tonumber
local type = type
local unpack = unpack

local string = string
local string_byte = string.byte
local string_char = string.char
local string_find = string.find
local string_format = string.format
local string_gmatch = string.gmatch
local string_lower = string.lower
local string_match = string.match
local string_rep = string.rep
local string_sub = string.sub

local table_concat = table.concat

local BNGetFriendInfo = BNGetFriendInfo
local BNGetNumFriendGameAccounts = BNGetNumFriendGameAccounts
local BNGetGameAccountInfo = BNGetGameAccountInfo
local BNSendWhisper = BNSendWhisper
local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter
local GetChannelName = GetChannelName
local GetTime = GetTime
local SendAddonMessage = SendAddonMessage

------------------------------------------------------------------------------
--
-- Percent Encoder / Decoder
-- =========================
--
---

---
-- Encodes a string using the percent-encoding that escapes all characters
-- except dash, underscore, dot, tilde, and all alphanumeric characters
-- ("Unreserved Characters").  The encoded string will contain only the above
-- characters and the percentage sign (the escape character).
--
-- @param  str                [string]
--   Data to be encoded.
--
-- @return                    [string]
--   Encoded result.
--
function _M.PercentEncode(str)
    local chunks = {}
    local index = 1
    for chunk, char in string_gmatch(str, "([-_.~%w]*)(.?)") do
        chunks[index] = chunk
        index = index + 1
        if #char == 1 then
            chunks[index] = string_format("%%%02x", string_byte(char))
            index = index + 1
        end
    end
    return table_concat(chunks)
end

---
-- Decodes a percent-encoded string.
--
-- @param  str                [string]
--   Data to be decoded.
--
-- @return                    [string]
--   Decoded result.
--
function _M.PercentDecode(str)
    local chunks = {}
    local index = 1
    for chunk, escape, hex in string_gmatch(str, "([^%%]*)(.?)(%x?%x?)") do
        chunks[index] = chunk
        if #hex == 2 then
            chunks[index + 1] = string_char(tonumber(hex, 16))
            index = index + 2
        else
            chunks[index + 1] = escape
            chunks[index + 2] = hex
            index = index + 3
        end
    end
    return table_concat(chunks)
end

------------------------------------------------------------------------------
--
-- Base-85 Encoder / Decoder
-- =========================
--
-- To create a custom `encoding` table for use with `Base85Encode` and
-- `Base85Decode`, it must contain the following:
--
--  * `toBase85`              [table]
--      Mapping from 0 through 84 to characters.
--
--  * `fromBase85`            [table]
--      Mapping from characters to 0 through 84.
--
--  * `zeroChar`              [character, optional]
--      Used to represents a group group zero-bytes.
--
--  * `invalidChars`          [pattern, optional]
--      Characters to be rejected as errors.  The base-85 characters are
--      already excluded so it's OK for this pattern to match them.
--
---

_M.BASE85 = {}

---
-- The standard ASCII85 encoding for encoding data in base-85.
--
_M.BASE85.ASCII = {
    zeroChar = "z",
    invalidChars = "[^%s]",
    toBase85 = {
        [0] = "!", '"', "#", "$", "%", "&", "'", "(", ")", "*", "+", ",",
        "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F",
        "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S",
        "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`",
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
        "n", "o", "p", "q", "r", "s", "t", "u"
    },
    fromBase85 = {
        ["!"] = 0, ['"'] = 1, ["#"] = 2, ["$"] = 3, ["%"] = 4, ["&"] = 5,
        ["'"] = 6, ["("] = 7, [")"] = 8, ["*"] = 9, ["+"] = 10, [","] = 11,
        ["-"] = 12, ["."] = 13, ["/"] = 14, ["0"] = 15, ["1"] = 16,
        ["2"] = 17, ["3"] = 18, ["4"] = 19, ["5"] = 20, ["6"] = 21,
        ["7"] = 22, ["8"] = 23, ["9"] = 24, [":"] = 25, [";"] = 26,
        ["<"] = 27, ["="] = 28, [">"] = 29, ["?"] = 30, ["@"] = 31,
        ["A"] = 32, ["B"] = 33, ["C"] = 34, ["D"] = 35, ["E"] = 36,
        ["F"] = 37, ["G"] = 38, ["H"] = 39, ["I"] = 40, ["J"] = 41,
        ["K"] = 42, ["L"] = 43, ["M"] = 44, ["N"] = 45, ["O"] = 46,
        ["P"] = 47, ["Q"] = 48, ["R"] = 49, ["S"] = 50, ["T"] = 51,
        ["U"] = 52, ["V"] = 53, ["W"] = 54, ["X"] = 55, ["Y"] = 56,
        ["Z"] = 57, ["["] = 58, ["\\"] = 59, ["]"] = 60, ["^"] = 61,
        ["_"] = 62, ["`"] = 63, ["a"] = 64, ["b"] = 65, ["c"] = 66,
        ["d"] = 67, ["e"] = 68, ["f"] = 69, ["g"] = 70, ["h"] = 71,
        ["i"] = 72, ["j"] = 73, ["k"] = 74, ["l"] = 75, ["m"] = 76,
        ["n"] = 77, ["o"] = 78, ["p"] = 79, ["q"] = 80, ["r"] = 81,
        ["s"] = 82, ["t"] = 83, ["u"] = 84
    }
}

---
-- Custom base-85 encoding for the internal messaging protocol.
--
_M.BASE85.FZM = {
    zeroChar = ".",
    invalidChars = "[^%s]",
    toBase85 = {
        [0] = "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b",
        "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o",
        "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "A", "B",
        "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O",
        "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_", "~",
        "-", "^", "=", "/", "+", "*", "%", "$", "#", "@", "&", "(", ")",
        "{", "}", "`", "'", ",", ";", "?", "!"
    },
    fromBase85 = {
         ["0"] = 0, ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
         ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9, ["a"] = 10, ["b"] = 11,
         ["c"] = 12, ["d"] = 13, ["e"] = 14, ["f"] = 15, ["g"] = 16,
         ["h"] = 17, ["i"] = 18, ["j"] = 19, ["k"] = 20, ["l"] = 21,
         ["m"] = 22, ["n"] = 23, ["o"] = 24, ["p"] = 25, ["q"] = 26,
         ["r"] = 27, ["s"] = 28, ["t"] = 29, ["u"] = 30, ["v"] = 31,
         ["w"] = 32, ["x"] = 33, ["y"] = 34, ["z"] = 35, ["A"] = 36,
         ["B"] = 37, ["C"] = 38, ["D"] = 39, ["E"] = 40, ["F"] = 41,
         ["G"] = 42, ["H"] = 43, ["I"] = 44, ["J"] = 45, ["K"] = 46,
         ["L"] = 47, ["M"] = 48, ["N"] = 49, ["O"] = 50, ["P"] = 51,
         ["Q"] = 52, ["R"] = 53, ["S"] = 54, ["T"] = 55, ["U"] = 56,
         ["V"] = 57, ["W"] = 58, ["X"] = 59, ["Y"] = 60, ["Z"] = 61,
         ["_"] = 62, ["~"] = 63, ["-"] = 64, ["^"] = 65, ["="] = 66,
         ["/"] = 67, ["+"] = 68, ["*"] = 69, ["%"] = 70, ["$"] = 71,
         ["#"] = 72, ["@"] = 73, ["&"] = 74, ["("] = 75, [")"] = 76,
         ["{"] = 77, ["}"] = 78, ["`"] = 79, ["'"] = 80, [","] = 81,
         [";"] = 82, ["?"] = 83, ["!"] = 84
    }
}

local BASE85_ASCII = _M.BASE85.ASCII

---
-- Encodes a string of bytes using a base-85 encoding.
--
-- @param  str                [string]
--   Data to be encoded.
--
-- @param  encoding           [table, optional]
--   Encoding table.  Default: `BASE85_ASCII`.
--
-- @return                    [string]
--   Encoded result.
--
function _M.Base85Encode(str, encoding)
    if not encoding then encoding = BASE85_ASCII end
    local toBase85 = encoding.toBase85
    local zeroChar = encoding.zeroChar or string_rep(toBase85[0], 5)
    local chunks = {}
    local chunksEnd = 1
    for group in string_gmatch(str, "(....)") do
        local b3, b2, b1, b0 = string_byte(group, 1, 4)
        local n = 16777216 * b3 + 65536 * b2 + 256 * b1 + b0
        if n == 0 then
            chunks[chunksEnd] = zeroChar
            chunksEnd = chunksEnd + 1
        else
            local r = n % 85
            chunks[chunksEnd + 4] = toBase85[r]
            n = (n - r) / 85
            r = n % 85
            chunks[chunksEnd + 3] = toBase85[r]
            n = (n - r) / 85
            r = n % 85
            chunks[chunksEnd + 2] = toBase85[r]
            n = (n - r) / 85
            r = n % 85
            chunks[chunksEnd + 1] = toBase85[r]
            n = (n - r) / 85
            chunks[chunksEnd] = toBase85[n]
            chunksEnd = chunksEnd + 5
        end
    end
    local padLen = #str % 4
    if padLen > 0 then
        local b3, b2, b1 = string_byte(str, -padLen, -1)
        -- Pad with zeros
        if not b2 then b2 = 0 end
        if not b1 then b1 = 0 end
        local n = 16777216 * b3 + 65536 * b2 + 256 * b1
        n = (n - n % 85) / 85
        local r = n % 85
        if padLen > 2 then
            chunks[chunksEnd + 3] = toBase85[r]
        end
        n = (n - r) / 85
        r = n % 85
        if padLen > 1 then
            chunks[chunksEnd + 2] = toBase85[r]
        end
        n = (n - r) / 85
        r = n % 85
        chunks[chunksEnd + 1] = toBase85[r]
        n = (n - r) / 85
        chunks[chunksEnd] = toBase85[n]
    end
    return table_concat(chunks)
end

---
-- Decodes a string of bytes using a base-85 encoding.
--
-- @param  str                [string]
--   Data to be decoded.
--
-- @param  encoding           [table, optional]
--   Encoding table.  Default: `BASE85_ASCII`.
--
-- @return                    [string or (`nil`, string)]
--   Decoded result.  If an error occurs, `nil` is returned along with an error
--   message.
--
function _M.Base85Decode(str, encoding)
    if not encoding then encoding = BASE85_ASCII end
    local fromBase85 = encoding.fromBase85
    local zeroChar = encoding.zeroChar
    local invalidChars = encoding.invalidChars or ".^" -- Won't ever match
    local chunks = {}
    local chunksEnd = 1
    local n = 0
    local j = 4
    local len = #str
    for i = 1, len do
        local char = string_sub(str, i, i)
        local value = fromBase85[char]
        if value then
            n = n * 85 + value
            if j > 0 then
                j = j - 1
            else
                local r = n % 256
                chunks[chunksEnd + 3] = string_char(r)
                n = (n - r) / 256
                r = n % 256
                chunks[chunksEnd + 2] = string_char(r)
                n = (n - r) / 256
                r = n % 256
                chunks[chunksEnd + 1] = string_char(r)
                n = (n - r) / 256
                if n > 255 then
                    -- `n` is too large to be converted into 4-bytes
                    return nil, string_format("group %q is invalid",
                                              string_sub(str, i - 4, i))
                end
                chunks[chunksEnd] = string_char(n)
                chunksEnd = chunksEnd + 4
                j = 4
                n = 0
            end
        elseif char == zeroChar then
            if j < 4 then
                return nil, string_format("%q found in middle of group", char)
            end
            chunks[chunksEnd] = "\000\000\000\000"
            chunksEnd = chunksEnd + 1
        elseif string_find(char, invalidChars) then
            return nil, string_format("invalid character %q", char)
        end
    end
    if j < 4 then
        if j == 3 then
            return nil, string_format("terminal group %q is incomplete",
                                      string_sub(str, -1))
        end
        -- Pad with 84's
        for i = 0, j do
            n = n * 85 + 84
        end
        n = (n - n % 256) / 256
        local r = n % 256
        if j < 1 then
            chunks[chunksEnd + 2] = string_char(r)
        end
        n = (n - r) / 256
        r = n % 256
        if j < 2 then
            chunks[chunksEnd + 1] = string_char(r)
        end
        n = (n - r) / 256
        if n > 255 then
            -- `n` is too large to be converted into 4-bytes
            return nil, string_format("group %q is invalid",
                                      string_sub(str, len - 3 + j, len))
        end
        chunks[chunksEnd] = string_char(n)
    end
    return table_concat(chunks)
end

------------------------------------------------------------------------------
--
-- String Streams
-- ==============
---

---
-- This class provides the ability to read a string in sequence from beginning
-- to end.
_M.StringReader = {}
_M.StringReader.__index = _M.StringReader

---
-- Creates a `StringReader` instance from the input string.
--
-- @param  str                [string]
--   The data to be read.
--
-- @return                    [`StringReader`]
--   An instance of the class.
--
function _M.StringReader.New(str)
    local self = {str = str, index = 1, len = #str}
    setmetatable(self, _M.StringReader)
    return self
end

---
-- Determines whether the stream has reached its end (i.e. nothing more can be
-- read).
--
-- @return                    [boolean]
--   `true` if the stream has reached its end.
--
function _M.StringReader:End()
    return self.index > self.len
end

---
-- Reads up to `size` characters from the stream and advances the stream
-- position by the number of characters read.
--
-- @param  size               [unsigned, optional]
--   Maximum number of characters to read.  If omitted, all remaining
--   characters will be read.
--
-- @return                    [string]
--   The data read from the stream.
--
function _M.StringReader:Read(size)
    local index = self.index
    if not size then
        return string_sub(self.str, index)
    end
    local new_index = index + size
    self.index = new_index
    return string_sub(self.str, index, new_index - 1)
end

---
-- Reads a byte from the stream and advances the stream position by one.
--
-- @return                    [`0` to `255`]
--   The value of the byte.
--
function _M.StringReader:ReadByte()
    local index = self.index
    self.index = index + 1
    return string_byte(string_sub(self.str, index, index))
end

---
-- Reads a nibble (half-byte) from the stream and advances the stream position
-- by one byte.  If the stream remains unchanged and `ReadNibble` is called
-- again, the remaining nibble is read without advancing the stream further.
-- The more significant half-byte is read first, followed by the less
-- significant one.
--
-- @return                    [`0` to `127`]
--   The value of the half-byte.
--
function _M.StringReader:ReadNibble()
    local nibbleIndex = self.nibbleIndex
    local index = self.index
    if nibbleIndex and nibbleIndex + 1 == index then
        self.nibbleIndex = nil
        return self.nibbleOther
    else
        local byte = string_byte(string_sub(self.str, index, index))
        local nibbleOther = byte % 16
        self.index = index + 1
        self.nibbleOther = nibbleOther
        self.nibbleIndex = index
        return (byte - nibbleOther) / 16
    end
end

---
-- Attempts to read the given Lua pattern from the current stream location and
-- advances the stream further if successful.
--
-- @param  pattern            [pattern]
--   The pattern to match.
--
-- @return                    [string or `nil`]
--   The matched result if successful.  On failure, `nil` is returned.
--
function _M.StringReader:ReadPattern(pattern)
    local index = self.index
    local results = {string_find(self.str, pattern, index)}
    if index == results[1] then
        self.index = results[2] + 1
        local captures = {}
        for resultIndex, result in ipairs(results) do
            captures[resultIndex - 2] = result
        end
        return unpack(captures)
    end
end

---
-- This class provides the ability to write a string from beginning to end in
-- variable-sized blocks of data.
_M.StringWriter = {}
_M.StringWriter.__index = _M.StringWriter

---
-- Creates a `StringWriter` that allows stream-based writing.
--
-- @return                    [`StringWriter`]
--   An instance of the class.
--
function _M.StringWriter.New()
    local chunks = {}
    local self = {chunks = chunks, index = #chunks + 1}
    setmetatable(self, _M.StringWriter)
    return self
end

---
-- Writes a string to the stream.
--
-- @param str                 [string]
--   The data to be written.
--
function _M.StringWriter:Write(str)
    local index = self.index
    self.chunks[index] = str
    self.index = index + 1
end

---
-- Writes a byte to the stream.
--
-- @param  byte               [`0` to `255`]
--   The data to be written.
--
function _M.StringWriter:WriteByte(byte)
    local index = self.index
    self.chunks[index] = byte
    self.index = index + 1
end

---
-- Writes a nibble (half-byte) to the stream in the more significant half and
-- advances the stream by one byte.  If another nibble is immediately written,
-- then it will fill the less significant half of the same byte without
-- advancing the stream further.
--
-- @param  nibble             [`0` to `127`]
--   The data to be written.
--
function _M.StringWriter:WriteNibble(nibble)
    local nibbleIndex = self.nibbleIndex
    local index = self.index
    if nibbleIndex and nibbleIndex + 1 == index then
        local chunks = self.chunks
        chunks[nibbleIndex] = chunks[nibbleIndex] + nibble
        self.nibbleIndex = nil
    else
        self.chunks[index] = nibble * 16
        self.index = index + 1
        self.nibbleIndex = index
    end
end

---
-- Merges data from another writer into the current one.
--
-- @param  writer             [`StringWriter`]
--   The data to be merged in.
--
function _M.StringWriter:Merge(writer)
    local chunks = self.chunks
    local lastIndex = self.index - 1
    for chunkIndex, chunk in ipairs(writer.chunks) do
        chunks[lastIndex + chunkIndex] = chunk
    end
    self.index = lastIndex + writer.index
end

---
-- Constructs a string that contains all the written data
--
-- @return                    [string]
--   All of the written data.
--
function _M.StringWriter:ToString()
    local chunks = self.chunks
    for chunkIndex, chunk in ipairs(chunks) do
        if type(chunk) == "number" then
            chunks[chunkIndex] = string_char(chunk)
        end
    end
    return table_concat(chunks)
end

------------------------------------------------------------------------------
--
-- Data Serialization
-- ==================
---

---
-- Contains various serialization formats.
--
-- `FZSF1`
--   FZ Serialization Format version 1.
--
-- `FZSF0`
--   FZ Serialization Format version 0 (deprecated).
--
-- `ACE3`
--   AceSerializer-3.0 Format (requires Ace3 to be installed).
--
_M.SERIALIZATION_FORMAT = {
    FZSF0 = 0x40,
    FZSF1 = 0x20,
    ACE3 = 0x50,
}

local StringReader = _M.StringReader
local StringWriter = _M.StringWriter
local newWriter = StringWriter.New
local writerToString = StringWriter.ToString
local write = StringWriter.Write
local writeByte = StringWriter.WriteByte
local writeNibble = StringWriter.WriteNibble
local newReader = StringReader.New
local readerEnd = StringReader.End
local read = StringReader.Read
local readNibble = StringReader.ReadNibble
local readPattern = StringReader.ReadPattern

local FORMAT = _M.SERIALIZATION_FORMAT
local TYPE_NIL = 0x0
local TYPE_BOOLEAN_FALSE = 0x1
local TYPE_BOOLEAN_TRUE = 0x2
local TYPE_TABLE = 0x3
local TYPE_INT = 0x4
local TYPE_FLOAT = 0x5
local TYPE_STRING = 0x6
local TYPE_STRING_REF = 0x7
local TYPE_ARRAY = 0x8

-- Note: on some platforms NaN can cause crashes so support has been removed.
local INF = math.huge
local NAN = nil -- (-1)^.5

-- Find the maximum integer that can be represented fully
local INT_MAX
local EXP_MAX = 1024                    -- Safety net to prevent infinite loops
do
    local i = 1
    for n = 1, EXP_MAX do
        i = i * 2
        if i + 1 == i then break end
    end
    INT_MAX = i / 2
end

-- Encodes an nonnegative integer of arbitrary size into a variable-length
-- string.  This returns a string in which all characters have byte-value 127
-- or lower, except for the very last character whose value is 128 or higher.
--
-- The `flag` parameter can be used to attach an additional unsigned integer
-- of fixed size to the returned string (e.g. to store sign information).  The
-- parameter `flagSize` is to be specified in bits (at most 7).
local function encodeUnsigned(unsigned, flag, flagSize)
    if not flag then flag = 0 end
    if not flagSize then flagSize = 0 end
    local leftover = 128 / 2^flagSize
    local bytes = {flag * leftover + unsigned % leftover}
    local bytesEnd = 2
    unsigned = (unsigned - unsigned % leftover) / leftover
    while unsigned > 0 do
        bytes[bytesEnd] = unsigned % 128
        bytesEnd = bytesEnd + 1
        unsigned = (unsigned - unsigned % 128) / 128
    end
    bytes[bytesEnd - 1] = bytes[bytesEnd - 1] + 128
    return string_char(unpack(bytes))
end

-- Returns the original unsigned integer, the string captured, and the flag.
local function decodeUnsigned(stream, flagSize)
    if not flagSize then flagSize = 0 end
    local leftover = 128 / 2^flagSize
    local str = readPattern(stream, "([%z\001-\127]*[\128-\255])")
    if not str then return end
    local bytes = {string_byte(str, 1, -1)}
    local unsigned = 0
    for i = #str, 2, -1 do
        unsigned = unsigned * 128 + bytes[i]
    end
    unsigned = unsigned * leftover + bytes[1] % leftover
    return unsigned - 128, str, (bytes[1] - bytes[1] % leftover) / leftover
end

local function serializeObject(object, state)
    local size = ""
    local stream = newWriter()
    local typeID = TYPE_NIL
    local objectType = type(object)
    if objectType == "table" then
        typeID = TYPE_TABLE
    elseif objectType == "boolean" then
        typeID = object and TYPE_BOOLEAN_TRUE or TYPE_BOOLEAN_FALSE
    elseif objectType == "string" then
        typeID = TYPE_STRING
    elseif objectType == "number" then
        local n = object
        if n < 0 then
            n = -n
        end
        if n % 1 == 0 and n < INT_MAX then
            typeID = TYPE_INT
        else
            typeID = TYPE_FLOAT
        end
    end
    if not state then
        writeByte(stream, FORMAT.FZSF0 + typeID)
    end
    if typeID == TYPE_TABLE then
        if state then
            local cache = state.tableCache
            local ref = cache[object]
            if not ref then
                local cacheCount = state.tableCacheCount
                ref = encodeUnsigned(cacheCount)
                cache[object] = ref
                state.tableCacheCount = cacheCount + 1
                state.tables[cacheCount] = object
            end
            write(stream, ref)
        else
            state = {
                tables = {object},
                tableCache = {[object] = encodeUnsigned(0)},
                tableCacheCount = 1,
                stringCache = {},
                stringCacheCount = 0
            }
            local tables = state.tables
            local tableIndex = 0
            repeat
                local tableTypes = newWriter()
                local tableData = newWriter()
                local arrayIndices = {}
                local numItems = 0
                -- First serialize the array items
                for index, value in ipairs(object) do
                    local valueData, typeID, valueSize
                        = serializeObject(value, stream, state)
                    writeNibble(tableTypes, TYPE_ARRAY + typeID)
                    write(tableData, valueSize)
                    write(tableData, valueData)
                    arrayIndices[index] = true
                    numItems = index
                end
                -- Then serialize the non-array items
                for key, value in pairs(object) do
                    if not arrayIndices[key] then
                        local keyData, keyType, keySize
                            = serializeObject(key, stream, state)
                        writeNibble(tableTypes, keyType)
                        write(tableData, keySize)
                        write(tableData, keyData)
                        local valueData, typeID, valueSize
                            = serializeObject(value, stream, state)
                        writeNibble(tableTypes, typeID)
                        write(tableData, valueSize)
                        write(tableData, valueData)
                        numItems = numItems + 1
                    end
                end
                write(stream, encodeUnsigned(numItems))
                merge(stream, tableTypes)
                merge(stream, tableData)
                tableIndex = tableIndex + 1
                object = tables[tableIndex]
            until object == nil
        end
    elseif typeID == TYPE_INT then
        -- Make it nonnegative and store the sign as an extra bit
        if object < 0 then
            write(stream, encodeUnsigned(-object, 1, 1))
        else
            write(stream, encodeUnsigned(object, 0, 1))
        end
    elseif typeID == TYPE_FLOAT then
        local e, s, eSign, sSign, de
        -- Store special numbers using an abnormal combo of sign & magnitude
        if object == INF then
            if object == -INF then
                eSign, e, sSign, s = 1, 0, 0, 0 -- Not-a-number
            else
                eSign, e, sSign, s = 1, 0, 0, 1 -- Infinity
            end
        elseif object == -INF then
            eSign, e, sSign, s = 1, 0, 1, 1 -- Minus-infinity
        elseif not (object == object) then
            eSign, e, sSign, s = 1, 0, 0, 0 -- Not-a-number
        else
            sSign, eSign = 0, 0
            s, e = math_frexp(object)
            -- Make the significand an integer by altering the exponent
            for i = 1, 1024 do
                s = s * 2
                e = e - 1
                if s % 1 == 0 then
                    break
                end
            end
            s = s - s % 1
            -- Make them nonnegative and store the sign as an extra bit
            if s < 0 then
                sSign = 1
                s = -s
            end
            if e < 0 then
                eSign = 1
                e = -e
            end
        end
        write(stream, encodeUnsigned(e, eSign, 1)) -- Exponent
        write(stream, encodeUnsigned(s, sSign, 1)) -- Significand
    elseif typeID == TYPE_STRING then
        local len = #object
        size = encodeUnsigned(len)
        if state then                   -- This is not the root element
            local cache = state.stringCache
            local ref = cache[object]
            if ref then                 -- Reference is worth using
                typeID = TYPE_STRING_REF
                size = ""
                object = ref
            elseif ref == nil then      -- Has never been cached
                local cacheCount = state.stringCacheCount
                local ref = encodeUnsigned(cacheCount)
                if #ref <= #size + len then -- There is a size benefit
                    cache[object] = ref
                    state.stringCacheCount = cacheCount + 1
                else                    -- No benefit; avoid using it
                    cache[object] = false
                end
            end
        end
        write(stream, object)
    end
    return writerToString(stream), typeID, size
end

local function deserializeObject(typeID, stream, state)
    if typeID == TYPE_TABLE then
        if state then
            local ref = decodeUnsigned(stream)
            local cache = state.tableCache
            local t = cache[ref]
            if not t then
                t = {}
                cache[ref] = t
            end
            return t
        end
        state = {
            tableCache = {},
            tableCacheCount = 0,
            stringCache = {},
            stringCacheCount = 0
        }
        local cache = state.tableCache
        repeat
            local numItems = decodeUnsigned(stream)
            local keyTypes = {}
            local valueTypes = {}
            for i = 1, numItems do
                local nibble = readNibble(stream)
                if nibble >= TYPE_ARRAY then
                    keyTypes[i] = TYPE_ARRAY
                    valueTypes[i] = nibble % TYPE_ARRAY
                else
                    keyTypes[i] = nibble
                    valueTypes[i] = readNibble(stream)
                end
            end
            local count = state.tableCacheCount
            local t = cache[count]
            if not t then
                t = {}
                cache[count] = t
            end
            state.tableCacheCount = count + 1
            for i = 1, numItems do
                local keyType = keyTypes[i]
                if keyType == TYPE_ARRAY then
                    t[i] = deserializeObject(valueTypes[i], stream, state)
                else
                    local key = deserializeObject(keyType, stream, state)
                    if key then
                        t[key] = deserializeObject(valueTypes[i], stream, state)
                    end
                end
            end
        until readerEnd(stream)
        return cache[0]
    elseif typeID == TYPE_INT then
        local magnitude, sign = decodeUnsigned(stream, 1)
        if sign == 1 then
            return -magnitude
        end
        return magnitude
    elseif typeID == TYPE_FLOAT then
        local e, eSign = decodeUnsigned(stream, 1)
        local s, sSign = decodeUnsigned(stream, 1)
        if eSign == 1 then
            if e == 0 then              -- Special value
                if s == 0 then
                    return NAN
                elseif sSign == 0 then
                    return INF
                end
                return -INF
            end
            e = -e
        end
        if sSign == 1 then
            s = -s
        end
        return math_ldexp(s, e)
    elseif typeID == TYPE_STRING then
        if state then
            local cache = state.stringCache
            local size, sizeStr = decodeUnsigned(stream)
            local str = read(stream, size)
            local cacheCount = state.stringCacheCount
            local ref = encodeUnsigned(cacheCount)
            -- Check if there's any size benefit before caching it
            if #ref <= #sizeStr + #str then
                cache[cacheCount] = str
                state.stringCacheCount = cacheCount + 1
            end
            return str
        end
        return read(stream)
    elseif typeID == TYPE_STRING_REF then
        if state then
            local cache = state.stringCache
            local size = decodeUnsigned(stream)
            if cache and size then
                return cache[size]
            end
        end
    elseif typeID == TYPE_BOOLEAN_FALSE then
        if not (state or readerEnd(stream)) then
            return nil, "trailing garbage found"
        end
        return false
    elseif typeID == TYPE_BOOLEAN_TRUE then
        if not (state or readerEnd(stream)) then
            return nil, "trailing garbage found"
        end
        return true
    elseif typeID == TYPE_NIL then   -- Return nothing
    else
        return nil, "invalid root type identifier"
    end
end

---
-- Serializes/deserializes an arbitrary Lua object.
--
-- FZSF1-specific: Any unserializable data will be ignored.
--
-- @param  object             [anything]
--   Object to be serialized.
--
-- @param  format             [member of `SERIALIZATION_FORMAT`, optional]
--   Serialization format.
--
-- @return                    [string or (`nil`, string)]
--   Serialized data.  If an error occurs, `nil` is returned along with an
--   error message.
--
function _M.Serialize(object, format)
    if not format then format = FORMAT.FZSF1 end
    if format == FORMAT.FZSF1 then
        return serializeObject(object)
    elseif format == FORMAT.FZSF0 then
        -- Known bug: NaN can get mixed up with +/-Infinity.
        local chunks = {}
        local chunksEnd = 1
        local objects = {object}           -- Stores all objects as an array
        local objects_i = {[object] = 1}   -- Stores indices of the objects
        local objectsEnd = 2
        repeat
            local chunk
            local object_type = type(object)
            if object_type == "table" then
                -- The table keys and values are stored as references only.
                -- This saves space and also allows recursive tables to be
                -- handled easily.
                local items = {}
                local itemsEnd = 1
                for key, value in pairs(object) do
                    local key_i = objects_i[key]
                    if not key_i then
                        key_i = objectsEnd
                        objects_i[key] = key_i
                        objects[key_i] = key
                        objectsEnd = key_i + 1
                    end
                    local value_i = objects_i[value]
                    if not value_i then
                        value_i = objectsEnd
                        objects_i[value] = value_i
                        objects[value_i] = value
                        objectsEnd = value_i + 1
                    end
                    items[itemsEnd] = string_format("%x=%x", key_i, value_i)
                    itemsEnd = itemsEnd + 1
                end
                chunk = "T" .. table_concat(items, ",")
            elseif object_type == "boolean" then
                chunk = object and "BB" or "B"
            elseif object_type == "string" then
                chunk = string_format("S%s", _M.PercentEncode(object))
            elseif object_type == "number" then
                local numStr = tostring(object)
                if tonumber(numStr) == object then
                    chunk = "N" .. _M.PercentEncode(numStr)
                else
                    -- Some Lua interpreters can be finicky with NaN: the only
                    -- way to figure if it is NaN is by excluding the
                    -- possibility of being Inf, -Inf, or a real number.
                    if object == math_huge then
                        if object == -math_huge then
                            chunk = "Nnan"
                        else
                            chunk = "Ninf"
                        end
                    elseif object == -math_huge then
                        chunk = "N-inf"
                    else
                        chunk = "Nnan"
                    end
                end
            else
                chunk = ""
            end
            chunks[chunksEnd] = chunk
            chunksEnd = chunksEnd + 1
            object = objects[chunksEnd]
        until object == nil
        return table.concat(chunks, ";")
    elseif format == FORMAT.ACE3 then
        local LibStub = LibStub
        if not LibStub then
            return nil, "Cannot find LibStub."
        end
        local AceSerializer = LibStub:GetLibrary("AceSerializer-3.0")
        if not AceSerializer then
            return nil, "Cannot find AceSerializer-3.0."
        end
        return AceSerializer:Serialize(object)
    end
    return nil, "Unknown serialization format."
end

---
-- Deserializes data returned from Serialize.
--
-- @param objectStr           [string]
--   Serialized data.
--
-- @return                    [anything or (`nil`, string)]
--   An object deserialized from the string.  If a decoding error occurs, `nil`
--   is returned along with the error message.
--
function _M.Deserialize(objectStr)
    if objectStr == "" then return end
    local formatChar = string_sub(objectStr, 1, 1)
    local formatByte = string_byte(formatChar)
    local format = formatByte - formatByte % 16
    local FZSF0_formatChars = {T = 0, B = 0, S = 0, N = 0}
    if format == FORMAT.FZSF1 then
        return deserializeObject(formatByte % 16, newReader(objectStr))
    elseif FZSF0_formatChars[formatChar] then
        local objects = {}              -- Stores all objects as an array
        local objects_i = {}
        local objectsEnd = 1
        for chunkType, data in string_gmatch(objectStr, "([^;]?)([^;]*);?") do
            local object
            if chunkType == "T" then
                -- For now, only keep track of the references since not every
                -- table has been constructed yet
                local object_i = {}
                for key_i, value_i in string_gmatch(data, "(%x+)=(%x+),?") do
                    object_i[tonumber(key_i, 16)] = tonumber(value_i, 16)
                end
                object = {}
                objects_i[object] = object_i
            elseif chunkType == "B" then
                object = data ~= ""
            elseif chunkType == "S" then
                object = _M.PercentDecode(data)
            elseif chunkType == "N" then
                if data == "inf" then
                    object = math_huge
                elseif data == "-inf" then
                    object = -math_huge
                elseif data == "nan" then
                    object = 0 / 0
                else
                    object = tonumber(_M.PercentDecode(data))
                end
            end
            objects[objectsEnd] = object
            objectsEnd = objectsEnd + 1
        end
        -- Reconstruct the tables
        for _, object in pairs(objects) do
            if type(object) == "table" then
                for key_i, value_i in pairs(objects_i[object]) do
                    local key = objects[key_i]
                    if key then
                        object[key] = objects[value_i]
                    end
                end
            end
        end
        return objects[1]
    elseif format == FORMAT.ACE3 then
        local LibStub = LibStub
        if not LibStub then
            return nil, "Cannot find LibStub."
        end
        local AceSerializer = LibStub:GetLibrary("AceSerializer-3.0")
        if not AceSerializer then
            return nil, "Cannot find AceSerializer-3.0."
        end
        return AceSerializer:Deserialize(objectStr)
    end
    return nil, "Unknown serialization format."
end

------------------------------------------------------------------------------
-- |HFZM:__________|h |h
-- Packet control chars: 11 (244 chars left)
-- Each 32-bit int requires: 5 chars (base-85)
-- For SendAddonMessage, all 255 chars are available (+10 more b85's).

local playerName = UnitName("player")
local playerRealm = GetRealmName()

-- If a message is being sent directly to the player himself, bypass all the
-- chat channels and just send it to the same client for greater efficiency
-- (although this is a rare usage).  Use SendChatMessage if the player is
-- already on the same realm+faction (i.e. don't unnecessarily use
-- BNSendWhisper)

local dataIndex = 0
local function bnFilter(_, _, text)

    -- FZM protocol
    if string_match(text, "^|HFZM:") then
        return true
    end

    -- FZXC protocol
    if string_match(text, "^|HFZXC:") then
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


-- Message receiver
local function onEvent(_, event, arg1, arg2, _, arg4)

    if event == "CHAT_MSG_ADDON" then
        if arg1 ~= "FZM" then return end
        -- Handle realm-local message
        -- (prefix, message, channel, sender)

        -- NOTE: Messages that use CHAT_MSG_ADDON in lieu of BN_CHAT_MSG_ADDON will
        --       need to be dealt with separately.

        -- TODO: not implemented

    elseif event == "BN_CHAT_MSG_ADDON" then
        -- Handle cross-realm message
        -- arg1 = prefix, arg2 = data, arg4 = sender's toonID

        --@alpha@
        if FZMP_DEBUG then
            print("libfzmp: onEvent: BN_CHAT_MSG_ADDON from presenceID = ",
                  arg4)
        end
        --@end-alpha@

        if arg1 == "FZXC" then
            local data = _M.Deserialize(arg2)

            local prefixListeners = listeners["FZXC"]
            if prefixListeners then
                for listener, _ in pairs(prefixListeners) do
                    listener(prefix, data, "BN_CHAT_MSG_ADDON", arg4)
                end
            end
        end
    end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", onUpdate)
frame:SetScript("OnEvent", onEvent)
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
frame:RegisterEvent("BN_CHAT_MSG_ADDON")
ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER", bnFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER_INFORM", bnFilter)
if not RegisterAddonMessagePrefix("FZM") then
    DEFAULT_CHAT_FRAME:AddMessage("libfzmp: failed to load.", 1, 0, 0)
    error('RegisterAddonMessagePrefix("FZM") failed.')
end

-- For now, payload is assumed to be an array of strings (or just a string)
-- prefix must be 16 chars or fewer
function _M.SendMessage(prefix, data, channel, recipient)
    if channel == "BN_CHAT_MSG_ADDON" then

        -- FZXC protocol
        if prefix == "FZXC" then

            if type(data) == "string" then
                data = {data}
            end

            local payload = _M.Serialize(data, FORMAT.FZSF0)
            BNSendGameData(recipient, "FZXC", payload)

            --@alpha@
            if FZMP_DEBUG then
                print("libfzmp: FZMP.SendMessage: sending message to",
                      recipient)
            end
            --@end-alpha@

        else
            -- TODO: other prefixes are not supported yet
        end

    else
         -- TODO: other channels are not supported yet
    end
end

-- The listener is of the form: (prefix, data, channel, sender)
function _M.RegisterMessageListener(prefix, listener)
    local prefixListeners = listeners[prefix]
    if not prefixListeners then
        prefixListeners = {}
        listeners[prefix] = prefixListeners
    end
    prefixListeners[listener] = true
end

function _M.UnregisterMessageListener(prefix, listener)
    local prefixListeners = listeners[prefix]
    if prefixListeners then
        prefixListeners[listener] = nil
        if #prefixListeners == 0 then
            listeners[prefix] = nil
        end
    end
end
