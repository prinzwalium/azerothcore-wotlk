/*
 * This file is part of the mod-playerbots module for AzerothCore. See AUTHORS file for Copyright
 * information; released under GNU GPL v2 license, redistribute/modify under version 2 of the License,
 * or (at your option) any later version.
 */

#ifndef PLAYERBOTS_BANKGATHEREDTRIGGER_H
#define PLAYERBOTS_BANKGATHEREDTRIGGER_H

#include "Trigger.h"

class PlayerbotAI;

// Fires when the bot is standing at a guild vault it may deposit into and is
// carrying enough gathered material to be worth banking.
//
// Deliberately proximity based rather than sending the bot to a vault: the
// travel subsystem has no GameObject-type destination (the calls in
// ChooseTravelTargetAction are commented out because the helper was removed),
// so bots bank when their wandering brings them past a vault.
class BankGatheredTrigger : public Trigger
{
public:
    BankGatheredTrigger(PlayerbotAI* botAI) : Trigger(botAI, "bank gathered", 5) {}

    bool IsActive() override;
};

#endif
