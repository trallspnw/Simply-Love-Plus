# Theme Networking Capabilities

## Summary
This fork's theme environment has engine-level networking available to Lua.
Direct network integration for queue data is feasible without external tooling.

## Confirmed Available APIs
- `NETWORK:HttpRequest{...}` for async HTTP requests.
- `NETWORK:WebSocket{...}` for websocket connections.
- `JsonEncode(...)` / `JsonDecode(...)` for JSON payloads.

## Confirmed In-Repo Usage
- HTTP request wrapper:
  - `Scripts/SL-Helpers-GrooveStats.lua:93`
- HTTP file download with progress callback:
  - `Scripts/SL-Helpers-GrooveStats.lua:686`
- WebSocket login flow:
  - `BGAnimations/ScreenGrooveStatsLogin underlay/default.lua:12`
- API request with encoded query and JSON body:
  - `BGAnimations/ScreenEvaluation common/Shared/AutoSubmitScore.lua:401`

## Implication For Queue Mode
Queue mode can fetch `username` and `song_path` from a network endpoint directly in theme Lua.

Recommended shape:
- On `ScreenQueueReady` load: request next queue item via `NETWORK:HttpRequest`.
- Parse JSON response and resolve song using song directory/path match.
- Keep a fallback path or local cache for offline/timeout behavior.

## Notes
- Existing theme code already handles async callbacks and response parsing patterns.
- Reusing the established GrooveStats request style reduces risk.
