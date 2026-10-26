# AGENTS.md

This repository is a personal fork of a Simply Love theme for ITGmania/StepMania.

## Purpose
Use this file as the default working guide for future agent sessions in this repo.

## Project Type
- Theme project for ITGmania (Lua + theme assets + metrics).
- Root-level theme assets and behavior are loaded by the engine directly from folder conventions.

## Layout At A Glance
- `ThemeInfo.ini`: Theme metadata (`DisplayName`, `Author`, `Version`).
- `metrics.ini`: Core screen flow, metrics, and many behavioral bindings.
- `Scripts/`: Shared Lua logic and global initialization (`SL_Init.lua`, preferences, helpers, branching helpers, parsers).
- `BGAnimations/`: Screen-specific Lua actors, underlays/overlays, and screen composition.
- `Graphics/`: Visual assets, many actor Lua files, and `.redir` indirection.
- `Fonts/`, `Sounds/`, `Languages/`: Theme resources.
- `Modules/`: Optional module injection system (screen-keyed actor tables).
- `Other/Documentation/`: Upstream docs and user-facing guides.

## Theme Conventions
- Keep logic in `Scripts/` when shared across screens.
- Keep screen behavior in `BGAnimations/Screen*` when screen-specific.
- Prefer existing redirect/asset patterns (`*.redir`) instead of inventing new loading patterns.
- Preserve naming conventions and existing screen structure to avoid broken metric links.
- Avoid global pollution in Lua; prefer local tables/functions unless intentional shared state.

## Docs
- `README.md`: upstream Simply Love readme, plus a **This fork** section at the top.
- `docs/server-mode.md`: the fork's Server play mode (setup, flow, code map).
- `docs/server-song-loader.md`: the song loader script.

Docs describe current behavior. Change history belongs in commits and PRs, not in `docs/`.

## Editing Safety
- Make small, targeted changes and keep behavior compatible unless intentionally changing flow.
- If modifying screen transitions, verify related branches in both `metrics.ini` and branching helpers.
- If adding options/preferences, keep defaults and migration behavior clear.
- If touching assets referenced by `.redir`, verify path/name consistency.

## First Reads For New Sessions
1. `docs/server-mode.md`
2. `Scripts/SL_Init.lua`
3. `Scripts/99 SL-ThemePrefs.lua`
4. `metrics.ini`
