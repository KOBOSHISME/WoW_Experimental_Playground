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

The addon includes a small hidden communication diagnostic feature:

```text
/wep comm status
/wep comm ping
/wep comm debug
```

`/wep comm ping` sends a hidden discovery-channel ping. Other players with the addon respond with a `PONG` after a short randomized delay.

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

## Sound Tool

`WEP.Tools.Sound` plays game sound kits and addon-local custom sound files. Custom files should live under `Sounds\Custom` so they are saved with the repo and installed with the addon.

```lua
WEP.Tools.Sound.Play("ui_select")
WEP.Tools.Sound.Play("game:852", { channel = "SFX", duration = 1 })
WEP.Tools.Sound.Play("wep_alert", { duration = 1 })
WEP.Tools.Sound.Play("custom:wep-alert.wav", { duration = 1 })
WEP.Tools.Sound.PlayCustom("wep-alert.wav")
```

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
actionbars, unitframes, minimap, questtracker, chat, bags, micromenu, buffs, casting, mirrorbars
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
