/*
 * This file is part of the mod-playerbots module for AzerothCore. See AUTHORS file for Copyright
 * information; released under GNU GPL v2 license, redistribute/modify under version 2 of the License,
 * or (at your option) any later version.
 */

#ifndef PLAYERBOTS_AICHATUTIL_H
#define PLAYERBOTS_AICHATUTIL_H

#include <cstdint>
#include <cstdlib>
#include <string>
#include <vector>

// Pure helpers for the Ollama bridge: no AzerothCore types, so they can be
// tested on their own. Everything that decides whether a model's output is
// allowed to reach a bot lives here.
namespace AiChatUtil
{
    inline std::string JsonEscape(std::string const& in)
    {
        std::string out;
        out.reserve(in.size() + 16);

        for (unsigned char c : in)
        {
            switch (c)
            {
                case '"':  out += "\\\""; break;
                case '\\': out += "\\\\"; break;
                case '\n': out += "\\n";  break;
                case '\r': out += "\\r";  break;
                case '\t': out += "\\t";  break;
                case '\b': out += "\\b";  break;
                case '\f': out += "\\f";  break;
                default:
                    if (c < 0x20)
                    {
                        static char const* hex = "0123456789abcdef";
                        out += "\\u00";
                        out += hex[(c >> 4) & 0xF];
                        out += hex[c & 0xF];
                    }
                    else
                        out += static_cast<char>(c);
                    break;
            }
        }

        return out;
    }

    // Read a JSON string literal starting at the opening quote, honouring the
    // escapes JsonEscape produces. Returns false if the literal is unterminated.
    inline bool ReadJsonString(std::string const& in, std::size_t quote, std::string& out)
    {
        if (quote >= in.size() || in[quote] != '"')
            return false;

        out.clear();

        for (std::size_t i = quote + 1; i < in.size(); ++i)
        {
            char const c = in[i];

            if (c == '"')
                return true;

            if (c != '\\')
            {
                out += c;
                continue;
            }

            if (++i >= in.size())
                return false;

            switch (in[i])
            {
                case '"':  out += '"';  break;
                case '\\': out += '\\'; break;
                case '/':  out += '/';  break;
                case 'n':  out += '\n'; break;
                case 'r':  out += '\r'; break;
                case 't':  out += '\t'; break;
                case 'b':  out += '\b'; break;
                case 'f':  out += '\f'; break;
                case 'u':
                {
                    // Only the BMP escapes a model realistically emits, and only
                    // as far as needed to not corrupt the rest of the string.
                    if (i + 4 >= in.size())
                        return false;

                    uint32_t code = 0;
                    for (int k = 1; k <= 4; ++k)
                    {
                        char const h = in[i + k];
                        code <<= 4;
                        if (h >= '0' && h <= '9')      code |= uint32_t(h - '0');
                        else if (h >= 'a' && h <= 'f') code |= uint32_t(h - 'a' + 10);
                        else if (h >= 'A' && h <= 'F') code |= uint32_t(h - 'A' + 10);
                        else return false;
                    }
                    i += 4;

                    if (code < 0x80)
                        out += static_cast<char>(code);
                    else if (code < 0x800)
                    {
                        out += static_cast<char>(0xC0 | (code >> 6));
                        out += static_cast<char>(0x80 | (code & 0x3F));
                    }
                    else
                    {
                        out += static_cast<char>(0xE0 | (code >> 12));
                        out += static_cast<char>(0x80 | ((code >> 6) & 0x3F));
                        out += static_cast<char>(0x80 | (code & 0x3F));
                    }
                    break;
                }
                default:
                    return false;
            }
        }

        return false;
    }

    // Pull message.content out of an Ollama /api/chat reply. Anchored on
    // "message" so that a "content" appearing elsewhere cannot be picked up.
    inline bool ExtractContent(std::string const& body, std::string& out)
    {
        std::size_t const message = body.find("\"message\"");
        std::size_t const from = message == std::string::npos ? 0 : message;
        std::size_t const key = body.find("\"content\"", from);

        if (key == std::string::npos)
            return false;

        std::size_t colon = body.find(':', key + 9);
        if (colon == std::string::npos)
            return false;

        ++colon;
        while (colon < body.size() && (body[colon] == ' ' || body[colon] == '\t' ||
                                       body[colon] == '\n' || body[colon] == '\r'))
            ++colon;

        return ReadJsonString(body, colon, out);
    }

    inline std::string Trim(std::string const& in)
    {
        std::size_t b = 0;
        std::size_t e = in.size();

        while (b < e && (in[b] == ' ' || in[b] == '\t' || in[b] == '\n' || in[b] == '\r'))
            ++b;
        while (e > b && (in[e - 1] == ' ' || in[e - 1] == '\t' || in[e - 1] == '\n' || in[e - 1] == '\r'))
            --e;

        return in.substr(b, e - b);
    }

    inline std::vector<std::string> SplitList(std::string const& in, char sep = ',')
    {
        std::vector<std::string> out;
        std::size_t start = 0;

        while (true)
        {
            std::size_t const at = in.find(sep, start);
            std::string const piece = Trim(in.substr(start, at == std::string::npos ? std::string::npos : at - start));

            if (!piece.empty())
                out.push_back(piece);

            if (at == std::string::npos)
                break;

            start = at + 1;
        }

        return out;
    }

    inline bool ListContains(std::vector<std::string> const& list, std::string const& value)
    {
        for (std::string const& entry : list)
            if (entry == value)
                return true;

        return false;
    }

