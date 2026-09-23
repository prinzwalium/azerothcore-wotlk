/*
 * This file is part of the mod-playerbots module for AzerothCore. See AUTHORS file for Copyright
 * information; released under GNU GPL v2 license, redistribute/modify under version 2 of the License,
 * or (at your option) any later version.
 */

#include "AiChatBridge.h"

#include "AiChatConfig.h"
#include "AiChatUtil.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "OllamaClient.h"
#include "Playerbots.h"

#include <sstream>

namespace
{
    // Enough of the situation for the model to resolve "get this one" or
    // "wait here", without sending anything that would be stale by the time the
    // answer comes back.
    std::string BuildPrompt(Player* bot, Player* from, std::string const& message)
    {
        std::ostringstream out;

        out << "You are " << bot->GetName() << ", level " << uint32_t(bot->GetLevel())
            << ", a companion of " << from->GetName() << ".";

        if (bot->IsInCombat())
            out << " You are in combat.";

        out << " Message: " << AiChatUtil::ClampChat(message, 200);

        return out.str();
    }
}

AiChatBridge& AiChatBridge::instance()
{
    static AiChatBridge instance;
    return instance;
}

void AiChatBridge::Start()
{
    if (_running.load())
        return;

    AiChatConfig const& config = AiChatConfig::instance();
    if (!config.enabled)
        return;

    _running.store(true);

    for (uint32_t i = 0; i < config.workers; ++i)
        _workers.emplace_back([this]() { WorkerLoop(); });

    LOG_INFO("playerbots", "AiChat: started {} worker thread(s)", _workers.size());
}

void AiChatBridge::Stop()
{
    if (!_running.exchange(false))
        return;

    _requestCv.notify_all();

    for (std::thread& worker : _workers)
        if (worker.joinable())
            worker.join();

    _workers.clear();

    {
        std::lock_guard<std::mutex> guard(_requestMutex);
        _requests.clear();
    }
    {
        std::lock_guard<std::mutex> guard(_resultMutex);
        _results.clear();
    }
}

bool AiChatBridge::Submit(Player* bot, Player* from, std::string const& message)
{
    AiChatConfig const& config = AiChatConfig::instance();

    if (!_running.load() || !bot || !from || message.empty())
        return false;

    // One in flight per bot at a time, and not more often than the cooldown:
    // a hundred bots reacting to one party message would bury a local model.
    auto const now = std::chrono::steady_clock::now();
    auto const seen = _cooldowns.find(bot->GetGUID());

    if (seen != _cooldowns.end() &&
        now - seen->second < std::chrono::milliseconds(config.cooldownMs))
        return false;

    Request request;
    request.bot = bot->GetGUID();
    request.from = from->GetGUID();
    request.prompt = BuildPrompt(bot, from, message);

    {
        std::lock_guard<std::mutex> guard(_requestMutex);

        // Drop rather than queue when saturated. A command that arrives a minute
        // later is worse than one that never arrives.
        if (_requests.size() >= config.maxQueue)
            return false;

        _requests.push_back(std::move(request));
    }

    _cooldowns[bot->GetGUID()] = now;
    _requestCv.notify_one();

    return true;
}

void AiChatBridge::WorkerLoop()
{
    AiChatConfig const& config = AiChatConfig::instance();

    while (_running.load())
    {
        Request request;

        {
            std::unique_lock<std::mutex> lock(_requestMutex);
            _requestCv.wait(lock, [this]() { return !_requests.empty() || !_running.load(); });

            if (!_running.load())
                return;

            request = std::move(_requests.front());
            _requests.pop_front();
        }

        Result result;
        result.bot = request.bot;
        result.from = request.from;
        result.ok = OllamaClient::Ask(config.host, config.port, config.path, config.model,
                                      config.systemPrompt, request.prompt, config.timeoutMs,
                                      result.reply, result.error);

        std::lock_guard<std::mutex> guard(_resultMutex);
        _results.push_back(std::move(result));
    }
}

void AiChatBridge::Update()
{
    if (!_running.load())
        return;

    std::deque<Result> ready;

    {
        std::lock_guard<std::mutex> guard(_resultMutex);
        if (_results.empty())
            return;

        ready.swap(_results);
    }

    for (Result const& result : ready)
        Dispatch(result);

    // Keep the cooldown map from growing with every bot that ever spoke.
    if (_cooldowns.size() > 4096)
        _cooldowns.clear();
}

void AiChatBridge::Dispatch(Result const& result)
{
    AiChatConfig const& config = AiChatConfig::instance();

    if (!result.ok)
    {
        LOG_DEBUG("playerbots", "AiChat: request failed: {}", result.error);
        return;
    }

    // Resolved now rather than held across the request: either may have gone.
    Player* bot = ObjectAccessor::FindPlayer(result.bot);
    Player* from = ObjectAccessor::FindPlayer(result.from);

    if (!bot || !from)
        return;

    PlayerbotAI* botAI = GET_PLAYERBOT_AI(bot);
    if (!botAI)
        return;

    std::string const command = AiChatUtil::NormalizeCommand(result.reply);

    if (command.empty() || command == "none")
        return;

    std::string matched;
    if (!AiChatUtil::IsAllowedCommand(command, config.allowed, matched))
    {
        // Not a refusal to be apologetic about: the model produced something
        // outside the vocabulary, so it is dropped and logged for tuning.
        LOG_DEBUG("playerbots", "AiChat: {} rejected '{}' from {}", bot->GetName(),
                  AiChatUtil::ClampChat(command, 60), from->GetName());
        return;
    }

    LOG_DEBUG("playerbots", "AiChat: {} -> '{}' (for {})", bot->GetName(), command, from->GetName());

    if (config.confirm)
        bot->Whisper(AiChatUtil::ClampChat("(" + command + ")"), LANG_UNIVERSAL, from);

    // Fed in exactly as if the player had whispered the command themselves, so
    // it goes through the module's own parsing and permission checks rather
    // than around them.
    botAI->HandleCommand(CHAT_MSG_WHISPER, command, from);
}
