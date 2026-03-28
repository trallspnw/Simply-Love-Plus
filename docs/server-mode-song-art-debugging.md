# Server Mode Song Art Debugging

Notes from debugging song-art rendering on `ScreenQueueReady` for Server mode.

## Current Status

Deferred. The screen uses a static fallback banner. All known dynamic loading approaches produced a white rectangle. See attempts below.

## Confirmed Findings

### Asset lookup is not the problem

The following were confirmed during debugging:

- `song:GetBannerPath()` returned the expected path (e.g. `make it better.png`).
- `FILEMAN:DoesFileExist(...)` returned `true`.
- The actor reported a non-nil `RageTexture` at the expected dimensions.

So the issue is not wrong song lookup, missing file, unresolved path, or missing texture object.

### ScreenQueueReady does not expose a built-in Banner actor

`SCREENMAN:GetTopScreen():GetChild("Banner")` returns `nil` on `ScreenQueueReady`. The normal `ScreenSelectMusic` proxy pattern cannot be reused here. `ScreenQueueReady` uses `Fallback="ScreenWithMenuElements"` (confirmed in metrics.ini), not a `ScreenSelectMusic` subclass.

### Theme assets render — song-folder assets do not

Every method we tried to dynamically load a song-folder image produced a white rectangle. Loading a theme asset (e.g. `GetFallbackBanner()`) in the same actor renders correctly.

## Approaches Tried — All Produced White

| Method | Actor type | Result |
|--------|-----------|--------|
| `sprite:Load(song:GetBannerPath())` | `Def.Sprite` | white |
| `sprite:LoadBanner(path)` | `Def.Sprite` | white |
| `sprite:LoadFromCached("Jacket", path)` | `Def.Sprite` | white |
| `sprite:LoadFromCached("Banner", path)` | `Def.Sprite` | white |
| `sprite:LoadFromCachedBanner(path)` | `Def.Sprite` | white, tex reported 512x512 |
| `banner:LoadFromSong(song)` | `Def.Banner` | white (correct size after `setsize`) |
| `banner:LoadFromSong(song):animate(true)` | `Def.Banner` | white |
| Copy file via `RageFileUtil` to `Save/`, then `sprite:Load("Save/_server_banner.png")` | `Def.Sprite` | white |
| HTTP fetch → `FILEMAN:SetFileContents` → `sprite:Load(cached_path)` | `Def.Sprite` | abandoned (complexity, `fetch_banner_from_url` scoping bug) |

### Note on `LoadFromSong` vs ScreenEvaluation

`Def.Banner:LoadFromSong(song)` works on `ScreenEvaluation` (also a `ScreenWithMenuElements` screen). The difference: on ScreenEvaluation the song was just played, so its banner is already in the `BANNERCACHE` atlas. On `ScreenQueueReady` the song is freshly set and its banner is not in cache. The BANNERCACHE appears not to process its decode queue on this screen, so the atlas slot stays white indefinitely.

`BANNERCACHE` has no Lua bindings — `Finish()` or `Demand()` cannot be called from theme code.

### Note on `ScreenSelectMusicCasual`

`SongMT.lua` uses `Sprite:LoadFromCached(type, path)` and is confirmed to use `Fallback="ScreenWithMenuElements"`. We did not get to fully test whether `LoadFromCached` also produces white on a fresh (never-played) song on that screen; it may also rely on songs already being in cache from the music wheel's init pass.

## Recommended Direction

The most promising untried approach is to trigger a screen transition that causes the engine to populate the BANNERCACHE — for example, briefly pushing ScreenSelectMusic with the song pre-selected so the engine loads the banner into cache, then immediately transitioning to ScreenQueueReady. This is invasive to the UX and was not pursued.

Alternatively, if the server API is extended to return a song ID, the banner could be fetched directly from the server's library browse endpoint (`/api/library/browse/songs/{id}/banner`) and written to a `Save/` path, then loaded from there. This was partially implemented but abandoned due to complexity before confirming whether `Save/`-path images render (the RageFile copy approach wrote to `Save/` and loaded from there — and also produced white, suggesting the white is not path-specific but something deeper in the texture pipeline on this screen).
