# Server Song Loader

## Scope
`Tools/serversongloader/serversongloader.py`: syncs a machine's server songs from stepmania-server, then exits. Linux only, Python 3 standard library only. The overall design is the wiki's **Song Sync** doc (Side Projects → StepMania Server).

## Usage
Run it before starting ITGmania, never while ITGmania is running:

```sh
python3 Tools/serversongloader/serversongloader.py            # normal sync
python3 Tools/serversongloader/serversongloader.py --verify   # also rehash local songs and repair changed or missing ones
```

Whatever runs the loader also starts ITGmania afterwards. The loader doesn't start the game.

## Setup (once per machine)
1. Copy `serversongloader.example.ini` to `serversongloader.ini` next to the script (gitignored) and set `InstallDir` to the ITGmania install folder. `--install-dir` overrides it.
2. `Save/StepManiaServer.ini` must already have `Url` and `Token` (the same file the theme uses).
3. `HttpAllowHosts` in `Save/Preferences.ini` must list the server host for the theme's queue calls. The loader doesn't set this.

## Folders and files
The data folder is `InstallDir` when it contains `Portable.ini`, otherwise `~/.itgmania` (ITGmania's own rule).

| Path (in the data folder) | Purpose |
|---|---|
| `ServerSongs/` | Exact mirror of the server library. The loader adds, replaces, and deletes freely here. |
| `ServerSongs.staging/` | Downloads in progress; emptied at the end of each run |
| `Save/ServerSongLoader.json` | Saved checksums and the manifest `ETag` |
| `Save/Preferences.ini` | The loader adds `ServerSongs/` to `AdditionalSongFoldersReadOnly`, keeping other entries and the file's CRLF line endings |

Local songs belong in `Songs/`, which the loader never touches.

## Behavior
1. Refuses to run while a process named `itgmania` exists, since ITGmania rewrites `Preferences.ini` on exit.
2. Fetches the manifest with the saved `ETag`. `304` means nothing changed: one request, done.
3. Deletes packs and songs the server no longer lists.
4. Downloads each pack-root archive or song whose server checksum differs from the saved one, or whose folder is missing. Each download is extracted to staging, checked against the server checksum, then renamed into place.
5. Saves state every 25 songs, so an interrupted first sync resumes where it stopped.

A checksum mismatch means the server folder changed after its last ingestion: the song is skipped and logged until ingestion is re-run. Any failure leaves the `ETag` unsaved, so the next run checks again.

## Exit status
| Status | Meaning |
|---|---|
| 0 | In sync |
| 1 | Sync incomplete: server unreachable, request rejected, or some songs failed |
| 2 | Setup problem (missing `InstallDir` or server config, or ITGmania running) |

## Gotchas
- A pack with the same `Pack/Song` in both `Songs/` and `ServerSongs/`: the local copy should win, but which copy ITGmania uses is unverified.
- Files edited or deleted inside `ServerSongs/` aren't noticed by a normal run unless a whole song folder is missing; use `--verify`.
