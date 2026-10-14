# Dialogue & voice latency (V3 continuation, Part 9)

Measured, not guessed. `VoiceService.latency` records every line: the time from a line being asked for to its
audio starting (`tts_ms`) and where the audio came from. `VoiceService.latency_report()` gives p50 / p95 / max and a
per-source breakdown; `describe()` carries it. `--mktest=companions` measures conversational turn-taking (line N
ends -> line N+1 starts); `--mktest=ambush` measures a fight with its standoff dialogue and barks.

## Where the time went (before)

| stage | cost | notes |
|---|---|---|
| dialogue decision (`MageTalk._phrase`, LLM) | 0 ms offline / ~1-3 s with an LLM | once per conversation, before the first line |
| shipped / session-cached identity clip | 0 ms | `assets/voice/<who>/<key>.wav`, `user://voice_cache/<identity>/` |
| live Gemini identity synthesis | **7-8 s** per line | the real bottleneck: each un-cached Mika / Luna line blocked the queue |
| Edge (rivals, NPCs) | 0.7-3.7 s per line | service warm-up dominates the first lines |
| ffmpeg post (rubberband, loudnorm) | ~0.1-0.3 s | in a worker thread |
| WAV decode + playback start | < 1 frame | `AudioStreamWAV.load_from_buffer` |

The voice queue is serial (one speaker at a time, as in life), so a 7 s synthesis became a 7 s silence in which the
characters stood waiting.

## What changed

* **The whole exchange synthesises up front.** A conversation is composed before it is spoken; `MageTalk.meet`
  now calls `VoiceService.prefetch_lines(...)`, so line N+1 is synthesised while line N plays. The ambush director
  prefetches the band's entire script when the encounter starts; NPC dialogue prefetches Mika's / Luna's answer
  while the NPC speaks.
* **Fixed lines are shipped.** Every authored line Mika and Luna say with a known text and mood (reactions, Latin,
  aftermath lines, companion warnings, the ambush exchanges and barks) is pre-rendered in their own identity
  (`tools/voice/voice_identity.py ship`) and plays with 0 ms latency, offline.
* **Combat lines have a latency budget** (`opts.max_wait`, 1.2 s for barks / warnings / aftermath calls): if the
  voice is not ready in time the line is shown as a subtitle only - the fight never waits - and the synthesis
  lands in the cache for the next time she says it.
* **No recitation in ordinary fights** (`MagicSystem`): a cast in combat stance is silent except the first of a
  fight and then at most one short word per 90 s per mage; signature moments keep their full words.
* **Runaway TTS answers are rejected** (a 2 s line returned as 100 s of babble): runtime and the ship tool both
  reject audio longer than `max(5 s, 0.12 s/char + 3 s)`.
* Synthesis metadata (provider, identity, mood) now survives the prefetch cache, so tests can prove every line was
  spoken in the character's own voice.

## Measured after (RTX 5050, live profile)

| scenario | result |
|---|---|
| Mika & Luna conversation (`--mktest=companions`) | turn gaps 333 / 400 / 600 / 867 ms; median **600 ms**, max **867 ms**; 4 of 4 follow-up lines prefetched (0 ms) |
| ambush fight (`--mktest=ambush`) | p50 **0 ms**; 25 shipped + 11 prefetched + 4 session-cached lines at 0 ms; budget drops 2 (shown as subtitles, fight continued) |
| remaining slow lines | rivals' first Edge line while the Edge service warms; a Mika/Luna line not yet shipped (daily Gemini quota) |

## Known limits

* The Gemini TTS free quota (about 100 requests/day per model, two models) bounds how many NEW lines can be voiced
  per day. Shipped and cached lines are unlimited. Three bark lines are still waiting for quota
  (`voice_identity.py ship` renders whatever is missing; re-run it).
* Free-form LLM dialogue cannot be pre-rendered; it is prefetched within the conversation, so only the first line
  of a new conversation can wait on synthesis.
