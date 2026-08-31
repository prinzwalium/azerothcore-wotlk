/*
 * This file is part of the mod-playerbots module for AzerothCore. See AUTHORS file for Copyright
 * information; released under GNU GPL v2 license, redistribute/modify under version 2 of the License,
 * or (at your option) any later version.
 */

#ifndef PLAYERBOTS_AICHATBRIDGE_H
#define PLAYERBOTS_AICHATBRIDGE_H

#include "ObjectGuid.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

class Player;

// Turns a sentence typed at a bot into one of the bot's own chat commands, via
// a local Ollama instance.
//
// The world thread only ever enqueues and drains; the HTTP call happens on a
// worker thread. Nothing but plain values crosses that boundary -- players are
// referred to by GUID and resolved again at dispatch time, because a bot can
// log out or a player leave while the model is still thinking.
class AiChatBridge
{
public:
    static AiChatBridge& instance();

    void Start();
    void Stop();

    // World thread. Returns true if the message was accepted for translation.
    bool Submit(Player* bot, Player* from, std::string const& message);

    // World thread. Dispatches whatever the workers have finished.
    void Update();

private:
    struct Request
    {
        ObjectGuid bot;
        ObjectGuid from;
        std::string prompt;
    };

    struct Result
    {
        ObjectGuid bot;
        ObjectGuid from;
        std::string reply;
        std::string error;
        bool ok = false;
    };

    void WorkerLoop();
    void Dispatch(Result const& result);

    std::atomic<bool> _running{false};

    std::vector<std::thread> _workers;

    std::mutex _requestMutex;
    std::condition_variable _requestCv;
    std::deque<Request> _requests;

    std::mutex _resultMutex;
    std::deque<Result> _results;

    // World thread only, so it needs no lock.
    std::map<ObjectGuid, std::chrono::steady_clock::time_point> _cooldowns;
};

#define sAiChatBridge AiChatBridge::instance()

#endif
