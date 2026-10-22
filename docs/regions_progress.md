# Regions progress (read this first after any compaction)

Written 22 October 2026. Worktree ~ › Downloads › Mika-Godot-Dev-Fix, branch mika-fix-20261022 (last commit 6510293). Nothing here is live. The live build (Day3, golive-20261020 at 49bc513) is untouched. Nothing goes live without Selwyn's go.

## The plan, in order

1. Every region open with smooth trips. All 16 areas of the six regions reachable, every path between them walkable, preloading so arrival and travel never freeze. Proof is one real time trip into each region with no frame over 100 ms.
2. Trip test checks added on 22 October at Selwyn's request
   * Any leg longer than 90 seconds must have the girls talking or doing something on the way. No silent walking.
   * Any build over 3 seconds must be explained and fixed, or moved off the live path (done before the girls reach the gate, or hidden behind the travel card and preloaded).
3. Signature activities per region. Objects to inspect, views, small secrets, its own magic to practise, so no place feels empty.
4. Curiosity. First visit to a place, a path or a new object makes the girls stop and wonder out loud, look closer, react to each other. They remember every place, discovery and conversation across restarts, bring it up later, and a revisit feels different from the first visit.
5. Memory and no repeated lines. Mika, Luna, every NPC and the phoenix never repeat a line. A memory of what each one said and to whom.
6. Repetition rules. Lake dance at most once per night. An activity can't repeat within 30 minutes. A place can't be visited twice in a row. Days spread across all six regions. Fights and transformations stay off.
7. Phoenix encounter on the forest path. Rare, calm, never a fight. The phoenix remembers every encounter with each girl and the talk grows over time. Proof is a 10 fps sheet plus the dialogue log.
8. Proof before anything goes live. A 10 fps sheet of one trip through every region, the phoenix sheet and the dialogue log, videos in Mika-Project › review › Test_Videos.
9. Spell duel video for approval. 45 to 60 s, Mika against Luna, only with a story reason, at most once per 2 hours, talking during, grand fast effects, dashes and blinks, shields and counters, no damage, no close combat, no swords. Never live until Selwyn sees the full video and says yes.
10. Highlight Shorts, at most 2 a day.

## World trip test

Run 1 (old test, 22 Oct afternoon) stopped at the River Valley bridge. Run 2 (new test, brain walks with Luna, talk and build checks) started 20.20, code before the fixes listed below. Log at ~ › .cache › mika_qa › fix_tests › log_worldtrip.txt.

| Area (region) | Target | Arrived | Trip time | Talks on the way | Frames over 100 ms | Build before › now |
|---|---|---|---|---|---|---|
| whispering_woods (sanctuary) | whispering_woods | yes | 41 s | 0 (under 90 s, ok) | 0 | 3932 › 1683 ms |
| ancient_grove (forest) | ancient_grove | yes | 183 s | 1 | 4 | 7517 › 3517 ms (more slicing since) |
| river_valley (forest) | luminous_river | yes | 233 s | 1 | 1 | 8580 › 3252 ms (terrain cache since) |
| village (village) | village_square | running | | | | |
| observatory_hill (village) | village_observatory | waiting | | | | |
| crystal_caverns (caverns) | crystal_entrance | waiting | | | | |
| deep_caverns (caverns) | underground_lake | waiting | | | | |
| academy (academy) | academy_courtyard | waiting | | | | |
| great_library (academy) | great_library | waiting | | | | |
| highland_path (highlands) | mountain_path | waiting | | | | |
| celestial_summit (highlands) | celestial_observatory | waiting | | | | |
| sanctuary (sanctuary) | ritual_sanctuary | waiting | | | | |
| lantern_lake (sanctuary) | lantern_lake | waiting | | | | |
| arcane_library (sanctuary) | ancient_spell_library | waiting | | | | |
| mentor_tower (sanctuary) | mentors_tower | waiting | | | | |
| wayside (forest path) | passed through on routes | | | | | |

