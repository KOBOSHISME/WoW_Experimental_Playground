# WoW Experimental Playground

A World of Warcraft Classic addon playground for experimental features, challenges, roleplay tools, and whatever strange little ideas are worth trying next.

This project is intentionally open-ended. Some features may become polished addon modules, while others may stay as prototypes or one-off experiments.

## Goals

- Build playful and useful WoW Classic addon experiments.
- Try challenge modes, roleplay helpers, UI ideas, quality-of-life tools, and social features.
- Keep experiments modular so unfinished ideas do not block stable ones.
- Document decisions as the addon grows.

## Status

Early scaffold. No addon files have been implemented yet.

## Planned Addon Shape

The addon will likely start with a small core and feature folders:

```text
WoW_Experimental_Playground/
  WoW_Experimental_Playground.toc
  Core.lua
  Features/
  UI/
```

This may change as the project finds its direction.

## Installation

Once addon files exist:

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
- Update this README as actual features, commands, and install details are added.
