# Game API Contract (Machine/Theme Client)

## Last Verified
2026-03-27 (updated from current machine API details)

## Auth
- Header: `Authorization: Bearer {machine_token}`
- Applies to all `/api/game/*` routes.
- Machine tokens are managed from the admin UI.

If the token is missing or invalid:
- `GET /api/game/song/current` returns `401` with an empty body.
- Mutation routes return `401` JSON:

```json
{ "error": "Unauthorized" }
```

## Current Model

The machine API works against the current queue/current-song state.

Current behavior:
- If a queue entry exists, the queue head is treated as the current song.
- `start` marks the current queue head as `playing`.
- `skip` removes the current queue head and advances.
- `finish` records play history, removes the current queue head, and advances.

## Machine-Facing Endpoints

### `GET /api/game/song/current`

Returns the current song context for the machine.

Success with no current song:

```json
{
  "song": null,
  "player": null,
  "user_highscore": null,
  "server_highscore": null
}
```

Success with current song present:

```json
{
  "queue_item_id": 42,
  "song": {
    "file_path": "1Arc2008 - DDR X/Butterfly",
    "difficulty_name": "Hard"
  },
  "player": {
    "id": 12,
    "display_name": "Jordan"
  },
  "user_highscore": {
    "score": 97.43,
    "grade": "AA"
  },
  "server_highscore": {
    "score": 99.12,
    "grade": "AAA",
    "held_by": "Alex"
  }
}
```

Response fields:
- `queue_item_id`: Current queue entry id. Pass this back to `POST /api/game/song/start`, `POST /api/game/song/skip`, and `POST /api/game/song/finish`.
- `song.file_path`: Relative song path used by the server, matching ingested `Song.filePath`.
- `song.difficulty_name`: Selected chart difficulty name.
- `player`: Active player for the current song, if known.
- `user_highscore`: Best recorded score for the current player on the current chart.
- `server_highscore`: Best recorded score for any player on the current chart, including `held_by`.

Notes:
- High scores are chart-specific, not just song-specific.
- `score` is a decimal percentage, for example `100.00` or `75.23`.
- `grade` is stored and returned alongside the numeric score.

### `POST /api/game/song/start`

Marks the current queue song as started.

This route is idempotent for the current queue head. If the current entry is already `playing`, it still returns success.

Request body:

```json
{
  "queue_item_id": 42
}
```

Request field rules:
- `queue_item_id`: Required positive integer. It must match the current queue head or the request fails with `400` and no state change occurs.

Success:

```json
{
  "ok": true,
  "queue_item_id": 42,
  "song": {
    "file_path": "1Arc2008 - DDR X/Butterfly",
    "difficulty_name": "Hard"
  },
  "player": {
    "id": 12,
    "display_name": "Jordan"
  }
}
```

Invalid or mismatched `queue_item_id`:

```json
{ "error": "queue_item_id must be a positive integer" }
```

or:

```json
{ "error": "queue_item_id does not match the current queue item" }
```

Status: `400`

If no current song exists:

```json
{ "error": "No current song set" }
```

Status: `400`

### `POST /api/game/song/skip`

Skips the current song.

Current behavior:
- If a queue entry exists, it is removed and the queue advances.
- No play history is recorded.

Request body:

```json
{
  "queue_item_id": 42
}
```

Request field rules:
- `queue_item_id`: Required positive integer. It must match the current queue head or the request fails with `400` and no state change occurs.

Success:

```json
{
  "ok": true,
  "skipped": {
    "file_path": "1Arc2008 - DDR X/Butterfly",
    "difficulty_name": "Hard"
  },
  "next_song": {
    "queue_item_id": 43,
    "file_path": "1Arc2008 - DDR X/Paranoia",
    "difficulty_name": "Challenge"
  }
}
```

`next_song` is `null` when the queue becomes empty.

Invalid or mismatched `queue_item_id`:

```json
{ "error": "queue_item_id must be a positive integer" }
```

or:

```json
{ "error": "queue_item_id does not match the current queue item" }
```

Status: `400`

If no current song exists:

```json
{ "error": "No current song set" }
```

Status: `400`

### `POST /api/game/song/finish`

Records a completed play and advances the queue/current-song state.

Request body:

```json
{
  "score": 100.00,
  "grade": "AAA",
  "queue_item_id": 42
}
```

Optional test payload:

```json
{
  "queue_item_id": 42,
  "score": 75.23,
  "grade": "B",
  "test": true
}
```

Request field rules:
- `score`: Required non-negative decimal value.
- `grade`: Required non-empty string.
- `test`: Optional boolean. When `true`, the resulting `PlayHistory` row is marked as test data.
- `queue_item_id`: Required positive integer. It must match the current queue head or the request fails with `400` and no state change occurs.

Success:

```json
{
  "recorded": true,
  "queue_item_id": 42,
  "user_highscore": {
    "score": 97.43,
    "grade": "AA"
  },
  "server_highscore": {
    "score": 99.12,
    "grade": "AAA",
    "held_by": "Alex"
  },
  "next_song": {
    "queue_item_id": 43,
    "file_path": "1Arc2008 - DDR X/Paranoia",
    "difficulty_name": "Challenge"
  }
}
```

If `queue_item_id` does not match the active queue head:

```json
{ "error": "queue_item_id does not match the current queue item" }
```

Status: `400`

Validation errors:

```json
{ "error": "score must be a non-negative decimal value" }
```

```json
{ "error": "grade must be a non-empty string" }
```

Status: `400`

Missing current song:

```json
{ "error": "No current song set" }
```

Status: `400`

## History And High Score Semantics

Play history is stored in `PlayHistory`.

Current behavior:
- History is chart-specific via `chartId`.
- A finish event stores `songId`, `chartId`, `userId`, `score`, `grade`, `isTest`, and `playedAt`.
- User highscores are the highest score for the same player on the same chart.
- Server highscores are the highest score for any player on the same chart.
- Ties are broken by earliest `playedAt`.

## Admin-Side Dependencies And Test Surface

### `GET /api/admin/settings/current-song`

Returns:

```json
{
  "songPath": "Pack Name/Song Title",
  "difficulty": "Expert",
  "playerId": "3"
}
```

### `PUT /api/admin/settings/current-song`

Sets all three current-song fields together.

### `GET /api/admin/users/active`

Returns active users:

```json
[
  {
    "id": "3",
    "displayName": "Jordan"
  }
]
```

Admin test behavior:
- The admin `Test` tab can call machine routes directly.
- Token may be omitted intentionally to test unauthorized responses.
- Admin-triggered `POST /start`, `POST /skip`, and `POST /finish` requests must include `queue_item_id`.
- Admin-triggered finish requests are forced to `test: true`.
- The admin `History` tab can clear test-only history rows.

## Current Gaps

Known limitations at the time of writing:
- `grade` accepts any non-empty string; there is no canonical grade validation yet.
- `skip` does not write any history.
- There is no separate machine heartbeat route; token `lastSeen` is updated opportunistically on authenticated machine requests.

## Current Client Assumptions
- Single stable bearer-token auth scheme.
- `current` returns JSON on success with stable top-level fields.
- `current.queue_item_id` is required when a song is present and must be persisted client-side for follow-up mutation calls.
- `start` is available and safe to call idempotently for the active queue head.
- `skip` requires `queue_item_id` and advances queue-backed state without recording history.
- `finish` requires `queue_item_id`, validates score and grade, records play history, updates highscores, and advances state.
