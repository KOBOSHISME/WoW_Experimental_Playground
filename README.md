# WoW Experimental Playground

A small World of Warcraft Classic addon playground for trying features, challenges, roleplay tools, sound moments, and whatever addon ideas seem worth poking at next.

The point is to keep experiments easy to try, easy to turn off, and easy to remove when they have served their purpose. Some ideas may grow into polished modules. Others can stay as little prototypes.

## What This Is For

- Build playful, useful WoW Classic addon experiments.
- Try challenge modes, roleplay helpers, UI ideas, quality-of-life tools, and social features.
- Keep features modular so unfinished ideas do not get in the way of stable ones.
- Leave enough notes that the next pass through the code is not archaeology.

## Current Shape

The addon has a small core, shared tools, a hidden addon communication layer, and a few feature modules:

- Hide and Seek, an addon-managed challenge mode.
- Pranks, a party-only panel for temporary UI and sound mischief.
- Sound Events, local sound triggers for casts and world events.
- Tool Debug, a grab bag for testing shared tools in-game.

The source is laid out like this:

```text
WoW_Experimental_Playground/
  WoW_Experimental_Playground.toc
  Core.lua
  Utils/
  Tools/
  Comm/
  Features/
```

That shape can change as the playground grows, but new features should still stay easy to find.

## How Code Is Organized

- `Core.lua` owns the addon namespace, saved defaults, module initialization, logging, and feature registry.
- `Utils/` contains pure helpers that do not call WoW APIs.
- `Tools/` contains reusable WoW-facing services such as timers, sounds, player identity, environment snapshots, and UI helpers.
- `Comm/` owns addon communication protocol and transport behavior.
- `Features/` contains player-facing experiments and feature modules.
- `Sounds/Custom/` contains addon-local custom sounds registered by `WEP.Tools.Sound`.

## Communication Diagnostics

Open the default feature panel with:

```text
/wep
```

The panel lists registered features, lets you turn each one on or off, and opens feature UI panels when available.

Recent addon activity is stored in a capped saved log buffer for after-the-fact debugging:

```text
/wep logs
/wep logs 25
/wep logs clear
/wep logs echo on
/wep logs echo off
```

The addon includes a small hidden communication diagnostic feature:

```text
/wep comm status
/wep comm ping
/wep comm debug
```

`/wep comm ping` uses party/raid addon messages when grouped, falling back to the hidden discovery channel otherwise. Other players with the addon respond with a `PONG` after a short randomized delay.

## Hide and Seek

The addon includes an addon-managed Hide and Seek challenge. Open it with:

```text
/wep hide
```

The window lets the host invite players one at a time, set the hiding countdown, seeking time, starting-spot radius, play-area radius, and optional Star reveal uses, start the game, view the roster, watch player states, or leave. Accepted players join the Hide and Seek roster without requiring a WoW party.

During a game, the starter randomly chooses the seeker unless one is selected. The seeker's position when the round starts is captured as the starting spot. The starting-spot radius and play-area radius are measured in visible map-coordinate points on the 0-100 coordinate scale, not yards.

The seeker gets a black countdown screen while hiders hide. When the countdown ends, the blackout is removed and the seeker's map, minimap, unit frames, and action bars are hidden. The starting spot is marked as a user waypoint on supported clients so hiders can see it on the map and minimap; the tracker also shows start-spot distance and play-area status for participants, including the seeker while their map UI is hidden. The map and minimap tint everything outside the play-area radius red and mark the starting spot. If a hider stays outside the play area for 5 seconds, that hider is counted found; if the seeker stays outside, the seeker loses. The seeker tags a hider by targeting them, then must return to the starting spot to mark that hider found. Hiders become safe by reaching the starting spot and staying there for 1 second while the seeker is away. If all hiders become safe, hiders win. If any hider is found, the seeker wins and that hider is preselected as the next seeker. If the seek timer expires first, hiders win. If the host enabled Star reveals, the seeker's tracker includes a Reveal button that briefly places the Star raid target icon on addressable, active hiders. After a game ends, the host can use Start Again in the same Hide and Seek window to reuse the current roster.

## Pranks

Pranks is a small party-only feature for sending temporary effects to friends who also have the addon. Open it with:

```text
/wep pranks
/wep prank
```

The window lists current `party1` through `party4` members. Select one or more party members, choose a bounded duration, optionally add a short custom message, choose whether to include your sender name, then pick from the scrollable prank list. Use All Party to target everyone currently in the party, or None to clear the target selection. Each row has a selector, a short description, a type label, and its own Send button. The footer can still send the selected row, clear effects that you sent, or refresh the party list. The percent field appears for visual pranks, where it controls intensity.

