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
| `0002-register-ai-chat.patch` | likewise |

Every `*.patch` in this directory is applied, in name order.

New files go in `src/` and are picked up by AzerothCore's module glob with no
CMake changes. Only edits to files that already exist upstream belong in a patch.

If a patch stops applying the build **fails at that step**, on purpose: a
registration silently dropped would produce an image that looks fine and has a
strategy no bot can run.

## When the patch stops applying

`PLAYERBOTS_REF` defaults to `master`, which the publish workflow resolves to
whatever that branch points at *today*. So an upstream change near one of the
four anchors breaks the build, with the failing hunk named in the log:

```
error: patch failed: src/Ai/Base/Value/ItemUsageValue.cpp:30
error: src/Ai/Base/Value/ItemUsageValue.cpp: patch does not apply
```

That has already happened once, when upstream replaced
`botAI->HasActivePlayerMaster()` with `IsRealPlayer(botAI->GetMaster())` three
lines below the insertion point. To regenerate:

```bash
git clone --depth 1 https://github.com/mod-playerbots/mod-playerbots.git
cd mod-playerbots
# re-apply the four edits listed below, then:
git diff > /path/to/apps/docker/playerbots/0001-register-bank-gathered.patch
```

The patch currently applies against `5397110`. If these breakages get annoying,
pin `PLAYERBOTS_REF` in `docker-bake.hcl` to a known-good sha: builds then stop
drifting, and updating the module becomes a deliberate act that regenerates the
patch at the same time. The cost is no longer picking up upstream fixes on their
own.

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

# Plain language to bot commands (Ollama)

`src/Ai/Ollama/` translates what a player types at a bot into one of the bot's
own chat commands, using an Ollama server you point it at — nothing here runs
one. "wait here while I tame this wolf" becomes `stay`; "ok come on" becomes
`follow`.

It is a **translator, not a chatbot**. The model is asked for one command and
nothing else, and its answer is checked against an allow list before it reaches
a bot. Anything outside that list is dropped and logged. A misread sentence is
therefore a no-op rather than a surprise action, which is what makes a small
local model good enough for this: the task is classification, and the validator
is the safety net rather than the model's good behaviour.

## How it hangs together

| File | Role |
|---|---|
| `AiChatUtil.h` | pure helpers: JSON escape/extract, HTTP body, command normalisation, the allow-list check. No AzerothCore types, so it can be tested on its own |
| `AiChatConfig.{h,cpp}` | settings, read once per config load rather than per chat line |
| `OllamaClient.{h,cpp}` | one blocking POST to `/api/chat`, hand written over Asio |
| `AiChatBridge.{h,cpp}` | request queue, worker threads, and the world-tick drain that dispatches |
| `AiChatScript.cpp` | the chat hooks and the world script, registered by `0002-register-ai-chat.patch` |

The world thread never makes the HTTP call. A chat hook enqueues a request and
returns immediately; a worker thread talks to Ollama; `WorldScript::OnUpdate`
drains finished answers and dispatches them. Nothing but plain values crosses
that boundary — players are referred to by `ObjectGuid` and resolved again at
dispatch, because a bot can log out while the model is still thinking.

Commands are handed to `PlayerbotAI::HandleCommand` exactly as if the player had
whispered them, so they go through the module's own parsing and permission
checks rather than around them.

## Configuration

| Option | Default | Meaning |
|---|---|---|
| `AiPlayerbot.Ai.Enabled` | `false` | master switch |
| `AiPlayerbot.Ai.Host` / `.Port` / `.Path` | `ollama` / `11434` / `/api/chat` | where Ollama is; the deploy compose overrides Host with `AI_HOST`, defaulting to `host.docker.internal` |
| `AiPlayerbot.Ai.Model` | `llama3.1:8b` | model tag to ask for |
| `AiPlayerbot.Ai.CommandScopes` | `whisper,party` | chat that gets translated (`whisper`, `party`, `guild`, `say`) |
| `AiPlayerbot.Ai.CommandFrom` | `master` | `master` or `group` — who may drive a bot |
| `AiPlayerbot.Ai.Commands` | see below | the allow list the model is held to |
| `AiPlayerbot.Ai.TimeoutMs` | `8000` | give up on a reply after this long |
| `AiPlayerbot.Ai.Workers` | `2` | concurrent requests (clamped to 1-8) |
| `AiPlayerbot.Ai.MaxQueue` | `32` | requests dropped rather than queued past this |
| `AiPlayerbot.Ai.CooldownMs` | `3000` | minimum gap between translations per bot |
| `AiPlayerbot.Ai.Confirm` | `true` | whisper back the command that was understood |
| `AiPlayerbot.Ai.SystemPrompt` | see source | `{COMMANDS}` is replaced with the allow list |

The default allow list is deliberately narrow:

```
follow, stay, flee, runaway, grind, attack, pull, rti, formation, summon,
repair, buff, home, max dps, tank attack, wait for attack, focus heal targets,
co, nc
```

`destroy`, `sell`, `buy`, `trade`, `mail`, `leave` and everything under `guild`
are **not** on it, and should not be added lightly: a model misreading "don't
sell that" must not be able to sell it. `co` and `nc` are included because they
carry strategy toggles (`co +passive`, `nc +bank gathered`), which is what makes
the vocabulary useful rather than just movement.

## What it does not do

* **No conditionals.** "wait until I've tamed this" produces `stay`; nothing
  resumes following on its own. Supporting "until X" needs a deferred trigger
  layer that does not exist here.
* **No chat flavour.** This only produces commands. Bots still speak from the
  `ai_playerbot_texts` table.
* Literal commands are ignored rather than translated, so typing `stay` is not
  dispatched twice.
