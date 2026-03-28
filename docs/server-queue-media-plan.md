# Server Queue Media Plan

Planning note for media features on the server-driven queue flow.

This document records desired behavior for queue-screen banner art and preview audio, but both areas still need more research before implementation should be considered stable.

## Planned Features

### Queue Banner Art

Desired end state:

- show real song art for the active queue head on the queue/ready view
- update the art when `queue_item_id` changes
- clear or replace the art appropriately when the queue becomes empty

Current status:

- planned feature
- blocked by unresolved screen/media loading issues
- see [server-mode-song-art-debugging.md](./server-mode-song-art-debugging.md) for current findings

Research still needed:

- whether this should be solved on `ScreenQueueReady` directly
- whether the queue flow should move to a different screen path before retrying song-art work
- whether a theme-local cache/mirror path is safer than direct `/Songs/...` asset loading

### Queue Preview Audio

Desired end state:

- play the selected song preview on the queue/ready view
- stop/replace preview audio when the queue head changes
- remain silent on empty/error states unless a later UX decision says otherwise

Current status:

- planned feature
- not yet researched enough to choose an implementation direction

Research still needed:

- which engine/theme audio path is safest for a non-SelectMusic queue screen
- whether preview audio should run on `ScreenQueueReady` or only after moving the queue UX to a different screen flow
- lifecycle rules for preview audio during menus, modals, gameplay handoff, and results

## Planning Note

These two media features are important for the queue UX, but should be treated as separate workstreams from the queue state/polling logic.

The queue control flow can be implemented without them, but the intended polished experience still includes both:

1. song/banner art for the active queue head
2. song preview audio for the active queue head
