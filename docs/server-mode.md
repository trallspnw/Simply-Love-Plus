# Server Mode

This fork adds a **Server** play mode that plays songs queued on a [stepmania-server](https://github.com/trallspnw/stepmania-server) backend: players queue songs from their phones, and the machine plays them in turn and reports the results.

## Setup

1. Create a machine token in the server's admin console.
2. Set the server address and token in `Save/StepManiaServer.ini`, in the game's data folder (on Linux, `~/.itgmania`, not the theme folder):
   ```ini
   [StepManiaServer]
   Url=https://your-server.example.com
   Token=<machine token>
   ```
   The theme creates the file with empty values on first start and rewrites it on every start, trimming whitespace and trailing slashes. It's a file rather than a theme option because the operator menus only offer fixed choices, not free text.
3. Add the server's host to `HttpAllowHosts` in `Save/Preferences.ini`, with the game closed (it rewrites that file on exit). ITGmania blocks theme HTTP requests to any other host, and Lua can't change this setting.
   ```ini
   HttpAllowHosts=*.groovestats.com,*.itgmania.com,your-server.example.com
   ```
4. Get the server's songs onto the machine with the [song loader](./server-song-loader.md). Server Mode finds each queued song by the server's `Pack/Song` folder name, so the machine needs the same folders.

## Playing

Choose **Server** on the play-mode screen. `ScreenQueueReady` then:

1. Asks the server for the song at the head of the queue (`GET /api/game/song/current`) and shows it: banner, the player whose turn it is, and the player's and machine's best scores for the selected chart. With nothing queued it shows **Server Idle** and keeps checking.
2. Lets the player change difficulty, then START plays the chart and tells the server it started.
3. After the song, the result goes to the server (score and grade), which records it in the player's history and highscores and moves to the next song.

BACK opens a menu: **Continue**, **Song Options**, **Skip** (removes the song from the queue) and **Exit**.

Errors (no config, server unreachable, a queued song or chart that isn't on this machine) are shown on screen with START to retry. A queued song that isn't on the machine keeps failing until it's skipped from that menu or synced onto the machine.

Request and response formats: the server repo's [`docs/machine-api.md`](https://github.com/trallspnw/stepmania-server/blob/main/docs/machine-api.md).

## Code

| Path | Role |
|------|------|
| `Scripts/98 SL-StepManiaServerConfig.lua` | Reads, normalizes and writes `Save/StepManiaServer.ini`; values at `SL.Global.StepManiaServer.Url` / `.Token` |
| `BGAnimations/ScreenQueueReady underlay.lua` | The Server Mode screen: polling, song lookup, start/skip, menus |
| `Tools/serversongloader/` | Song loader (see [server-song-loader.md](./server-song-loader.md)) |

Server requests use `NETWORK:HttpRequest`, the same engine API the GrooveStats code uses. Its `onResponse` callback runs on the main thread, but texture loads (such as the banner's `LoadFromSong`) only render reliably from the screen's `SetUpdateFunction` loop, so the screen defers them there.

## Other fork changes

- Song select shows each difficulty's name next to its meter.
