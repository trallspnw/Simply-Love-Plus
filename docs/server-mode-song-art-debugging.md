# Server Mode Song Art Debugging

Notes from debugging song-art rendering on `ScreenQueueReady` for Server mode.

## Summary

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
