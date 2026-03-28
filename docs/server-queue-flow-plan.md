# Server Queue Flow Plan

Planning notes for the server-driven queue flow. This is an implementation plan only, not a statement that the current theme already behaves this way.

## Goal

Drive the cabinet flow from the machine API so the theme continuously reflects the current queue head, handles empty/error states cleanly, and reports lifecycle events (`start`, `skip`, `finish`) back to the server with `queue_item_id`.

## Core State Model

The queue UI should be treated as a small state machine with three main view states:

1. `error`
2. `empty`
3. `ready`

Separate from the current view state, the client should also track:

- `queue_item_id`
- current `song.file_path`
- current `song.difficulty_name`
- current player display name
- current user high score
- current machine high score
- poll timing / consecutive failure count

`queue_item_id` is the primary identity for detecting queue-head changes. If it changes, all queue-head-derived UI should be refreshed together.

## Polling Behavior

### Startup

On entering the queue flow, the client should:

1. begin polling `GET /api/game/song/current`
2. retry every 5 seconds while waiting for a usable response
3. count consecutive failures
4. transition to `error` after too many consecutive failures

Threshold decision:
- enter `error` after 3 consecutive failures with the normal 5-second polling interval between attempts

Failure types that count toward the threshold:
- request timeout
- HTTP `400` responses
- HTTP `500` responses
- HTTP `401` responses should be treated the same way for simplicity

### Valid Response Handling

On a valid `200` response:

- reset the consecutive failure count
- compare `queue_item_id` with the current local queue-head identity

If the response has no current song:

- enter `empty`
- continue polling every 5 seconds

If the response has a current song:

- resolve the local song from `song.file_path`
- select the requested chart from `song.difficulty_name`
- store `queue_item_id`
- store player and high score display data
- enter `ready`

### Ready-State Polling

While in `ready`, continue polling every 5 seconds.

On each poll result:

- if the response is invalid or request fails, count the failure and eventually enter `error`
- if the response is valid and `song` is `null`, transition to `empty`
- if the response is valid and `queue_item_id` matches the current one, do nothing
- if the response is valid and `queue_item_id` changed, treat it as a full queue-head replacement:
  - update song
  - update difficulty
  - update player display name
  - update user high score
  - update machine high score
  - remain in or re-enter `ready`

## View Responsibilities

### Error View

Shows when polling fails too many times in a row or when a response is unusable in a way that blocks queue operation.

Expected behavior:

- stop normal ready/empty presentation
- show a clear error state
- show the most recent failure message
- allow manual retry only
- allow `Back` / `Exit`

### Empty Queue View

Shows when the server responds successfully but no current queue head exists.

Expected behavior:

- continue polling every 5 seconds
- if a song appears, transition to `ready`
- if polling fails too many times, transition to `error`

### Song/Ready View

Shows when a queue head exists and has been mapped locally.

Expected behavior:

- display current song info
- auto-select the difficulty from the response
- display player high score and machine high score
- continue polling every 5 seconds for queue-head changes

## Queue Identity And Selection Rules

When a valid queue head is loaded:

- store `queue_item_id`
- resolve the local song from `song.file_path`
- resolve the local chart from `song.difficulty_name`
- apply that chart selection immediately

If `queue_item_id` changes:

- treat the response as a new queue head even if the song path appears similar
- refresh all queue-derived display fields, not just the song title

## Back/Menu Flow

From the `ready` view, `Back` should open a menu with three choices:

1. `Continue`
2. `Skip`
3. `Exit`

### Continue

- close the menu
- return to the `ready` view
- suppress poll-driven transitions while the menu is open

### Skip

- send `POST /api/game/song/skip`
- include `queue_item_id`
- wait for the request result
- after a successful skip, repoll `GET /api/game/song/current`
- transition based on the repoll result:
  - `empty` if queue is empty
  - `ready` if a new queue head exists
  - `error` if the repoll fails too many times or response is unusable

No second confirmation is needed because `Skip` is already chosen from the back menu.

### Exit

- leave the queue flow
- return to the main game menu by default

## Start Flow

From the `ready` view, `Enter` / `Start` should:

