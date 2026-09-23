/*
 * This file is part of the mod-playerbots module for AzerothCore. See AUTHORS file for Copyright
 * information; released under GNU GPL v2 license, redistribute/modify under version 2 of the License,
 * or (at your option) any later version.
 */

#ifndef PLAYERBOTS_GATHEREDMATERIALS_H
#define PLAYERBOTS_GATHEREDMATERIALS_H

#include "Config.h"
#include "ItemTemplate.h"

// Shared between the "bank gathered" trigger/action and ItemUsageValue, which
// has to agree with them: an item the bot is about to bank must not first be
// classified as vendor trash and sold or destroyed.
namespace GatheredMaterials
{
    inline bool Enabled()
    {
        return sConfigMgr->GetOption<bool>("AiPlayerbot.BankGathered.Enabled", false);
    }

    // Subclasses of ITEM_CLASS_TRADE_GOODS to bank, as a comma separated list.
    // The default is what the gathering professions actually produce: leather
    // and hides (6), ore and stone (7), herbs (9). Cloth is deliberately absent
    // -- it drops from humanoids rather than being gathered, and on a realm full
    // of bots it would swamp the bank.
    inline std::string const& SubClasses()
    {
        static std::string const value =
            sConfigMgr->GetOption<std::string>("AiPlayerbot.BankGathered.SubClasses", "6,7,9");
        return value;
    }

    inline bool IsMaterial(ItemTemplate const* proto)
    {
        if (!proto || proto->Class != ITEM_CLASS_TRADE_GOODS)
            return false;

        // Anything soulbound cannot reach a guild bank anyway.
        if (proto->Bonding == BIND_WHEN_PICKED_UP || proto->Bonding == BIND_QUEST_ITEM)
            return false;

        std::string const& subClasses = SubClasses();
        std::string const needle = std::to_string(proto->SubClass);

        // Match on whole comma separated fields so that "1" never matches "10".
        for (std::size_t pos = 0; (pos = subClasses.find(needle, pos)) != std::string::npos; pos += needle.size())
        {
            bool const atStart = pos == 0 || subClasses[pos - 1] == ',';
            std::size_t const end = pos + needle.size();
            bool const atEnd = end == subClasses.size() || subClasses[end] == ',';

            if (atStart && atEnd)
                return true;
        }

        return false;
    }
}

#endif
