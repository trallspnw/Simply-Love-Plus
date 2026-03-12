# Fork Decision Log

Track decisions that should persist across sessions.

## Entry Format
- Date: YYYY-MM-DD
- Area: file(s) or subsystem
- Decision: what was chosen
- Reason: why it was chosen
- Impact: what this changes
- Follow-up: optional next actions

## Entries

### 2026-03-12
- Area: StepMania server integration config
- Decision: Store backend URL and token in a dedicated machine-level config file at `Save/StepManiaServer.ini` instead of adding them to `ThemePrefs` or operator menu rows.
- Reason: The current theme prefs system is choice-based and does not fit arbitrary text entry, and these settings are machine-scoped rather than per-player options.
- Impact: Theme code can read normalized values from `SL.Global.StepManiaServer.Url` and `SL.Global.StepManiaServer.Token` without depending on in-game text entry.
- Follow-up: If the fork later needs editable in-game text fields, add a dedicated text-entry screen rather than extending the current choice-row prefs flow.

### 2026-03-09
- Area: Repository documentation
- Decision: Added `AGENTS.md`, `KNOWLEDGE_INDEX.md`, and `docs/` knowledge system.
- Reason: Preserve durable context while keeping future session context small.
- Impact: Future sessions can discover project knowledge from the root index and load only needed docs.
- Follow-up: Add topic docs as new features/debug findings are implemented.
