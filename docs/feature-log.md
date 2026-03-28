# Feature Log

Tracks fork-specific features and improvements added beyond upstream Simply Love behavior.

## Entry Format
- Date: YYYY-MM-DD
- Feature: short title
- Area: primary files touched
- Summary: behavior change
- Notes: optional implementation/context details

## Entries

### 2026-03-28
- Feature: Queue media planning note
- Area: `docs/server-queue-media-plan.md`, `KNOWLEDGE_INDEX.md`
- Summary: Recorded banner-art and preview-audio support as planned queue features that still require more implementation research.
- Notes: Banner art remains blocked by existing queue-screen rendering issues, while preview audio is still earlier in the investigation stage.

### 2026-03-28
- Feature: Machine API chart-selection update
- Area: `docs/game-api-contract.md`, `docs/server-queue-flow-plan.md`
- Summary: Updated the queue integration docs so `start` and `finish` carry explicit `difficulty_name`, and `start` returns pre-play high score context for PR messaging.
- Notes: This removes the earlier chart-identity ambiguity around manual difficulty changes before play or on retry.

### 2026-03-28
- Feature: Server queue flow plan
- Area: `docs/server-queue-flow-plan.md`, `KNOWLEDGE_INDEX.md`
- Summary: Captured the intended polling, queue-state, start/skip/finish, and high-score behavior for the server-driven queue flow before implementation.
- Notes: The plan treats `queue_item_id` as the primary queue-head identity and leaves a short list of unresolved behavior decisions to confirm before coding.

### 2026-03-12
- Feature: Server mode song-art debugging notes
- Area: `docs/server-mode-song-art-debugging.md`, `KNOWLEDGE_INDEX.md`
- Summary: Recorded confirmed findings from debugging Server prep-screen song art rendering and documented the recommended path to reuse the Casual song-art loader instead of continuing screen-local banner experiments.
- Notes: Confirmed that theme PNGs render on `ScreenQueueReady`, while direct song-folder PNG rendering is unreliable or crashes depending on loader API.

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
