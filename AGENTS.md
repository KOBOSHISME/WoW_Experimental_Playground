# Agent Instructions

This repository contains a World of Warcraft Classic addon playground for experimental features, challenges, roleplay tools, and other addon ideas.

## Project Goals

- Keep the addon easy to iterate on.
- Prefer small, focused features that can be enabled, disabled, or removed independently.
- Preserve the spirit of a playground: experiments are welcome, but they should still be understandable to the next person who opens the repo.
- Avoid adding heavy frameworks unless the project clearly needs them.

## Coding Guidelines

- Use Lua patterns that work in WoW Classic's addon environment.
- Keep global variables to a minimum. Prefer a single addon namespace table when implementation begins.
- Name files and modules after the feature they contain.
- Keep feature code isolated where practical, especially for experimental mechanics.
- Add short comments only when they explain behavior that is not obvious from the code.

## Addon Compatibility

- Target WoW Classic unless a feature explicitly says otherwise.
- Avoid APIs that are unavailable in Classic clients.
- When using UI code, account for combat lockdown and protected frames.
- Do not assume third-party addons are installed.

## Repository Hygiene

- Do not commit local game client files, generated archives, logs, or editor state.
- Keep README instructions updated when the install path, addon folder name, or development workflow changes.
- If tests, linting, packaging, or release scripts are added later, document the commands here.

## Suggested Future Layout

```text
WoW_Experimental_Playground/
  WoW_Experimental_Playground.toc
  Core.lua
  Features/
    Challenges/
    Roleplay/
    Experiments/
  UI/
  README.md
```

This layout is only a starting point. Follow the shape of the addon as it grows.
