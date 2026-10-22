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

## The six regions and their paths (part a of the brief)

| Region | Areas (locations) | Finds and clue trips | Its own magic (new) | What it still needs for stream |
|---|---|---|---|---|
| Arcane Sanctuary (home) | sanctuary (ritual circle, training grounds), arcane library, Mentor's Tower, Whispering Woods, Lantern Lake | woods 1 find, 1 clue trip, home has the story, books, training targets | the training grounds (rune targets, crystal, dummy) | library and tower proven in run 5, woods phoenix encounter proof |
| Enchanted Forest | Ancient Grove (grove, forgotten shrine), River Valley (luminous river, waterfall crossing), the wayside road | 3 finds, 4 clue trips | grove glyph stone, shrine seed crystal, river dew crystal, falls spray rune | grove build under 3 s (hull cache added), visual check of the new targets |
| Fantasy Village | village (square, lantern market, workshop), observatory hill | 3 finds, 2 clue trips, 5 villagers | square lantern crystal, workshop mending rune, observatory star rune | stair foot arrival (fixed, needs proof), village build 3.2 s |
| Crystal Caverns | crystal caverns (entrance, crystal hall), deep caverns (underground lake, ancient vault) | 2 finds, 2 clue trips | singing crystal, resonance crystal, vault seal rune | not yet reached in a real time trip |
| Celestial Highlands | highland path (mountain path, cliff overlook), celestial summit (observatory, cloud temple) | 3 finds, 5 clue trips | cairn rune, wind crystal, summit star rune, sky crystal | not yet reached in a real time trip |
| Grand Academy | academy (courtyard, arena, gardens), great library | 3 finds, 3 clue trips | arena crystal, courtyard exam rune, garden bloom rune | not yet reached in a real time trip |

Paths (16 connections, 15 walkable). Sanctuary to woods (forest path through the north arch, where the phoenix comes), to the library (stairway under the west ruins), to the tower (east trail), to the lake (past Starfall Hill). Woods to grove (old forest track), woods to highland path (frontier road over the ridge). Grove to river (forest track). River to village (waterfall bridge road). Village to observatory hill (stairway), to caverns (quarry road), to highland path (mountain road), to academy (old academy road). Caverns to deep caverns (tunnel). Highland path to summit (summit stairway). Academy to great library (doors). Sanctuary to academy is the sealed ley line (story, not walkable). Eight of the long roads have wayside stretches (overland.json).

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

## Daily life soak, 90 minutes (23.51 to 01.21, 23 Oct), all checks pass

* No activity again within 30 minutes, no place twice in a row, at most one lake dance a night (none happened, see below), 5 of 6 regions visited (sanctuary 3860 s, highlands 550 s, village 540 s, forest 230 s, academy 230 s). Caverns not reached in 90 minutes.
* 65 decisions. Morning day trip to the grove, back home for the afternoon, the library, nights at home, a dawn hike up the frontier road to the highland path, the village market (Hilde), the academy's great library, back home by the lake at night.
* First visits seen. The grove (closer look at the glyph stone among the giant roots), the spell library (the old map of the realm). Revisits quiet as planned.
* Found and fixed (96800a8). Luna's stargazing invite stopped Mika's walk to the lake 4 s after it set off (an invite now never stops a girl on a journey). The stargazing shot on the slope of Starfall Hill sat inside the hill and flipped with the chase lens every 4 s (now picks a side that sees both, above the ground, strikes off a hidden side, high wide shot as the last resort).
* Frame spikes over 100 ms. 64 in 90 minutes, 50 of them behind the travel card during builds. About 14 on screen in ordinary play (grove, village chats, library, boat), 105 to 138 ms each, GPU 4 to 11 ms and scripts 13 to 37 ms, so the time is lost outside the frame's own work. Next suspect is the voice model on the same GPU (the CPU voice village check tests it).
* Not in this branch yet. The magic water path and the nightly lake dance Selwyn approved on 21 Oct (cast_water_walk, frost and stars or moonlight path, once a night, chat can ask) are planned for the lake worktree but were never built. In this branch the lake dance is only the ordinary dance, at most once a night. To do after the regions proof.

## Night of 23 Oct, after the soak (all committed and pushed on mika-fix-20261022)

Proof results
* Village with the voice model on the CPU. Worse, not better (17 frames over 100 ms instead of 1, CPU at 96 C). The voice stays on the GPU as on the stream. Known and accepted for now, about one frame of 140 ms about 1.3 s after each village arrival.
* Phoenix, three meetings, PASS. No line said twice, her memory grew 1, 2, 3, friendship 0.15, 0.25, 0.40, she shared the keepers' fires and the summit shrine. Sheet looked at by eye, she flies in, lands and takes her human form in a flash.
* Spell duel, fourth render. All checks pass, 59.3 s, 23 lines, all exchange kinds, 4.6 m closest. By eye NOT approval ready, a tree trunk fills the frame from 32.6 to 37 s and the girls are small and dim in wide shots. Fixed (the lens hides whatever stands between it and them, brighter hour), fifth render queued.
* Lake dance on the water, first run. The whole sequence ran and every check passed but one. The six lake clips were missing from this worktree (git ignored files), so the dance had no motion, and the map was still empty for a few frames after the path bake, so they never left the shore. Both fixed (probe shows the navmesh reaching the circle 34 ms after the bake), second run queued.

