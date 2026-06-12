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
