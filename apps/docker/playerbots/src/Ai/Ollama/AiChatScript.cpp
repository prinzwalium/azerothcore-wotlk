/*
 * This file is part of the mod-playerbots module for AzerothCore. See AUTHORS file for Copyright
 * information; released under GNU GPL v2 license, redistribute/modify under version 2 of the License,
 * or (at your option) any later version.
 */

#include "AiChatBridge.h"
#include "AiChatConfig.h"
#include "AiChatUtil.h"
#include "Playerbots.h"
#include "ScriptMgr.h"

namespace
{
    // A bot takes natural language from its own master, and -- only if the
    // realm opts in -- from anyone grouped with it. Without this, any player
    // able to reach a chat channel a bot listens to could drive someone else's
    // bots around.
    bool MayCommand(Player* bot, Player* from)
    {
        PlayerbotAI* botAI = GET_PLAYERBOT_AI(bot);
        if (!botAI)
            return false;

        // Only real people give orders: bots talking to each other must not
        // start a chain of translations.
        if (GET_PLAYERBOT_AI(from))
            return false;

        if (botAI->GetMaster() == from)
            return true;

        if (!AiChatConfig::instance().commandFromGroupMembers)
            return false;

        Group* group = bot->GetGroup();
        return group && group == from->GetGroup();
    }

    // Literal commands are already handled by the module's own parser, so
    // sending them through a language model as well would dispatch them twice.
    bool IsAlreadyACommand(std::string const& message)
    {
        std::string matched;
        return AiChatUtil::IsAllowedCommand(AiChatUtil::NormalizeCommand(message),
                                            AiChatConfig::instance().allowed, matched);
    }

    void Consider(Player* bot, Player* from, std::string const& message)
    {
        if (!bot || !from || bot == from)
            return;

        if (!MayCommand(bot, from))
            return;

        sAiChatBridge.Submit(bot, from, message);
    }

    void ConsiderGroup(Player* from, std::string const& message)
    {
        Group* group = from->GetGroup();
        if (!group)
            return;

        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
        {
            Player* member = ref->GetSource();
            if (member && GET_PLAYERBOT_AI(member))
                Consider(member, from, message);
        }
    }

    bool Ready(std::string const& message)
    {
        return AiChatConfig::instance().enabled && !message.empty() && !IsAlreadyACommand(message);
    }
}

class PlayerbotsAiChatPlayerScript : public PlayerScript
{
public:
    PlayerbotsAiChatPlayerScript()
        : PlayerScript("PlayerbotsAiChatPlayerScript",
                       { PLAYERHOOK_CAN_PLAYER_USE_CHAT, PLAYERHOOK_CAN_PLAYER_USE_PRIVATE_CHAT,
                         PLAYERHOOK_CAN_PLAYER_USE_GROUP_CHAT, PLAYERHOOK_CAN_PLAYER_USE_GUILD_CHAT })
    {
    }

    // Say and yell. Off by default: everything in earshot would answer.
    bool OnPlayerCanUseChat(Player* player, uint32 /*type*/, uint32 /*language*/, std::string& msg) override
    {
        if (!AiChatConfig::instance().commandFromSay || !player || !Ready(msg))
            return true;

        Group* group = player->GetGroup();
        if (group)
            ConsiderGroup(player, msg);

        return true;
    }

    // Whisper: the clearest case, since the message names exactly one bot.
    bool OnPlayerCanUseChat(Player* player, uint32 /*type*/, uint32 /*language*/, std::string& msg,
                            Player* receiver) override
    {
        if (!AiChatConfig::instance().commandFromWhisper || !player || !receiver || !Ready(msg))
            return true;

        if (GET_PLAYERBOT_AI(receiver))
            Consider(receiver, player, msg);

        return true;
    }

    // Party and raid: "wait here while I tame this" lands here.
    bool OnPlayerCanUseChat(Player* player, uint32 /*type*/, uint32 /*language*/, std::string& msg,
                            Group* /*group*/) override
    {
        if (!AiChatConfig::instance().commandFromParty || !player || !Ready(msg))
            return true;

        ConsiderGroup(player, msg);
        return true;
    }

    bool OnPlayerCanUseChat(Player* player, uint32 /*type*/, uint32 /*language*/, std::string& msg,
                            Guild* /*guild*/) override
    {
        if (!AiChatConfig::instance().commandFromGuild || !player || !Ready(msg))
            return true;

        ConsiderGroup(player, msg);
        return true;
    }
};

class PlayerbotsAiChatWorldScript : public WorldScript
{
public:
    PlayerbotsAiChatWorldScript()
        : WorldScript("PlayerbotsAiChatWorldScript",
                      { WORLDHOOK_ON_AFTER_CONFIG_LOAD, WORLDHOOK_ON_UPDATE, WORLDHOOK_ON_SHUTDOWN })
    {
    }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        AiChatConfig::instance().Load();

        if (AiChatConfig::instance().enabled)
            sAiChatBridge.Start();
        else
            sAiChatBridge.Stop();
    }

    // Draining on the world tick is what keeps the HTTP call off it: the
    // workers only ever hand back finished answers.
    void OnUpdate(uint32 /*diff*/) override { sAiChatBridge.Update(); }

    void OnShutdown() override { sAiChatBridge.Stop(); }
};

void AddPlayerbotsAiChatScripts()
{
    new PlayerbotsAiChatPlayerScript();
    new PlayerbotsAiChatWorldScript();
}
