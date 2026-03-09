# Docs Directory

This folder stores durable, reusable project knowledge that should persist across sessions.

## Goal
Keep session context small while preserving important details for future work.

## Add A New Doc When
- A behavior/quirk is non-obvious and likely to matter again.
- A feature plan or design decision should be referenced later.
- A debugging finding explains recurring failures or edge cases.

## Preferred Doc Types
- Architecture notes (`architecture-*.md`)
- Feature specs (`feature-*-spec.md`)
- Runbooks (`runbook-*.md`)
- Debug notes (`debug-*.md`)
- Decision records (`decision-*.md`)

## Writing Rules
- Be specific and concrete.
- Include paths, screen names, and metrics keys when relevant.
- Keep summaries at top; details below.
- Avoid duplicating content already in other docs.

## Required Step After Creating/Updating A Doc
Update `KNOWLEDGE_INDEX.md` in the repo root so future sessions can discover it quickly.
