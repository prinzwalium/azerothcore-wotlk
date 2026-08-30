/*
 * This file is part of the mod-playerbots module for AzerothCore. See AUTHORS file for Copyright
 * information; released under GNU GPL v2 license, redistribute/modify under version 2 of the License,
 * or (at your option) any later version.
 */

#include "BankGatheredTrigger.h"

#include "Bag.h"
#include "GatheredMaterials.h"
#include "GuildMgr.h"
#include "Playerbots.h"

bool BankGatheredTrigger::IsActive()
{
    if (!GatheredMaterials::Enabled())
        return false;

    if (!bot->GetGuildId() || bot->IsInCombat() || bot->IsBeingTeleported())
        return false;

    Guild* guild = sGuildMgr->GetGuildById(bot->GetGuildId());
    if (!guild || !guild->MemberHasTabRights(bot->GetGUID(), 0, GUILD_BANK_RIGHT_DEPOSIT_ITEM))
        return false;

    uint32 const minItems = sConfigMgr->GetOption<uint32>("AiPlayerbot.BankGathered.MinItems", 4);
    uint32 found = 0;

    for (uint8 slot = INVENTORY_SLOT_ITEM_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
        if (Item* item = bot->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
            if (GatheredMaterials::IsMaterial(item->GetTemplate()) && ++found >= minItems)
                break;

    if (found < minItems)
    {
        for (uint32 bag = INVENTORY_SLOT_BAG_START; found < minItems && bag < INVENTORY_SLOT_BAG_END; ++bag)
            if (Bag* pBag = (Bag*)bot->GetItemByPos(INVENTORY_SLOT_BAG_0, bag))
                for (uint32 slot = 0; slot < pBag->GetBagSize(); ++slot)
                    if (Item* item = pBag->GetItemByPos(slot))
                        if (GatheredMaterials::IsMaterial(item->GetTemplate()) && ++found >= minItems)
                            break;
    }

    if (found < minItems)
        return false;

    // Only now look for the vault: the scan above is cheap compared to walking
    // the nearby object list, and most of the time the bot is nowhere near one.
    GuidVector gos = *botAI->GetAiObjectContext()->GetValue<GuidVector>("nearest game objects");
    for (GuidVector::iterator i = gos.begin(); i != gos.end(); ++i)
    {
        GameObject* go = botAI->GetGameObject(*i);
        if (go && bot->GetGameObjectIfCanInteractWith(go->GetGUID(), GAMEOBJECT_TYPE_GUILD_BANK))
            return true;
    }

    return false;
}
