# Feature Log

Tracks fork-specific features and improvements added beyond upstream Simply Love behavior.

## Entry Format
- Date: YYYY-MM-DD
- Feature: short title
- Area: primary files touched
- Summary: behavior change
- Notes: optional implementation/context details

## Entries

### 2026-03-09
- Feature: Song selection difficulty name + meter layout
- Area: `BGAnimations/ScreenSelectMusic overlay/StepsDisplayList/Grid.lua`, `BGAnimations/ScreenSelectMusic overlay/PerPlayer/Cursor.lua`, `BGAnimations/ScreenSelectMusic overlay/PerPlayer/DensityGraph.lua`
- Summary: Extended song-select difficulty display to include localized difficulty names alongside meters, using aligned name/meter boxes.
- Notes: Included layout/cursor/chart-info positioning adjustments so the new labels fit cleanly without overlapping nearby elements, and shifted the `STEPS` header strip left to better align with chart info.