Core prank actions can darken their screen, tint it red/green/purple/white, pulse a panic flash, add tunnel vision, add letterbox bars, show fake raid/error/loot notices, hide selected UI groups, play the selected custom sound, or clear effects that you sent. The sound picker uses the same registered custom `wep_*` sounds used by Sound Events and includes a local Test button. UI-hide pranks include unit frames/health, action bars, minimap, chat, buffs, cast bars, bags, the micro menu, and the quest tracker. Sound-trap actions pick themed sounds automatically: Boom Walk plays Vine Boom while the target moves, Target Sting plays Hello There when they target a party member, Combat Drop plays FBI Open Up when they enter combat, Cast Heckle plays Error when they start casting, and Enemy Sting plays Nani when they target a hostile unit.

Incoming actions auto-apply only when the sender is currently in your party and the target matches your character. Custom prank messages are printed to chat and shown briefly on screen; pranks without a custom message apply quietly. Durations are clamped to 1-900 seconds, percent is clamped to 10-95%, custom messages are capped at 60 characters, and temporary visual/UI effects are owner-tracked so one sender's clear does not remove another sender's prank or restore UI that another feature, such as Hide and Seek, is still hiding. The old `/wep interfere` command still opens Pranks.

## Sound Events

Sound Events plays local custom sounds when built-in triggers happen. Open it with:

```text
/wep sounds
/wep soundevents
```

The panel lists each trigger with an on/off checkbox and a Test button for its sound. The list scrolls now, because the soundboard has grown a bit. Trigger toggles persist in `WEPDB.soundEvents.triggers`.

Current built-in triggers:

- Warrior Charge -> Deja Vu when your warrior or a party warrior casts Charge.
- Dungeon Entry -> Okay Lets Go when you enter a dungeon instance.
- Divine Shield -> Heavenly Music when your paladin or a party paladin casts Divine Shield.
- Mind Control -> Among Us when your priest or a party priest casts Mind Control.
- Feign Death -> Ack when your hunter or a party hunter casts Feign Death.
- You Die -> Auughhh when your character dies.
- Party Death -> Faaah when a party member dies.
- Hard Crowd Control -> Error when you are stunned, feared, or silenced by common Classic control effects.
- Party Join -> Hello There when a new party member joins.
- Party Leader -> Among Us when the party leader changes.
- Falling Damage -> Vine Boom when you take falling damage.
- Rested Area -> Hub Intro when you enter a rested area or inn.
- Level Up -> Anime Wow when you level up.
- Rare Loot -> Rizz when you loot a rare, epic, or better item.
- Underwater -> Under the Water when your breath timer starts after diving underwater.

Dungeon Entry ignores raids and battlegrounds. Dungeon, rested, party roster, and party leader state are primed on reload/login so the addon does not shout at you just for loading in.

## Tool Debug Commands

Reusable tools can be tested from chat with:

```text
/wep tools help
/wep tools list
/wep tools player
/wep tools timer now
/wep tools timer after 2
/wep tools chat normalize General
/wep tools chat getid General
/wep tools sound list
/wep tools sound play ui_select duration=1
/wep tools sound play game:852 channel=sfx
/wep tools sound play wep_alert duration=1
/wep tools sound play wep_vine_boom duration=1
/wep tools sound play custom:wep-alert.wav duration=1
/wep tools sound status
/wep tools overlay blackout 50
/wep tools overlay status
/wep tools overlay hide
/wep tools ui groups
/wep tools ui hide all
/wep tools ui show all
/wep tools ui toggle actionbars
/wep tools ui hide minimap
/wep tools ui show managed
/wep tools ui status
/wep tools dialog sample
/wep tools dialog status
/wep tools dialog hide
/wep tools environment status
/wep tools environment location
/wep tools environment unit target
/wep tools environment units 10
/wep tools request send Playername debug note=hello
/wep tools request respond 12345.1 Playername accepted
/wep tools request status
```

`/wep debug tools ...` is also supported as an alias for `/wep tools ...`.

## Request Tool

`WEP.Tools.Requests` provides a small request/response layer over the hidden communication channel. Future features can register request handlers, send typed requests to another addon user, and handle responses without adding UI.

```lua
WEP.Tools.Requests.RegisterRequestHandler("challenge", function(request)
	-- Feature decides whether to accept, decline, or ignore.
	WEP.Tools.Requests.Respond(request.id, request.sender, "accepted")
end)

WEP.Tools.Requests.RegisterResponseHandler("challenge", function(response)
	-- Feature decides what accepted/declined/result means.
end)

WEP.Tools.Requests.Send("Playername", "challenge", { name = "duel" })
```

## Dialog Tool

`WEP.Tools.Dialog` displays an in-game dialog with one or more options and returns the selected result through a callback.

```lua
WEP.Tools.Dialog.Show({
	title = "Challenge Request",
	message = "How do you want to respond?",
	options = {
		{ text = "Accept", value = "accepted" },
		{ text = "Decline", value = "declined" },
		{ text = "Ask Later", value = "later" },
	},
	onSelect = function(result)
		if result.canceled then
			return
		end

		WEP:Print("Selected:", result.value)
	end,
})
```

