# Agent Instructions

This repository contains a World of Warcraft Classic addon playground for experimental features, challenges, roleplay tools, and other addon ideas.

## Project Goals

- Keep the addon easy to iterate on.
- Prefer small, focused features that can be enabled, disabled, or removed independently.
- Preserve the spirit of a playground: experiments are welcome, but they should still be understandable to the next person who opens the repo.
- Avoid adding heavy frameworks unless the project clearly needs them.

## Behavioral Guidelines

These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### Think Before Coding

Do not assume or hide confusion. Surface tradeoffs.

Before implementing:

- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them instead of picking silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop, name what is confusing, and ask.

### Simplicity First

Write the minimum code that solves the problem. Do not add speculative work.

- No features beyond what was asked.
- No abstractions for single-use code.
- No flexibility or configurability that was not requested.
- No error handling for impossible scenarios.
- If 200 lines could be 50, rewrite it.

Ask whether a senior engineer would call the change overcomplicated. If yes, simplify.

### Surgical Changes

Touch only what is necessary. Clean up only your own mess.

When editing existing code:

- Do not improve adjacent code, comments, or formatting unless required.
- Do not refactor things that are not broken.
- Match existing style, even if you would do it differently.
- If you notice unrelated dead code, mention it instead of deleting it.

When your changes create orphans:

- Remove imports, variables, or functions that your changes made unused.
- Do not remove pre-existing dead code unless asked.

Every changed line should trace directly to the user's request.

### Goal-Driven Execution

Define success criteria and loop until verified.

Transform tasks into verifiable goals:

- "Add validation" means writing tests for invalid inputs, then making them pass.
- "Fix the bug" means writing a test that reproduces it, then making it pass.
- "Refactor X" means ensuring tests pass before and after.

For multi-step tasks, state a brief plan:

```text
1. [Step] -> verify: [check]
2. [Step] -> verify: [check]
3. [Step] -> verify: [check]
```

These guidelines are working when diffs contain fewer unnecessary changes, rewrites due to overcomplication are rarer, and clarifying questions happen before implementation mistakes.

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