1. send `POST /api/game/song/start`
2. include `queue_item_id`
3. include the selected `difficulty_name`
4. store the returned user/machine high score context as the pre-play baseline for result-page PR messaging
5. on success, transition into gameplay

Failure behavior still needs to be nailed down, but the likely path is:

- stay on the `ready` view
- surface an error state or modal
- keep polling

Poll-driven transitions should be suppressed while menus or modal dialogs are open.

## Song Failure / Retry Flow

On a failed song result, the gameplay/results flow should allow:

1. `Retry`
2. `Change Diff`
3. `Forfeit`

Current planning note:
- `Change Diff` is now accommodated by the machine API by sending explicit `difficulty_name` values on both `start` and `finish`.
- The queued song identity still comes from `queue_item_id`, but chart identity is now client-declared per play attempt.

## Finish Flow

When gameplay completes, the theme should:

1. collect final numeric score
2. collect final letter grade
3. send `POST /api/game/song/finish`
4. include `queue_item_id`
5. include the actually played `difficulty_name`
6. include `score`
7. include `grade`

After the request:

- show the normal result screen
- begin polling for the next queue head while on results

If the queue head changed after `start`, `finish` may fail because the original `queue_item_id` is no longer current. In that case:

- ignore the `finish` failure
- continue showing results
- continue into the next-song flow normally

## Results View Behavior

The result screen should:

- show the result as normal
- show user and machine high score context
- show PR messaging when appropriate
- poll `GET /api/game/song/current` in the background every 5 seconds

On `Enter` from the result screen:

- go to `ready` if a queue head exists
- go to `empty` if the queue is empty

The result screen should preload the next queue state in the background, but should still wait for explicit `Enter` before leaving results.

## High Score Display Requirements

On the `ready` view, display:

- user high score grade and percent
- machine/server high score grade and percent
- machine/server high score holder name

On the result view, display:

- user high score grade and percent
- machine/server high score grade and percent
- machine/server high score holder name
- PR messaging for:
  - user personal record
  - machine/server record

PR rule:
- ties do not count as a PR; only strictly higher scores should trigger PR messaging
- use the `start` response high scores as the pre-play baseline and the `finish` response high scores as the post-play result

## API Fit For This UX

Based on the documented machine API shape, the server contract is broadly sufficient for the planned UX if the queue-oriented `queue_item_id` flow is treated as canonical.

The theme depends on these response properties:

- `GET /api/game/song/current`
  - must provide `queue_item_id` when a current song exists
  - must provide `song.file_path`
  - must provide `song.difficulty_name`
  - must provide `player.display_name` when known
  - must provide `user_highscore`
  - must provide `server_highscore`, including `held_by`
- `POST /api/game/song/start`
  - must accept `queue_item_id`
  - must accept the selected `difficulty_name`
  - should be safe to call idempotently
  - should return pre-play user and machine high score context for the selected chart
- `POST /api/game/song/skip`
  - must accept `queue_item_id`
  - should remove the active queue head and allow the client to repoll immediately
- `POST /api/game/song/finish`
  - must accept `queue_item_id`
  - must accept the actually played `difficulty_name`
  - must accept numeric `score`
  - must accept letter `grade`
  - should return updated user and machine high score context for the just-finished chart

For the planned result-screen UX:

- `start` returning high score context is useful because it provides the pre-play PR baseline for the selected chart
- `finish` returning high score context is useful because it provides the post-play result immediately without waiting for a second derived computation on the client

## Documentation Note

This plan assumes the queue-oriented `queue_item_id` contract documented in [game-api-contract.md](./game-api-contract.md).

## Recommended Implementation Slices

1. Stabilize polling/state transitions for `error`, `empty`, and `ready`
2. Make queue-head replacement fully driven by `queue_item_id`
3. Wire `start` and `skip` using `queue_item_id`
4. Wire `finish` from gameplay/results using `queue_item_id`, `difficulty_name`, score, and grade
5. Add high score rendering and PR messaging on `ready` and results

## Open Questions

These still need explicit decisions before implementation is fully pinned down:

1. If `song.file_path` resolves to no local song, should that count toward the same 3-failure threshold or immediately enter `error`?
