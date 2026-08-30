/*
 * This file is part of the mod-playerbots module for AzerothCore. See AUTHORS file for Copyright
 * information; released under GNU GPL v2 license, redistribute/modify under version 2 of the License,
 * or (at your option) any later version.
 */

#include "BankGatheredAction.h"

#include "Bag.h"
#include "GatheredMaterials.h"
#include "GuildMgr.h"
#include "Playerbots.h"

bool BankGatheredAction::Execute(Event /*event*/)
{
    if (!GatheredMaterials::Enabled() || !bot->GetGuildId())
        return false;

    Guild* guild = sGuildMgr->GetGuildById(bot->GetGuildId());
    if (!guild || !guild->MemberHasTabRights(bot->GetGUID(), 0, GUILD_BANK_RIGHT_DEPOSIT_ITEM))
        return false;

    // The trigger already established that a usable vault is in range, but the
    // bot may have moved since, so this is checked again rather than assumed.
    GameObject* bank = nullptr;
    GuidVector gos = *botAI->GetAiObjectContext()->GetValue<GuidVector>("nearest game objects");
    for (GuidVector::iterator i = gos.begin(); i != gos.end(); ++i)
    {
        GameObject* go = botAI->GetGameObject(*i);
        if (go && bot->GetGameObjectIfCanInteractWith(go->GetGUID(), GAMEOBJECT_TYPE_GUILD_BANK))
        {
            bank = go;
            break;
        }
    }

    if (!bank)
        return false;

    // Collect positions rather than Item pointers, and re-resolve each one just
    // before depositing it: SwapItemsWithInventory moves items and can merge
    // stacks, so a pointer taken before the first deposit may not survive it.
    std::vector<std::pair<uint8, uint8>> materials;

    for (uint8 slot = INVENTORY_SLOT_ITEM_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
        if (Item* item = bot->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
            if (GatheredMaterials::IsMaterial(item->GetTemplate()))
                materials.push_back({INVENTORY_SLOT_BAG_0, slot});

    for (uint32 bag = INVENTORY_SLOT_BAG_START; bag < INVENTORY_SLOT_BAG_END; ++bag)
        if (Bag* pBag = (Bag*)bot->GetItemByPos(INVENTORY_SLOT_BAG_0, bag))
            for (uint32 slot = 0; slot < pBag->GetBagSize(); ++slot)
                if (Item* item = pBag->GetItemByPos(slot))
                    if (GatheredMaterials::IsMaterial(item->GetTemplate()))
                        materials.push_back({static_cast<uint8>(bag), static_cast<uint8>(slot)});

    if (materials.empty())
        return false;

    // A full tab is the common failure once a realm of bots has been running a
    // while, so stop at the first refusal rather than retrying for every stack.
    uint32 deposited = 0;
    for (auto const& [bag, slot] : materials)
    {
        if (!Deposit(bag, slot))
            break;

        ++deposited;
    }

    if (!deposited)
        return false;

    LOG_DEBUG("playerbots", "Bot {} deposited {} stack(s) of gathered materials into guild {}",
              bot->GetName(), deposited, bot->GetGuildId());

    return true;
}

bool BankGatheredAction::Deposit(uint8 bag, uint8 slot)
{
    Guild* guild = sGuildMgr->GetGuildById(bot->GetGuildId());
    if (!guild)
        return false;

    Item* item = bot->GetItemByPos(bag, slot);

    // An earlier deposit may have merged this stack away, which is a success
    // for our purposes, not a reason to stop.
    if (!item)
        return true;

    if (!GatheredMaterials::IsMaterial(item->GetTemplate()))
        return true;

    uint32 const countBefore = item->GetCount();

    // 255 as the bank slot means "first free slot in the tab"; the guild code
    // reports a full tab by leaving the item where it was rather than failing,
    // so success is judged by the stack actually shrinking or going away.
    guild->SwapItemsWithInventory(bot, false, 0, 255, bag, slot, 0);

    Item* still = bot->GetItemByPos(bag, slot);

    return !still || still->GetCount() < countBefore;
}
