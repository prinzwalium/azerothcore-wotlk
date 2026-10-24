# ACGMPanel — GM Admin Panel addon

A WotLK 3.3.5 client addon that gives GMs an in-game GUI for administering the
server: quick-action buttons, a live command console, playerbots management,
and the ticket queue. It requires **no server-side changes** — it talks to the
worldserver through AzerothCore's built-in addon command channel.

## How it works

The core ships `AddonChannelCommandHandler` (`src/server/game/Chat/Chat.cpp`),
which accepts addon-whispered frames shaped:

```
AzerothCore\t<opcode><4-char counter><command text>
```

The addon sends these with the client's `SendAddonMessage("AzerothCore", ...)`,
and the server replies with structured frames (`a` ack, `o` ok, `f` failed,
`m` output line) that the addon turns into console lines. Because the handler
runs every command through the normal command parser, **RBAC permissions apply
exactly as if the command were typed** — a non-GM account simply gets
"command not found" style replies and every button fails harmlessly.

Requirements:

* `AddonChannel = 1` in `worldserver.conf` (the default).
* An account with GM permissions for the buttons to actually do anything.

## Installation

Copy `ACGMPanel` into the client's `Interface/AddOns` directory:

```
<client>/Interface/AddOns/ACGMPanel/...
```

Restart the client (or log in), then open the panel with `/acgm` or `/gmpanel`,
or the minimap button.

## Tabs

| Tab | Contents |
|---|---|
| Quick | Fly/god/visibility toggles, speed, gear repair, cooldown clear, save, GPS, cheat status, max skill, free-form command box, `.reload config`, `.server info` |
| Console | Scrolling output of everything the server sends back, plus a command input — the general-purpose console |
| Playerbots | mod-playerbots admin: `.playerbots bot list/add/remove/init`, account linking, debug, plus a free-form box for any other `bots`/`playerbots` command |
| Tickets | `.ticket list/onlinelist/escalatedlist/closedlist/togglesystem`, view/close/complete/delete by id, and response text via `.ticket response appendln` |

All command names were taken from this repository's command scripts
(`src/server/scripts/Commands/`) and the mod-playerbots wiki, so the buttons
match the server's actual command tree.

## Notes

* The panel does not gate anything itself: the server enforces permissions per
  command, which is why there is no "is GM" check in the addon.
* Output of every command from every tab lands in the Console tab, including
  errors, so nothing fails silently.
* The 3.3.5 client has no `C_Timer`; the login-time channel probe uses a
  one-shot OnUpdate frame instead.
