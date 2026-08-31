/*
 * This file is part of the mod-playerbots module for AzerothCore. See AUTHORS file for Copyright
 * information; released under GNU GPL v2 license, redistribute/modify under version 2 of the License,
 * or (at your option) any later version.
 */

#ifndef PLAYERBOTS_OLLAMACLIENT_H
#define PLAYERBOTS_OLLAMACLIENT_H

#include <cstdint>
#include <string>

// A single blocking POST to Ollama's /api/chat, meant to be called from a
// worker thread and never from the world thread.
//
// Hand written rather than using Beast: the request is one fixed shape, and
// this keeps the surface small enough to reason about without a compiler.
namespace OllamaClient
{
    // Returns true and fills `reply` with the assistant's message content.
    // On failure `error` says why, for the log.
    bool Ask(std::string const& host, uint16_t port, std::string const& path,
             std::string const& model, std::string const& systemPrompt, std::string const& userPrompt,
             uint32_t timeoutMs, std::string& reply, std::string& error);
}

#endif
