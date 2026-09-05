# Server Mode Song Art Debugging

Notes from debugging song-art rendering on `ScreenQueueReady` for Server mode.

## Resolved (2026-09-04)

Two separate bugs stacked on top of each other:

**1. The screen never tried to load the real banner at all.** It only ever
rendered a hardcoded `Def.Sprite{Texture=GetFallbackBanner()}`. Every earlier
attempt (`Def.Sprite:Load()`, `LoadFromCached`, `LoadBanner`) was also the
wrong actor class for the job — `Def.Banner` is what StepMania expects for
decoding/scaling a song banner of arbitrary source size; `Def.Sprite` doesn't
do that itself, which is why direct Sprite loads white-screened or came out
corrupted in earlier sessions.

**2. `Def.Banner:LoadFromSong()` only renders correctly when called from the
screen's own per-frame `Update` function** (or synchronously from `OnCommand`
— confirmed by reproducing it: going to Song Options and back re-enters
`OnCommand`, which — since `SL.Global.ServerQueuePrefetch` is already cached
— applies the song synchronously, and the banner suddenly rendered). Calling
the same `LoadFromSong` wherever `update_view` happened to run otherwise
(in particular, from inside the network request's `onResponse` callback)
produced a blank/white box. `Load()` also resets the sprite to the texture's
raw pixel size, which is why the banner rendered undersized instead of
white when the OnCommand path did work — this song pack uses an old-school
256x80 low-res banner (`Butterfly.png` under `1Arc1998 - DDR`), well below
the theme's assumed 418x164, and nothing re-scaled it back up afterward.

Fix, in `BGAnimations/ScreenQueueReady underlay.lua`:
- Added a real `Def.Banner` actor (`Name="SongBanner"`) next to the existing
  fallback sprite, toggling visibility between them based on
  `target_song:HasBanner()` — same pattern as `ScreenEvaluation`'s
  `Shared/TitleAndBanner.lua` and `ScreenSelectMusic`'s `overlay/banner.lua`.
- `update_view` no longer calls `LoadFromSong` directly. It just records the
  song that needs loading (`pending_banner_song`). The actual
  `song_banner:LoadFromSong(...)` + `:scaletoclipped(banner_width,
  banner_height)` call happens once, on the next tick of the screen's
  `SetUpdateFunction` loop — the one execution context proven to work
  reliably, regardless of whether the song became known synchronously
  (OnCommand) or asynchronously (network response).

## Summary (historical, pre-fix)

The Server prep screen can render theme-owned PNG assets in the custom top-left art slot, but direct rendering of song-folder PNG assets from `/Songs/...` has been unreliable on this screen in this fork's current engine/runtime setup.

Observed symptoms:

- A plain `Def.Sprite:Load()` of `song:GetBannerPath()` produced a white rectangle.
- Hardcoded direct loads of song-folder PNGs did render something, but the output was visibly corrupted/misdecoded instead of showing the expected image.
- Trying `LoadFromCached("Banner", path)` / `LoadBanner(path)` from this screen caused the engine to close immediately after the load attempt.

## Confirmed Findings

### Asset lookup is not the problem

The following were confirmed during debugging:

- `song:GetBannerPath()` returned the expected `Butterfly.png` path.
- `FILEMAN:DoesFileExist(...)` returned `true`.
- `ActorUtil.ResolvePath(...)` returned the same valid `/Songs/...` path.
- The actor reported a non-nil `RageTexture` at `418x164`.

So the issue is not:

- wrong song lookup
- missing file
- unresolved path
- missing texture creation

### ScreenQueueReady does not expose a usable built-in Banner actor

The normal ITG-mode banner on `ScreenSelectMusic` relies on proxying a screen-level `Banner` actor. Debugging showed `SCREENMAN:GetTopScreen():GetChild("Banner")` was `nil` on `ScreenQueueReady`, even after adding `Banner*` metrics. That means the normal SelectMusic proxy pattern cannot simply be reused here.

### Theme assets render, song-folder assets do not render correctly

Hardcoded test sprites on `ScreenQueueReady` showed:

- a theme fallback banner PNG rendered correctly
- hardcoded song-folder PNGs (`Butterfly.png`, `Butterfly-jacket.png`, `Butterfly-bg.png`) did not render correctly

This narrows the issue to how song-folder images are being loaded/rendered on this screen, not to generic visibility, layering, or actor placement.

## Working Reference

The best known-good song-art loader in this fork is the Casual song tile implementation:

- `BGAnimations/ScreenSelectMusicCasual overlay/SongMT.lua`

That code:

- chooses jacket, then background, then banner
- uses a plain `Def.Sprite`
- prefers `LoadFromCached(type, path)` when available
- falls back to `LoadBanner(path)` for older engine behavior

## Recommended Direction

Do not continue brute-forcing `ScreenQueueReady` with direct `Load()` / `Def.Banner` permutations.

Instead:

1. Extract a small reusable song-art loader based on `ScreenSelectMusicCasual overlay/SongMT.lua`.
2. Use a hidden loader actor that follows the known-good Casual flow.
3. Copy or proxy the loaded texture into the visible Server prep-screen art slot.

This keeps the Server screen aligned with an already-working song-art path in the theme instead of relying on behavior that appears screen-specific and unstable.
