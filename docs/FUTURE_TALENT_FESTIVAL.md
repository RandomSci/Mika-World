# Future: Magical Talent Festivals (roadmap — NOT implemented)

This is a design direction for a later, separately approved milestone. Milestone I only builds the
foundations listed at the end; it contains no registration, judging, voting, ranking or multiplayer code.

## Concept
Occasionally the world announces a festival. Independent characters (Mika, Luna, and future mages from
other regions with their own specialities) **decide for themselves** whether to take part, practise,
prepare a performance, perform at a scheduled event, receive results, react in character, and remember it.
Results are never predetermined in anyone's favour.

## Possible categories
Singing · dancing · magical performance · spell choreography (spell effects timed to music) · instrumental
(once instruments exist) · original magical demonstrations · group performances · music-and-magic combinations.

## Lifecycle (future)
1. **Announcement** — a world event with date, venue (an existing location), categories.
2. **Decision** — each character's planner weighs it like any activity (interest, confidence, rivalry,
   schedule). Declining is valid.
3. **Preparation** — practice sessions are real performances logged as practice (they raise familiarity
   with a song / routine through the same mechanics as Milestone I).
4. **Selection** — a song from the shared catalogue + a routine (dance clips, spell cues).
5. **Event** — scheduled special performances in sequence, with the special camera profile.
6. **Judging** — see below.
7. **Results** — announced; reactions come from each character's personality and relations.
8. **Memory** — stored in each performer's own history.

## Honest judging
Judges (NPCs or other characters) score only what the simulation actually measures, and the scoring
says so. Candidate measures:
* timing accuracy — how close dance-clip phrase changes and spell cues landed to beats/bars;
* completion — performance finished without interruption, ended on a planned ending;
* coordination — no foot sliding / collisions / interrupted animations recorded during the routine;
* magic synchronisation — spell or particle cues fired on musical events;
* variety — number of distinct routines / cues used (within what the system supports);
* audience response — **only** from verified real viewer input (never invented).
These are **proxies**. The festival must not claim to measure artistic talent objectively.

## Audience participation (later)
Votes or cheers only from genuine viewer input, with identity validation, rate limits, moderation and
anti-manipulation protections. Nothing is fabricated in DEV or LIVE. Multiplayer viewer access needs its
own permissions model before it exists.

## Constraints
* Performance: one performer on camera at a time at full detail; others in the nearby/background tiers.
* API cost: no LLM calls are needed to play cached songs; commentary (if any) is budgeted and optional.
* Music rights: every song used publicly needs confirmed commercial / broadcast rights (the first song was
  generated with Suno; its rights depend on the plan it was made under). Track this in each song's metadata.
* Length: Milestone I caps performances at 60–90 s total; longer festival slots need explicit approval.

## What Milestone I already provides
* A shared song catalogue (`assets/audio/music/`) with per-song metadata and measured timing (beats, bars,
  sections, endings, estimated vocal activity).
* A performer-agnostic Performance Controller with **casual** and **special** modes.
* Per-character performance records (history, favourites, familiarity) stored in each mind, never shared.
* Separate performer identities, voices and preferences; planned-ending logic; special camera profile.
These records (song, mode, start, planned/actual duration, ending type, interruptions, dance clips used)
are the raw material a future festival would read; nothing else needs to be rewritten.
