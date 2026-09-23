/*
 * This file is part of the mod-playerbots module for AzerothCore. See AUTHORS file for Copyright
 * information; released under GNU GPL v2 license, redistribute/modify under version 2 of the License,
 * or (at your option) any later version.
 */

#include "AiChatConfig.h"

#include "AiChatUtil.h"
#include "Config.h"
#include "Log.h"

#include <cstdint>

namespace
{
    // Commands a mistranslated sentence can trigger without costing anything
    // irreversible. Deliberately excludes destroy, sell, buy, trade, mail,
    // leave, and everything under guild: a model misreading "don't sell that"
    // must not be able to sell it.
    char const* DEFAULT_COMMANDS =
        "follow,stay,flee,runaway,grind,attack,pull,rti,formation,summon,repair,"
        "buff,home,max dps,tank attack,wait for attack,focus heal targets,co,nc";

    char const* DEFAULT_SYSTEM_PROMPT =
        "You translate a World of Warcraft player's message into one command for their companion bot. "
        "Reply with the command only: no punctuation, no quotes, no explanation. "
        "If the message is not an instruction, or no command fits, reply exactly: none. "
        "Available commands: {COMMANDS}. "
        "Strategies can be toggled with 'co +name' or 'nc -name' for combat and non-combat. "
        "Examples: 'wait here for me' -> stay. 'ok come on' -> follow. "
        "'get this one' -> attack. 'stop attacking' -> co +passive. 'how are you' -> none.";
}

AiChatConfig& AiChatConfig::instance()
{
    static AiChatConfig instance;
    return instance;
}

void AiChatConfig::Load()
{
    enabled = sConfigMgr->GetOption<bool>("AiPlayerbot.Ai.Enabled", false);

    host = sConfigMgr->GetOption<std::string>("AiPlayerbot.Ai.Host", "ollama");
    port = static_cast<uint16_t>(sConfigMgr->GetOption<uint32_t>("AiPlayerbot.Ai.Port", 11434));
    path = sConfigMgr->GetOption<std::string>("AiPlayerbot.Ai.Path", "/api/chat");
    model = sConfigMgr->GetOption<std::string>("AiPlayerbot.Ai.Model", "llama3.1:8b");
    timeoutMs = sConfigMgr->GetOption<uint32_t>("AiPlayerbot.Ai.TimeoutMs", 8000);

    workers = sConfigMgr->GetOption<uint32_t>("AiPlayerbot.Ai.Workers", 2);
    maxQueue = sConfigMgr->GetOption<uint32_t>("AiPlayerbot.Ai.MaxQueue", 32);
    cooldownMs = sConfigMgr->GetOption<uint32_t>("AiPlayerbot.Ai.CooldownMs", 3000);

    // Clamp rather than trust: a worker count of 0 would wedge the queue, and a
    // large one would let a busy realm bury a local model.
    if (workers < 1) workers = 1;
    if (workers > 8) workers = 8;
    if (maxQueue < 1) maxQueue = 1;
    if (timeoutMs < 500) timeoutMs = 500;
    if (timeoutMs > 60000) timeoutMs = 60000;

    std::string const scopes =
        sConfigMgr->GetOption<std::string>("AiPlayerbot.Ai.CommandScopes", "whisper,party");
    std::vector<std::string> const list = AiChatUtil::SplitList(scopes);

    commandFromWhisper = AiChatUtil::ListContains(list, "whisper");
    commandFromParty = AiChatUtil::ListContains(list, "party");
    commandFromGuild = AiChatUtil::ListContains(list, "guild");
    commandFromSay = AiChatUtil::ListContains(list, "say");

    std::string const from = sConfigMgr->GetOption<std::string>("AiPlayerbot.Ai.CommandFrom", "master");
    commandFromGroupMembers = from == "group";

    confirm = sConfigMgr->GetOption<bool>("AiPlayerbot.Ai.Confirm", true);

    allowed = AiChatUtil::SplitList(
        sConfigMgr->GetOption<std::string>("AiPlayerbot.Ai.Commands", DEFAULT_COMMANDS));

    systemPrompt = sConfigMgr->GetOption<std::string>("AiPlayerbot.Ai.SystemPrompt", DEFAULT_SYSTEM_PROMPT);

    // Let the prompt carry the same list the validator enforces, so the model is
    // not being asked to guess at a vocabulary it will then be judged against.
    std::string joined;
    for (std::string const& entry : allowed)
        joined += (joined.empty() ? "" : ", ") + entry;

    std::size_t const marker = systemPrompt.find("{COMMANDS}");
    if (marker != std::string::npos)
        systemPrompt = systemPrompt.substr(0, marker) + joined + systemPrompt.substr(marker + 10);

    if (enabled)
        LOG_INFO("playerbots", "AiChat: enabled, model {} at {}:{}{}, {} command(s) allowed, scopes:{}{}{}{}",
                 model, host, port, path, allowed.size(),
                 commandFromWhisper ? " whisper" : "", commandFromParty ? " party" : "",
                 commandFromGuild ? " guild" : "", commandFromSay ? " say" : "");
}