    // Squeeze a model's answer into something that could plausibly be a bot
    // command: lowercased, unwrapped from quotes or code fences, whitespace
    // collapsed, trailing punctuation dropped. Only the first line is kept --
    // models like to add an explanation underneath.
    inline std::string NormalizeCommand(std::string const& raw)
    {
        std::string s = raw;

        std::size_t const nl = s.find('\n');
        if (nl != std::string::npos)
            s = s.substr(0, nl);

        s = Trim(s);

        // Strip wrapping quotes, backticks and code fences.
        while (s.size() >= 2)
        {
            char const f = s.front();
            char const b = s.back();

            if ((f == '"' && b == '"') || (f == '\'' && b == '\'') || (f == '`' && b == '`'))
                s = Trim(s.substr(1, s.size() - 2));
            else
                break;
        }

        while (!s.empty() && (s.back() == '.' || s.back() == '!' || s.back() == '?' || s.back() == ','))
            s.pop_back();

        std::string out;
        out.reserve(s.size());
        bool space = false;

        for (char c : s)
        {
            if (c == ' ' || c == '\t')
            {
                space = !out.empty();
                continue;
            }

            if (space)
            {
                out += ' ';
                space = false;
            }

            if (c >= 'A' && c <= 'Z')
                c = static_cast<char>(c - 'A' + 'a');

            out += c;
        }

        return out;
    }

    // A command is acceptable when its leading words exactly match an allowed
    // entry and whatever follows is plain. Longest match wins so that
    // "tank attack" is not mistaken for "attack".
    //
    // This is the whole safety story: the model can emit anything, and anything
    // that is not on the list is dropped rather than handed to a bot.
    inline bool IsAllowedCommand(std::string const& command, std::vector<std::string> const& allowed,
                                 std::string& matched)
    {
        if (command.empty() || command.size() > 64)
            return false;

        for (char const c : command)
        {
            bool const ok = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
                            c == ' ' || c == '+' || c == '-' || c == '_';
            if (!ok)
                return false;
        }

        matched.clear();

        for (std::string const& entry : allowed)
        {
            if (entry.empty() || entry.size() > command.size())
                continue;

            if (command.compare(0, entry.size(), entry) != 0)
                continue;

            // Must end at a word boundary: "co" must not match "collect".
            if (command.size() > entry.size() && command[entry.size()] != ' ')
                continue;

            if (entry.size() > matched.size())
                matched = entry;
        }

        return !matched.empty();
    }

    // strncasecmp lives in <strings.h>, which is not portable enough to lean on
    // for one header comparison.
    inline bool StartsWithNoCase(char const* haystack, std::size_t available, char const* needle)
    {
        for (std::size_t i = 0; needle[i]; ++i)
        {
            if (i >= available)
                return false;

            char a = haystack[i];
            char const b = needle[i];

            if (a >= 'A' && a <= 'Z')
                a = static_cast<char>(a - 'A' + 'a');

            if (a != b)
                return false;
        }

        return true;
    }

    // Split an HTTP response into status code and body, de-chunking if the
    // server used Transfer-Encoding: chunked. The request asks for HTTP/1.0 so
    // this should not normally be needed, but a proxy in between may upgrade it.
    inline bool HttpBody(std::string const& response, int& status, std::string& body)
    {
        status = 0;
        body.clear();

        if (response.compare(0, 5, "HTTP/") != 0)
            return false;

        std::size_t const sp = response.find(' ');
        if (sp == std::string::npos || sp + 4 > response.size())
            return false;

        status = std::atoi(response.substr(sp + 1, 3).c_str());

        std::size_t const split = response.find("\r\n\r\n");
        if (split == std::string::npos)
            return false;

        std::string const headers = response.substr(0, split);
        body = response.substr(split + 4);

        bool chunked = false;
        for (std::size_t i = 0; i + 26 <= headers.size(); ++i)
        {
            // Header names are case insensitive; only this one matters here.
            if (StartsWithNoCase(headers.c_str() + i, headers.size() - i, "transfer-encoding:"))
            {
                std::size_t const eol = headers.find("\r\n", i);
                std::string const value = headers.substr(i, eol == std::string::npos ? std::string::npos : eol - i);
                if (value.find("chunked") != std::string::npos || value.find("CHUNKED") != std::string::npos)
                    chunked = true;
                break;
            }
        }

        if (!chunked)
            return true;

        std::string decoded;
        std::size_t at = 0;

        while (at < body.size())
        {
            std::size_t const eol = body.find("\r\n", at);
            if (eol == std::string::npos)
                break;

            std::size_t const size = static_cast<std::size_t>(strtoul(body.substr(at, eol - at).c_str(), nullptr, 16));
            if (!size)
                break;

            std::size_t const start = eol + 2;
            if (start + size > body.size())
                break;

            decoded.append(body, start, size);
            at = start + size + 2;
        }

        body = decoded;
        return true;
    }

    // WoW refuses chat lines longer than this, and a model does not know that.
    inline std::string ClampChat(std::string const& in, std::size_t limit = 250)
    {
        std::string out;
        out.reserve(in.size());

        for (char const c : in)
            out += (c == '\n' || c == '\r' || c == '\t') ? ' ' : c;

        out = Trim(out);

        if (out.size() <= limit)
            return out;

        // Do not cut inside a UTF-8 sequence.
        std::size_t cut = limit;
        while (cut > 0 && (static_cast<unsigned char>(out[cut]) & 0xC0) == 0x80)
            --cut;

        return out.substr(0, cut);
    }
}

#endif
