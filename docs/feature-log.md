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
- Feature: Select Music difficulty label + meter
- Area: `BGAnimations/ScreenSelectMusic overlay/StepsDisplayList/Grid.lua`, `BGAnimations/ScreenSelectMusic overlay/PerPlayer/Cursor.lua`
- Summary: Difficulty grid now renders localized difficulty name followed by numeric meter (example: `Hard 12`) and widens the row blocks to fit text.
- Notes: Cursor anchor positions were adjusted to align with the wider grid.

### 2026-03-09
- Feature: Select Music split name/meter columns
- Area: `BGAnimations/ScreenSelectMusic overlay/StepsDisplayList/Grid.lua`, `BGAnimations/ScreenSelectMusic overlay/PerPlayer/Cursor.lua`
- Summary: Difficulty grid now uses separate aligned boxes per row: difficulty name on the left and meter value on the right.
- Notes: Shifted the whole grid slightly left and made cursor X positioning follow the grid position dynamically.
