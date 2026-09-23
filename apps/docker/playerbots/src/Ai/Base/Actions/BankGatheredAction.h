/*
 * This file is part of the mod-playerbots module for AzerothCore. See AUTHORS file for Copyright
 * information; released under GNU GPL v2 license, redistribute/modify under version 2 of the License,
 * or (at your option) any later version.
 */

#ifndef PLAYERBOTS_BANKGATHEREDACTION_H
#define PLAYERBOTS_BANKGATHEREDACTION_H

#include "InventoryAction.h"

class Bag;
class GameObject;
class Item;
class PlayerbotAI;

// Deposits the gathered materials the bot is carrying into the first tab of its
// guild bank.
//
// Does not reuse GuildBankAction::MoveFromCharToBank: that is private, and it
// whispers the master once per item, which is right for an explicit "gb"
// command and wrong for something that runs on its own.
class BankGatheredAction : public InventoryAction
{
public:
    BankGatheredAction(PlayerbotAI* botAI) : InventoryAction(botAI, "bank gathered") {}

    bool Execute(Event event) override;

private:
    bool Deposit(uint8 bag, uint8 slot);
};

#endif