The result table includes `id`, `title`, `message`, `canceled`, `reason`, and, when an option was selected, `index`, `text`, and `value`.

## UI Tools

`WEP.Tools.Window`, `WEP.Tools.Form`, and `WEP.Tools.List` provide lightweight reusable UI building blocks for feature panels.

```lua
local window = WEP.Tools.Window.Create({ title = "Feature", width = 420, height = 320 })
local input = WEP.Tools.Form.CreateInput(window.content, { label = "Name" })
local button = WEP.Tools.Form.CreateButton(window.footer, { text = "Apply" })
local list = WEP.Tools.List.Create(window.content, {
	columns = {
		{ key = "name", width = 160 },
		{ key = "state", width = 120 },
	},
})
```

The window helper owns frame chrome and movable panel behavior. The form helper creates labeled text/number inputs and buttons. The list helper renders fixed-height row lists with simple columns and empty-state text.

## Sound Tool

`WEP.Tools.Sound` plays game sound kits and addon-local custom sound files. Custom files should live under `Sounds\Custom` so they are saved with the repo and installed with the addon.

```lua
WEP.Tools.Sound.Play("ui_select")
WEP.Tools.Sound.Play("game:852", { channel = "SFX", duration = 1 })
WEP.Tools.Sound.Play("wep_alert", { duration = 1 })
WEP.Tools.Sound.Play("wep_vine_boom")
WEP.Tools.Sound.Play("custom:wep-alert.wav", { duration = 1 })
WEP.Tools.Sound.PlayCustom("wep-alert.wav")
```

Pranks registers a set of short `wep_*` custom sound IDs for sound traps. Use `/wep tools sound list` to print the current registered names.

Supported options are:

- `channel`: WoW sound channel such as `Master`, `SFX`, `Music`, `Ambience`, or `Dialog`.
- `duration`: seconds before stopping playback, when the client returns a sound handle.
- `fadeOut`: optional fade-out seconds used when stopping a handled sound.
- `volume`: accepted as `0-100` or `0-1`; `0` skips playback, but WoW Classic does not support per-sound volume without changing global sound settings.

## UI Visibility Tool

`WEP.Tools.UIVisibility` controls screenshot-style full UI visibility and managed Blizzard UI groups at runtime. It does not persist hidden state across reloads.

```lua
WEP.Tools.UIVisibility.HideAll()
WEP.Tools.UIVisibility.ShowAll()
WEP.Tools.UIVisibility.ToggleAll()
WEP.Tools.UIVisibility.Hide("actionbars")
WEP.Tools.UIVisibility.Show("actionbars")
WEP.Tools.UIVisibility.Toggle("minimap")
WEP.Tools.UIVisibility.ShowEverythingManaged()
local status = WEP.Tools.UIVisibility.GetStatus()
```

Managed groups are:

```text
actionbars, unitframes, minimap, map, questtracker, chat, bags, micromenu, buffs, casting, mirrorbars
```

## Environment Tool

`WEP.Tools.Environment` provides snapshots of the current zone, map, instance state, PvP state, player flags, and units exposed by the WoW API. Unit discovery is limited to addressable tokens such as target, mouseover, focus, boss units, group units, pets, and visible nameplates.

```lua
local location = WEP.Tools.Environment.GetLocation()
local target = WEP.Tools.Environment.GetUnit("target")
local units = WEP.Tools.Environment.GetUnits()
local snapshot = WEP.Tools.Environment.GetSnapshot()
```

## Installation

To install or update from Git on Windows, run:

```text
Install-WEP-Addon.bat
```

The installer looks for a WoW Classic AddOns folder, installs Git with `winget` if Git is missing, then clones this repository into `WoW_Experimental_Playground`. If the addon folder already exists, local changes in that folder are overwritten so the latest `main` branch is installed.

If your WoW install is in a custom location, pass the AddOns path:

```text
Install-WEP-Addon.bat "C:\Path\World of Warcraft\_classic_era_\Interface\AddOns"
```

Manual install during development still works:

1. Copy the addon folder into your WoW Classic addons directory.
2. Make sure the folder name matches the `.toc` file name.
3. Enable the addon from the in-game AddOns menu.

Typical Classic Era path on Windows:

```text
World of Warcraft\_classic_era_\Interface\AddOns\WoW_Experimental_Playground
```

## Development Notes

- Target WoW Classic first.
- Keep experimental features isolated where practical.
- Avoid relying on other addons unless a feature explicitly integrates with one.
- Hidden addon channels are for coordination, not security. Treat received payloads as untrusted.
- Run `luac51 -p Core.lua Utils\*.lua Tools\*.lua Comm\*.lua Features\*.lua` from this folder for Lua syntax checks.
- Run `luacheck Core.lua Utils\*.lua Tools\*.lua Comm\*.lua Features\*.lua` with WoW globals allowed when linting is available.
- Update this README when features, commands, sounds, install details, or workflow notes change.
