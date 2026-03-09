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

### 2026-03-09
- Area: Repository documentation
- Decision: Added `AGENTS.md`, `KNOWLEDGE_INDEX.md`, and `docs/` knowledge system.
- Reason: Preserve durable context while keeping future session context small.
- Impact: Future sessions can discover project knowledge from the root index and load only needed docs.
- Follow-up: Add topic docs as new features/debug findings are implemented.