Built tonight
1. Soak fixes. An invite never stops a journey. The stargazing camera on slopes.
2. Highlight Shorts. The game names its best moments (first visits, dances, the lake dance, the phoenix landing, stargazing, the boat, viewer lanterns, level ups, a kept promise). Mika-Live (GoLive worktree, local commits a116bc9 and 27538e3, NOT pushed because the VR-Agent GitHub repo is public) marks them, saves OBS's replay buffer 20 s after a good one (stream encoder, off unless SHORTS_REPLAY=1), and after the stream render_day cuts the best two of the day, never the same kind, to 1080x1920 in Mika-Project › review › Shorts › date. Never uploaded. Tests pass.
3. Lake dance on the water (approved 21 Oct, never built before). On a clear night at the lake, Mika's own idea or a viewer's ask, once a night, saved. Both cast cast_water_walk (mocap, body only, fingers wait for the shared body roll in), Mika's frost and stars path and Luna's moonlight path form out to a ringed circle in the lanterns' clear lane, the navmesh is baked with it, steps glow and ring out, the lake duet (only Selwyn's six clips, the MV routine) to 月の灯り, back to land, the path fades. Whole body shots. No ordinary dance on the bank at night.
4. Viewer XP (rates proposed, need Selwyn's OK). Chat reply 2 XP to the girl who replied, once per viewer per 10 min, 30 an hour at most. Subscriber 15, member 25, Super Chat 25 + 1 per unit up to 75, viewer lantern 5, to both. Banked by the pacing like all XP. A grouped thank-you line on the overlay at most every 20 s.
5. Helping villagers (rates proposed, need Selwyn's OK). Ten requests (data › requests.json), herbs from the sanctuary garden or a spell at a named crystal or rune. Open requests are saved and pull the gathering, the spell and the road back. A kept promise pays 30 XP once, the first help for each villager 12 more. Test queued.

Deploy notes (for the day Selwyn says go, behind Be Right Back)
* Git ignored files the live folder needs. assets › audio › music › library › tsuki_no_akari › original.mp3 (copy of Mika-Project › music › tsuki_no_akari.mp3), the six lake_*.fbx in assets › animations › mixamo (from the Combat worktree), then an import.
* SHORTS_REPLAY=1 in Mika-Live's .env turns the replay buffer on (needs his OK, it changes the OBS profile's recording encoder to the stream's).

Incident
* 01.45, a headless unit check (godot --script with the project) loaded the autoloads without a test save and wrote the real save once (clock caught up 11 h, play time +90 s, no gameplay change). bak1 is the save from the end of the 22 Oct stream. Restoring it was refused by the permission check, so Selwyn has one command, bash ~/.cache/mika_qa/save_restore_20261023/restore.sh (keeps the accidental write, deletes nothing). Rule saved in memory, never --script with --path.

## Update 03.20, 23 Oct

* Lake dance on the water. Third and fourth runs pass every check (15). By eye the path was burnt white by NaN pixels at the strip edges (undefined pow and smoothstep), fixed and checked with night stills (frost cells and violet moonlight now show), and a 2.6 m rescue lens made close-ups (Luna's body counted as a wall in a two-shot), fixed.
* Spell duel, fifth render. Checks pass, brighter, the trunk is gone. By eye still tall grass round their feet and a lens inside a clump at 31.5 s, and one moment of Luna cut at the knees in a dash. Fixed (the ground mown for the duel, the lens keeps 3.5 m). Sixth render not yet made.
* Villager help test. Wenna was indoors at the test's hour; the test now places her at her 11.00 stall. Not yet rerun.
* 03.19 the NVIDIA card dropped off again (nvidia-smi finds no device, gamescope cannot open it), the same failure as 21 Oct. No GPU work possible until Selwyn reboots. Nothing was live.

## In the middle of right now (02.05, 23 Oct)

GPU queue, one at a time (proof_queue.log). Trip video at 10 fps 1280x720 (queue 9), then villager help (11), lake dance second run (12), spell duel fifth render (13). Then trip_sheets.py with TRIP_FPS=10, the sheets, videos and dialogue logs into Mika-Project › review › Test_Videos, look at every sheet by eye.

## What is left

1. Review the four runs above by eye, fix what they show.
2. 10 fps proof sheets and videos into Test_Videos.
3. Spell duel video to Selwyn for approval (only when the frames are clean).
4. Selwyn's answers. Viewer XP rates, villager XP rates, SHORTS_REPLAY, the save restore command.
5. Then tell Selwyn everything is ready. Apply to live only with his go, behind Be Right Back.
