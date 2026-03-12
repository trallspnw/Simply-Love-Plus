# Knowledge Index

This is the durable context index for this fork. Keep this file lightweight and use it to point to deeper docs in `docs/`.

## How To Use
- Read this file first in new sessions.
- Add a new `docs/*.md` file when information is likely to be useful in future sessions.
- Keep each index entry concise and link to exactly one primary doc.

## Entry Rules
- One topic per doc.
- File names: lowercase kebab-case (example: `feature-x-spec.md`).
- Include a short summary and concrete scope.
- Update `Last Updated` whenever content meaningfully changes.

## Indexed Knowledge

| Topic | Summary | Doc | Last Updated |
|---|---|---|---|
| Project Structure | High-level map of theme folders and where to implement changes. | [docs/project-structure.md](./docs/project-structure.md) | 2026-03-09 |
| Docs System | Rules for adding durable knowledge and keeping context lean. | [docs/README.md](./docs/README.md) | 2026-03-09 |
| Fork Decisions Log | Ongoing record of fork-specific decisions and rationale. | [docs/change-log.md](./docs/change-log.md) | 2026-03-09 |
| Feature Log | Chronological list of fork-only feature improvements versus upstream behavior. | [docs/feature-log.md](./docs/feature-log.md) | 2026-03-12 |
| Theme Networking | Confirmed engine networking APIs available to theme Lua and how to apply them for queue mode. | [docs/theme-networking-capabilities.md](./docs/theme-networking-capabilities.md) | 2026-03-10 |
| StepMania Server Config | Machine-level storage pattern for backend URL/token and runtime access points. | [docs/stepmania-server-config.md](./docs/stepmania-server-config.md) | 2026-03-12 |

## Template For New Entries
Use this row format when adding docs:

`| <Topic> | <1-line summary> | [docs/<file>.md](./docs/<file>.md) | YYYY-MM-DD |`
