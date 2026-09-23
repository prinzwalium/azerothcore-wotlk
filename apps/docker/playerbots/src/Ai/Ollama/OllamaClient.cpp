/*
 * This file is part of the mod-playerbots module for AzerothCore. See AUTHORS file for Copyright
 * information; released under GNU GPL v2 license, redistribute/modify under version 2 of the License,
 * or (at your option) any later version.
 */

#include "OllamaClient.h"

#include "AiChatUtil.h"

#include <boost/asio.hpp>

#ifndef _WIN32
#include <sys/socket.h>
#include <sys/time.h>
#endif

namespace
{
    using boost::asio::ip::tcp;

    std::string BuildRequestBody(std::string const& model, std::string const& systemPrompt,
                                 std::string const& userPrompt)
    {
        // stream:false gives one JSON object back rather than a token stream,
        // and temperature 0 keeps the mapping from sentence to command stable.
        // num_predict is small on purpose: the answer is one short command, and
        // capping it stops a chatty model from spending seconds explaining.
        std::string body;
        body += "{\"model\":\"";
        body += AiChatUtil::JsonEscape(model);
        body += "\",\"stream\":false,\"options\":{\"temperature\":0,\"num_predict\":24},\"messages\":[";
        body += "{\"role\":\"system\",\"content\":\"";
        body += AiChatUtil::JsonEscape(systemPrompt);
        body += "\"},{\"role\":\"user\",\"content\":\"";
        body += AiChatUtil::JsonEscape(userPrompt);
        body += "\"}]}";
        return body;
    }

    void ApplyTimeout(tcp::socket& socket, uint32_t timeoutMs)
    {
#ifndef _WIN32
        timeval tv{};
        tv.tv_sec = static_cast<time_t>(timeoutMs / 1000);
        tv.tv_usec = static_cast<suseconds_t>((timeoutMs % 1000) * 1000);

        int const fd = static_cast<int>(socket.native_handle());
        ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
#else
        (void)socket;
        (void)timeoutMs;
#endif
    }
}

bool OllamaClient::Ask(std::string const& host, uint16_t port, std::string const& path,
                       std::string const& model, std::string const& systemPrompt,
                       std::string const& userPrompt, uint32_t timeoutMs,
                       std::string& reply, std::string& error)
{
    reply.clear();
    error.clear();

    try
    {
        boost::asio::io_context ioc;

        tcp::resolver resolver(ioc);
        boost::system::error_code ec;

        auto const endpoints = resolver.resolve(host, std::to_string(port), ec);
        if (ec)
        {
            error = "resolve failed: " + ec.message();
            return false;
        }

        tcp::socket socket(ioc);
        boost::asio::connect(socket, endpoints, ec);
        if (ec)
        {
            error = "connect failed: " + ec.message();
            return false;
        }

        ApplyTimeout(socket, timeoutMs);

        std::string const body = BuildRequestBody(model, systemPrompt, userPrompt);

        // HTTP/1.0 so the server answers with a plain body and closes, which
        // means the read below ends at EOF and no chunked framing is involved.
        std::string request;
        request += "POST " + path + " HTTP/1.0\r\n";
        request += "Host: " + host + ":" + std::to_string(port) + "\r\n";
        request += "Content-Type: application/json\r\n";
        request += "Content-Length: " + std::to_string(body.size()) + "\r\n";
        request += "Connection: close\r\n\r\n";
        request += body;

        boost::asio::write(socket, boost::asio::buffer(request), ec);
        if (ec)
        {
            error = "write failed: " + ec.message();
            return false;
        }

        std::string response;
        boost::asio::read(socket, boost::asio::dynamic_buffer(response), ec);

        // Reading to EOF is the expected end; anything else with nothing read is
        // a real failure (a timeout surfaces here as try_again).
        if (ec && ec != boost::asio::error::eof && response.empty())
        {
            error = "read failed: " + ec.message();
            return false;
        }

        socket.close(ec);

        int status = 0;
        std::string payload;
        if (!AiChatUtil::HttpBody(response, status, payload))
        {
            error = "malformed http response";
            return false;
        }

        if (status != 200)
        {
            error = "http status " + std::to_string(status) + ": " + AiChatUtil::ClampChat(payload, 120);
            return false;
        }

        if (!AiChatUtil::ExtractContent(payload, reply))
        {
            error = "no message content: " + AiChatUtil::ClampChat(payload, 120);
            return false;
        }

        return true;
    }
    catch (std::exception const& e)
    {
        error = std::string("exception: ") + e.what();
        return false;
    }
}
