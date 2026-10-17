The existing world clock now reads `calendar.json`. `Asia/Manila` remains the
default. Date/day/time, environment, monitor and planning use the server's
injected epoch clock; the browser follows that epoch between status updates.
`dayOfWeek` is Monday=0 through Sunday=6. Calendar tests inject an epoch or pass
an explicit Date to `worldClock`; they never change the operating system clock.

No real holiday dates, birthday, or performance schedule are shipped. Add an
explicit verified appointment to the `events` array. For a fictional event use
an intentional configured date. An event is one-off: recurring performances
need separate eventIds. A terminal event cannot be replayed by reusing its ID.

Example schema (the following is documentation, **not an enabled event**):

```json
{
  "eventId": "owner-scheduled-practice-2026-10-10",
  "title": "MIKA MOTION rehearsal",
  "startDateTime": "2026-10-10T18:00:00+08:00",
  "endDateTime": "2026-10-10T18:45:00+08:00",
  "timezone": "Asia/Manila",
  "category": "fictional",
  "priority": 2,
  "preparationWindow": 86400,
  "activities": ["dance"],
  "environmentChanges": ["festive"],
  "outfitPreference": "HOME",
  "completionConditions": ["dance"],
  "cooldown": 86400
}
```

`preparationWindow` and `cooldown` are seconds. Activities must be existing
semantic capability names. They are selected only when currently available,
outside action/failure/dance cooldowns, and at a normal safe segment boundary.
Weekday preferences affect weights rather than becoming promised appointments.
An event completes only after all `completionConditions` actions are confirmed
while it is active. Empty conditions require explicit local administration.
Ending an event window does **not** claim it was completed: status becomes
`ended`. The owner may cancel/postpone through `WorldCalendar.set_status` in
server-side administration code. No LLM or viewer raw state-editing API exists.
Offset timestamps are recommended; ambiguous/nonexistent DST wall times require
an explicit offset. Invalid entries are diagnosed and excluded. `outfitPreference`
is context only: it does not bypass existing private-change or quality guards.

Optional HOME paper-bunting layers: `festive`, `birthday`, `christmas`,
`halloween`. They require an explicitly configured active event, have no lights
or colliders, and dispose their small geometry/materials when removed. Unsupported
environment directives are not executed. These are simple decoration layers,
not elaborate holiday room redesigns. The same day/night environment is retained.

Persistence sits beside the existing story checkpoint as
`<story-checkpoint-path>.calendar.json`. Version 1 stores one-off event status,
transition timestamps, action conditions, postponement dates, the last 96
confirmed action timestamps, 31 dated activity summaries and 30 observed civil
rollovers. It contains no viewer names/messages, bone transforms, phone physics
or camera transforms. Daily history means acknowledged activities, not a claim
of exactly how much reading/work Mika accomplished. Old sessions before this
feature have no backfilled yesterday history. Missing records are acknowledged.
Story checkpoint expiry and safe HOME reconstruction remain unchanged.

The two rooms retain their internal STUDIO/ARCADE anchor and collision IDs.
Public names and viewer intents use **MIKA MOTION** (rehearsal/content studio)
and **NEON PULSE** (disco/rhythm-game arena).
