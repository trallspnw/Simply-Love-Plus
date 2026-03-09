# Project Structure

## Scope
High-level map of this StepMania/ITGmania theme fork and where future features should be implemented.

## Root Files
- `ThemeInfo.ini`: Theme identity metadata (`DisplayName`, `Author`, `Version`).
- `metrics.ini`: Primary engine-facing config for screen classes, transitions, timers, and many behavior hooks.
- `README.md`: Upstream-facing overview and installation docs links.

## Core Directories
- `Scripts/`: Shared Lua systems and globals.
  - `SL_Init.lua`: Initializes shared `SL` state for `P1`, `P2`, and `Global`.
  - `99 SL-ThemePrefs.lua`: Defines custom theme preferences and defaults.
  - `SL-Branches.lua`: Branching logic used by metrics/screen transitions.
  - Helpers/parsers: chart parsing, layout, options, utility layers.
- `BGAnimations/`: Screen-level implementation.
  - `Screen*` folders/files define underlay/overlay/decorations and screen-specific behavior.
  - Many screens use `.redir` for fallback/reuse.
- `Graphics/`: Visual resources and actor scripts.
  - Contains static assets and Lua actor files.
  - `.redir` files are used heavily for indirection and sharing.
- `Fonts/`, `Sounds/`, `Languages/`: Resource sets.
- `Modules/`: Optional extension mechanism for screen-specific injected actors.
  - Modules return a table mapping `ScreenName -> Actor/ActorFrame`.
- `Other/Documentation/`: Additional upstream user guides.

## Practical Change Routing
- Add shared gameplay/ui logic in `Scripts/`.
- Add or alter a specific screen experience in `BGAnimations/Screen...`.
- Adjust flow/timers/choice wiring in `metrics.ini` and related branch helpers.
- Add/replace visuals in `Graphics/` while preserving redirect naming conventions.

## Known Patterns
- Theme relies on both metrics and Lua actor scripts together.
- Global cross-screen state is centralized in `SL` initialized by `SL_Init.lua`.
- Preference-driven behavior is largely configured through theme prefs in `99 SL-ThemePrefs.lua`.
