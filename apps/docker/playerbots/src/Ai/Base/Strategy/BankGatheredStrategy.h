/*
 * This file is part of the mod-playerbots module for AzerothCore. See AUTHORS file for Copyright
 * information; released under GNU GPL v2 license, redistribute/modify under version 2 of the License,
 * or (at your option) any later version.
 */

#ifndef PLAYERBOTS_BANKGATHEREDSTRATEGY_H
#define PLAYERBOTS_BANKGATHEREDSTRATEGY_H

#include "Strategy.h"

class PlayerbotAI;

class BankGatheredStrategy : public Strategy
{
public:
    BankGatheredStrategy(PlayerbotAI* botAI) : Strategy(botAI) {}

    void InitTriggers(std::vector<TriggerNode*>& triggers) override;
    std::string const getName() override { return "bank gathered"; }
    uint32 GetType() const override { return STRATEGY_TYPE_NONCOMBAT; }
};

#endif
