# StepMania Server Config

## Scope
Machine-level configuration for this fork's StepMania server integration.

## Decision
Store backend server URL and auth token in a dedicated config file at `Save/StepManiaServer.ini`, not in theme prefs or the operator menu flow.

## Reasoning
- `ThemePrefs` in this theme is built around fixed choice rows and operator-menu toggles.
- Arbitrary text entry such as a base URL or opaque token is a poor fit for the existing in-game settings flow.
- The server endpoint and token are machine-scoped integration settings, not player-facing options.

## File Shape
Expected config file contents:

```ini
[StepManiaServer]
Url=
Token=
```

## Runtime File Location
The loader uses the relative path `Save/StepManiaServer.ini`. In practice, that resolves relative to the game's writable user-data directory, not the theme repository.

Observed Linux behavior:
- `~/.itgmania/Save/StepManiaServer.ini`

Practical implication:
- Do not expect the file to appear under the cloned theme folder.
- The file is created where ITGmania/StepMania stores per-machine save data for the current platform.
- Other platforms are expected to use their equivalent user-data location with the same trailing `Save/StepManiaServer.ini` path shape.

## Runtime Access
- `SL.Global.StepManiaServer.Url`
- `SL.Global.StepManiaServer.Token`

## Host Allowlist Requirement
ITGmania can block theme HTTP traffic unless the target host is allowed by the engine's HTTP host allowlist.

Observed Linux location:
- `~/.itgmania/Save/Preferences.ini`

Relevant preference:

```ini
HttpAllowHosts=*.groovestats.com,*.itgmania.com,ddr.rallspnw.com
```

Notes:
- If your backend host is not listed in `HttpAllowHosts`, theme requests can be blocked before any traffic reaches the server.
- `HttpEnabled=1` must also remain enabled.
- On other platforms, the same preference is expected to live in that platform's equivalent user-data `Save/Preferences.ini`.

## Loader Pattern
- `Scripts/98 SL-StepManiaServerConfig.lua` owns read/write/init behavior.
- `Get()` reads `IniFile.ReadFile(...) or {}` and falls back to empty defaults.
- URL values are trimmed and normalized by removing trailing `/` characters.
- Token values are trimmed but otherwise preserved as opaque strings.
- `Init()` writes sanitized defaults back so the file is auto-created and normalized at startup.

## Follow-up Guidance
- Keep this file-backed unless the theme later adds a dedicated text-entry UI.
- If authentication later becomes per-player instead of machine-wide, store that separately in player profile `.ini` files similar to the existing GrooveStats profile config.