Earlier proof. Mentor's Tower after the freeze fix, worst frame 63 ms (build 59.6 s before, about 5 s after).

### Why builds took over 3 s and what was done
* Every build piece worked 8 ms and then gave the frame back, so 1 s of work took about 4 s of travel card. Behind the opaque card a build now uses 28 ms per frame (still well under 100 ms), in view it keeps 8 ms. WorldStreamingManager.slice_us().
* Single long steps held one frame each. Woods landmarks 263 ms, grove fallen tree 732 ms and ford stones 185 ms (collision hulls of scanned rocks). Now one piece per frame.
* Terrain height grid and trail masks (about 0.9 s per forest area) are the same every build. Now cached on disk per area, keyed by the md5 of the area's scripts.
* Still to do. River crossing stones 212 ms in one frame, trunk colliders 450 ms (sliced, fine), then rerun and check every area is under 3 s.

### Fixed during run 2
* River Valley bridge stuck (Mika at the west ramp). The ramp sides had no wall, her path cut over the edge. Parapets now run down the ramps. Probe crossed the bridge.
* Trip test started while Mika's brain was already off on a day trip. The test now cancels it and starts from home.
* Luna did not walk with Mika on journeys (she only appeared beside her behind the travel card). She now walks a step behind and beside Mika, runs to catch up if far.
* Long walks were silent. On a journey they now talk about the way after 25 s and again every 75 s (MageDialogue journey talk). The trip test fails any leg over 90 s without talk.
* A first trip line invented a memory ("remember last time we were here"). The topic now says they have never been there.

## Done in this branch (committed)

* bde8550 dance gap, home region at night, wanderlust
* ca0e5a0, 1538ebc stale brain hold released (Mika standing still)
* ee616be Mentor's Tower freeze fix (sliced builds, warm list, preload record)
* c2a7186 villager voices, edge-tts 7.3.1
* 6510293 journey wait judged by progress, worldtrip and navprobe tests

## In the middle of right now

* Run 5 of the world trip started 21.03 (monitor bfa8hso5s), all fixes below in. Runs 3 and 4 logs saved in the session scratchpad (log_worldtrip_run3.txt, run4).
* Runs 3 and 4 results. Woods 55 s, grove 190 to 202 s, river 255 s, builds 1.6, 3.3 to 3.8 and 2.5 to 3.5 s, no slow frame in view on any leg, talks on every long leg, first visit scenes ran (woods looked closer at Vell's buried box, grove at the moonmoth cocoons).
* Found and fixed in runs 3 and 4
  * Curiosity waited at most 60 s for the walk to end, then stopped both girls 11.5 m short of the grove. It now never interrupts a journey.
  * Luna stopped following after the first area change (the walking along link was dropped on arrival, so on the last stretch and on every second hop she was left behind). Now kept to the journey's end.
  * Crash. Luna's brain was practising at a new grove magic target when the area changed, the target was freed mid walk. Guarded, and her own errands end when she starts walking along.
  * Walking along now has its own pause flag. Sharing the general hold flag released a hold someone else had set.
  * Preloading of recorded textures never worked for areas with a constant resource list (append to a read only list). Fixed, should shorten builds further.
* Committed 0edb263 earlier, the fixes since are not committed yet (after run 5 passes a few legs).

## What is left

1. Finish the world trip, fix every failed leg and every frame over 100 ms.
2. Add the two new trip checks (talking on legs over 90 s, builds over 3 s) and fix what they find.
3. Test and commit the brain repetition and region changes.
4. Curiosity and place memory.
5. No repeat line memory for every speaker.
6. Region signature activities and discoveries.
7. Phoenix encounter memory growth, proof sheet and dialogue log.
8. 10 fps proof sheets and videos into Test_Videos.
9. Spell duel video for approval.
10. Shorts.
11. Then tell Selwyn everything is ready. Apply to live only with his go, behind Be Right Back.
