-- AzerothCore GM Admin Panel: transport layer over the addon channel.
--
-- The worldserver's AddonChannelCommandHandler (src/server/game/Chat/Chat.cpp)
-- accepts messages shaped:
--
--     AzerothCore\t<opcode><4-char counter><body>
--
-- The 3.3.5 client's SendAddonMessage(prefix, body, "WHISPER", target) sends
-- exactly "prefix\tbody" with LANG_ADDON to the named player, which is what
-- the server parses. Replies come back as CHAT_MSG_ADDON events with the same
-- prefix, so no chat-frame filters are needed.
--
-- The server:
--   * acks with 'a', echoed counter, on any valid command,
--   * replies 'o' on success, 'f' on failure,
--   * streams output back as 'm' lines, escaped for the chat pipe character.

local Counter = 0
local Pending = {}
local Available = nil  -- nil = unknown, true after first reply
local PREFIX = "AzerothCore"

local function NextCounter()
    Counter = Counter + 1
    if Counter > 9999 then
        Counter = 1
    end
    return string.format("%04d", Counter)
end

local eventFrame

function ACGMPanel.Commands.Init()
    if eventFrame then
        return
    end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
        if prefix == PREFIX and channel == "WHISPER" then
            ACGMPanel.Commands.HandleReply(message)
        end
    end)
end

function ACGMPanel.Commands.HandleReply(msg)
    if type(msg) ~= "string" or msg:len() < 5 then
        return
    end

    local opcode = msg:sub(1, 1)
    local echo = msg:sub(2, 5)
    local body = msg:sub(6)

    Available = true

    if opcode == "a" then
        -- Ack only; ok/fail/messages follow.
    elseif opcode == "o" then
        ACGMPanel.Commands.Dispatch(echo, "ok", "")
    elseif opcode == "f" then
        ACGMPanel.Commands.Dispatch(echo, "failed", body)
    elseif opcode == "m" then
        -- Unescape the pipe doubling the server applied.
        body = body:gsub("||", "|")
        ACGMPanel.Commands.Dispatch(echo, "message", body)
    end
end

function ACGMPanel.Commands.Dispatch(echo, kind, body)
    local callback = Pending[echo]
    if callback then
        local keep = callback(kind, body)
        if not keep then
            Pending[echo] = nil
        end
    end

    -- Everything is mirrored to the console regardless of callbacks.
    ACGMPanel.Console.Receive(kind, body)
end

-- Send a command. callback(kind, body) is called for each reply; return true
-- from it to keep receiving (for multi-line output), false/nil to detach.
function ACGMPanel.Commands.Send(command, callback)
    if type(command) ~= "string" or command == "" then
        return
    end

    local counter = NextCounter()
    -- 'h' = human-readable command; the leading '.' is optional in the
    -- server's parser but kept for clarity.
    local body = "h" .. counter .. command

    if callback then
        Pending[counter] = callback
    end

    SendAddonMessage(PREFIX, body, "WHISPER", UnitName("player"))
end

-- Probe the channel once at login. The protocol ping ('p') is answered with
-- ack only, which proves the channel works; '.account' additionally reveals
-- whether the account may run commands at all, since its output only arrives
-- for accounts that can.
function ACGMPanel.Commands.Ping()
    SendAddonMessage(PREFIX, "p0001", "WHISPER", UnitName("player"))

    ACGMPanel.Commands.Send(".account", function(kind, body)
        if kind == "message" then
            ACGMPanel._isGM = true
            ACGMPanel._gmChecked = true
            return false
        elseif kind == "failed" then
            ACGMPanel._isGM = false
            ACGMPanel._gmChecked = true
            return false
        end
        return true
    end)
end

function ACGMPanel.Commands.IsAvailable()
    return Available == true
end
