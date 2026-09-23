/*
 * This file is part of the mod-playerbots module for AzerothCore. See AUTHORS file for Copyright
 * information; released under GNU GPL v2 license, redistribute/modify under version 2 of the License,
 * or (at your option) any later version.
 */

#ifndef PLAYERBOTS_AICHATCONFIG_H
#define PLAYERBOTS_AICHATCONFIG_H

#include <cstdint>
#include <string>
#include <vector>

// Settings for the Ollama bridge, read once rather than per chat line.
struct AiChatConfig
{
    static AiChatConfig& instance();

    void Load();

    bool enabled = false;

    std::string host = "ollama";
    uint16_t port = 11434;
    std::string path = "/api/chat";
    std::string model = "llama3.1:8b";
    uint32_t timeoutMs = 8000;

    uint32_t workers = 2;
    uint32_t maxQueue = 32;
    uint32_t cooldownMs = 3000;

    // Chat scopes that may carry commands. Only ever whisper and party by
    // default: a bot taking orders from /guild or a public channel means anyone
    // can drive someone else's bots.
    bool commandFromWhisper = true;
    bool commandFromParty = true;
    bool commandFromGuild = false;
    bool commandFromSay = false;

    // "master" -- only the bot's own master may command it (default)
    // "group"  -- anyone grouped with the bot may
    bool commandFromGroupMembers = false;

    bool confirm = true;

    std::vector<std::string> allowed;

    std::string systemPrompt;
};

#endif
