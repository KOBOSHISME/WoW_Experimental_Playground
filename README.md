# WoW Experimental Playground

A World of Warcraft Classic addon playground for experimental features, challenges, roleplay tools, and whatever strange little ideas are worth trying next.

This project is intentionally open-ended. Some features may become polished addon modules, while others may stay as prototypes or one-off experiments.

## Goals

- Build playful and useful WoW Classic addon experiments.
- Try challenge modes, roleplay helpers, UI ideas, quality-of-life tools, and social features.
- Keep experiments modular so unfinished ideas do not block stable ones.
- Document decisions as the addon grows.

## Status

Early scaffold with a v1 hidden addon communication bus.

## Planned Addon Shape

The addon will likely start with a small core and feature folders:

```text
WoW_Experimental_Playground/
  WoW_Experimental_Playground.toc
  Core.lua
  Utils/
  Tools/
  Comm/
  Features/
```

This may change as the project finds its direction.

## Architecture

- `Utils/` contains pure helpers that do not call WoW APIs.
- `Tools/` contains reusable WoW-facing services such as timers, player identity, and chat-channel helpers.
- `Comm/` owns addon communication protocol and transport behavior.
- `Features/` contains player-facing experiments and feature modules.

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

## Party Interference

Party Interference is a small party-only prank feature. Open it with:

```text
/wep interfere
/wep prank
```

The resizable window lists current `party1` through `party4` members. Select a party member, choose a bounded duration, optionally add a short custom message, choose whether to include your sender name, expand an effect group, select an effect, then press Start. The window resizes for expanded groups and scales the whole frame down when needed so text, buttons, and rows stay inside the panel. The percent field appears only for screen darkening, where it controls blackout intensity.

Core interference actions can darken their screen, hide unit frames/health, hide action bars, hide the minimap, hide chat, play the WEP alert sound, or clear effects that you sent. Sound-trap actions pick themed sounds automatically: Boom Walk plays Vine Boom while the target moves, Target Sting plays Hello There when they target a party member, Combat Drop plays FBI Open Up when they enter combat, Cast Heckle plays Error when they start casting, and Enemy Sting plays Nani when they target a hostile unit.

Incoming actions auto-apply only when the sender is currently in your party and the target matches your character. Prank notices are printed to chat and shown briefly on screen. Durations are clamped to 1-900 seconds, percent is clamped to 10-95%, custom messages are capped at 60 characters, and UI hides are owner-tracked so temporary interference does not restore UI that another feature, such as Hide and Seek, is still hiding.

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

Party Interference registers a set of short `wep_*` custom sound IDs for sound traps. Use `/wep tools sound list` to print the current registered names.

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

To install during development:

1. Copy the addon folder into your WoW Classic addons directory.
2. Make sure the folder name matches the `.toc` file name.
3. Enable the addon from the in-game AddOns menu.

Typical Classic Era path on Windows:

```text
World of Warcraft\_classic_era_\Interface\AddOns\WoW_Experimental_Playground
```

## Development Notes

- Target WoW Classic first.
- Keep experimental features isolated where possible.
- Avoid relying on other addons unless a feature explicitly integrates with one.
- Hidden addon channels are for coordination, not security. Treat received payloads as untrusted.
- Run `luac51 -p Core.lua Utils\*.lua Tools\*.lua Comm\*.lua Features\*.lua` for Lua syntax checks.
- Run `luacheck Core.lua Utils\*.lua Tools\*.lua Comm\*.lua Features\*.lua` with WoW globals allowed for linting.
- Update this README as actual features, commands, and install details are added.
