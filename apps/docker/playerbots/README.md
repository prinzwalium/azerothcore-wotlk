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

## The pin

`PLAYERBOTS_REF` is a commit sha, not `master`. It lives in one place, the
`PLAYERBOTS_REF` variable in `docker-bake.hcl`. Everything that consumes the
module reads it from there via `apps/docker/scripts/bake-default.sh` —
`docker-build.yml`, which publishes the images, and `core-build-playerbots.yml`,
which compiles the core against the module on every PR — and the `ARG` in the
Dockerfile matches it for a bare `docker build`.

Currently `b6696bd` (2026-09-11).

Tracking `master` did not work. Upstream moves quickly and twice broke the build
on a change unrelated to anything here:

```
error: patch failed: src/Ai/Base/Value/ItemUsageValue.cpp:30
error: src/Ai/Base/Value/ItemUsageValue.cpp: patch does not apply
```

first when `botAI->HasActivePlayerMaster()` became
`IsRealPlayer(botAI->GetMaster())` three lines below the insertion point, then
again shortly after. A branch also means a new module release can add config
options mid-deployment, which a running server logs as `Missing property
AiPlayerbot.*` on its next restart.

Upstream has since gone further and made the module require a newer core than
this fork carries — its `src/Db/PlayerbotsDatabase.h` includes the core header
`ModuleDatabasePool.h`, which does not exist here:

```
fatal error: 'ModuleDatabasePool.h' file not found
```

So the pin is currently load-bearing, not just tidiness: moving it forward means
bringing the core up to date too.

The cost is that upstream fixes no longer arrive on their own.

## Updating the module

1. Pick the new revision and check the patch against it before changing
   anything:

   ```bash
   git clone https://github.com/mod-playerbots/mod-playerbots.git
   cd mod-playerbots && git checkout <new-sha>
   cp -r /path/to/apps/docker/playerbots/src/. src/
   git apply --check /path/to/apps/docker/playerbots/0001-register-bank-gathered.patch
   ```

2. If that fails, re-apply the four edits listed under *What is added* by hand
   and regenerate:

   ```bash
   git diff > /path/to/apps/docker/playerbots/0001-register-bank-gathered.patch
   ```

3. Bump `PLAYERBOTS_REF` in `docker-bake.hcl` and the `ARG` default in
   `apps/docker/Dockerfile`, and update the sha named above.

To build against `master` once without moving the pin, run the workflow manually
and put `master` in the *mod-playerbots branch, tag or commit* field — left
blank it uses the pin.

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
