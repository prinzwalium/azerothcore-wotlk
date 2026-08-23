# Local additions to mod-playerbots

mod-playerbots is fetched at a pinned revision by the `playerbots-src` stage in
`apps/docker/Dockerfile`. Anything in here is layered on top of that checkout
during the image build, so the module can be extended without maintaining a fork
of it: upgrading stays "bump `PLAYERBOTS_REF`".

## Layout

| Path | Applied how |
|---|---|
| `src/` | copied into `modules/mod-playerbots/src`, merging with what is already there |
| `0001-register-bank-gathered.patch` | `git apply` against the checkout |

New files go in `src/` and are picked up by AzerothCore's module glob with no
CMake changes. Only edits to files that already exist upstream belong in a patch.

If a patch stops applying the build **fails at that step**, on purpose: a
registration silently dropped would produce an image that looks fine and has a
strategy no bot can run.

## What is added

A `bank gathered` non-combat strategy: a bot carrying gathered materials that is
standing at a guild vault it may deposit into empties them into the first tab.

* `src/Ai/Base/Value/GatheredMaterials.h` — shared "is this a material we bank"
  test and the config it reads.
* `src/Ai/Base/Trigger/BankGatheredTrigger.{h,cpp}` — in a guild, out of combat,
  has deposit rights, carrying at least `MinItems` stacks, vault in range.
* `src/Ai/Base/Actions/BankGatheredAction.{h,cpp}` — the deposit itself.
* The patch registers those three in `TriggerContext.h`, `ActionContext.h` and
  `StrategyContext.h`, and adds one early return to `ItemUsageValue::Calculate`
  so materials are classified `ITEM_USAGE_KEEP` rather than vendor trash.

That last hunk is the one that matters most. Without it `DestroyItemAction`
treats `ITEM_USAGE_VENDOR` and `ITEM_USAGE_AH` as the first things to drop when
bags fill, so the ore would be sold or destroyed long before the bot passed a
vault.

## Why proximity rather than a trip to the bank

The travel subsystem has no GameObject-type destination. `ChooseTravelTargetAction`
still contains commented-out `SetGOTypeTarget(..., GAMEOBJECT_TYPE_MAILBOX, ...)`
calls, but the helper itself was removed upstream, so there is nothing to reuse.
Adding a `TravelDestination` subclass means coupling to `TravelMgr` (~4,900
lines) which upstream changes often — a large patch with a high chance of
breaking on every bump.

Bots therefore bank opportunistically. If the yield turns out too low, the next
step is a travel destination, and it should probably be a real fork at that point
rather than a patch this size.

## Configuration

| Option | Default | Meaning |
|---|---|---|
| `AiPlayerbot.BankGathered.Enabled` | `false` | master switch |
| `AiPlayerbot.BankGathered.SubClasses` | `6,7,9` | trade goods subclasses to bank |
| `AiPlayerbot.BankGathered.MinItems` | `4` | stacks carried before it is worth banking |

The strategy is registered but not on by default. Switch it on for the bot
population with `AiPlayerbot.RandomBotNonCombatStrategies = "+bank gathered"`, or
for one bot with `nc +bank gathered`.
