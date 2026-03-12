# Feature Log

Tracks fork-specific features and improvements added beyond upstream Simply Love behavior.

## Entry Format
- Date: YYYY-MM-DD
- Feature: short title
- Area: primary files touched
- Summary: behavior change
- Notes: optional implementation/context details

## Entries

### 2026-03-12
- Feature: Queue mode fetches current song from backend
- Area: `BGAnimations/ScreenQueueReady underlay.lua`, `Languages/en.ini`
- Summary: Replaced the hardcoded Queue mode song with a `GET /api/game/song/current` request using the configured machine-level server URL/token.
- Notes: The screen now resolves the returned `song.file_path` to a local song, preselects the requested difficulty when available, and surfaces loading/config/network/song-mapping errors in the queue UI.

### 2026-03-12
- Feature: Machine-level StepMania server config
- Area: `Scripts/98 SL-StepManiaServerConfig.lua`, `Scripts/SL_Init.lua`, `docs/stepmania-server-config.md`
- Summary: Added a dedicated `Save/StepManiaServer.ini` config path for backend URL/token storage and exposed sanitized values through `SL.Global.StepManiaServer`.
- Notes: URL values are trimmed and normalized to remove trailing slashes; token values are trimmed and stored opaquely. The file is auto-created and normalized during theme startup.

### 2026-03-09
- Feature: Song selection difficulty name + meter layout
- Area: `BGAnimations/ScreenSelectMusic overlay/StepsDisplayList/Grid.lua`, `BGAnimations/ScreenSelectMusic overlay/PerPlayer/Cursor.lua`, `BGAnimations/ScreenSelectMusic overlay/PerPlayer/DensityGraph.lua`
- Summary: Extended song-select difficulty display to include localized difficulty names alongside meters, using aligned name/meter boxes.
- Notes: Included layout/cursor/chart-info positioning adjustments so the new labels fit cleanly without overlapping nearby elements, and shifted the `STEPS` header strip left to better align with chart info.

### 2026-03-09
- Feature: Queue mode POC loop (fixed song)
- Area: `metrics.ini`, `Scripts/SL-Branches.lua`, `Scripts/SL_Init.lua`, `Scripts/SL-Helpers.lua`, `Languages/en.ini`, `BGAnimations/ScreenQueueReady underlay.lua`
- Summary: Added a new `Queue` mode that loops a fixed song (`Butterfly`) through a ready screen -> gameplay -> results -> ready screen flow.
- Notes: `ScreenQueueReady` lets the player cycle chart difficulty before pressing START, reuses SelectMusic chart/stats widgets, and includes a back-confirmation modal.
