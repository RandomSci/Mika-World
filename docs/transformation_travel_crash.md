# Crash: area travel after a permanent transformation

Status: **open, not fixed.** Branch `transformation-outfits`, found while testing the transformation cutscene and the continuity rule (2026-10-16).
Engine: Godot v4.7.2.stable.official (ed1daf0bf), Linux x86_64, RTX 5050 laptop. Signal 11 (SIGSEGV).

## What happens

A character takes a **permanent** transformation (her outfit changes, `TransformationDirector._play_sequence` writes her new appearance to her mind and records the activity). Then Mika fast-travels to another area: sanctuary → whispering woods → highland path → village. Right after the journey's last walk, at Mika's `navigate_to ... arrived (0.4 m from target)` event in the village, Godot crashes. In every run it is the same moment, the next thing after that event, before `journey_finished` is printed.

It is **not** caused by the new cutscene player: the **legacy** transformation path (`--legacy-transform`, the old director code) crashes in exactly the same place with an identical backtrace.

## How often

All runs used `--profile=stream --luna --brain --dev-fast-travel` with the `--tfcontinuity` test (`scripts/tests/tf_continuity_test.gd`), unless noted. "Permanent transformation then travel" is the trigger case; the other rows are controls.

| Run | What it did | Crashed |
|---|---|---|
| run3 | cutscene, Luna L10 at the sanctuary (permanent), then travel | **yes** |
| run4 | same | **yes** |
| run5 | same (brains held during the test's travel) | **yes** |
| legacy | **legacy director path** (`--legacy-transform`), Luna L10, then travel | **yes** |
| skip_record | director's activity record skipped (appearance still saved), then travel | **yes** |
| final3 | cutscene, clean (no debug flags), then travel | **yes** |
| verbose | same as final3 with `--verbose` | no |
| skip_appearance | appearance save skipped, then travel | no |
| skip_signal | director's `finished` signal skipped, then travel (3 places) | no |
| final | cutscene, clean, 3 places and two travels | no |
| final2 | cutscene, clean | no crash; the run ended early (exit 0) mid-place-2, cause unknown |
| *controls* | | |
| dry | brains on, travel, **no** transformation | no |
| swap_same | bare `swap_avatar` to the outfit she already wore, then travel | no |
| swap_target | bare `swap_avatar` to her L10 outfit (no director, no progression), then travel | no |
| preview | cutscene in **preview** mode (no progression change), then travel | no |
| direct | `TransformationSequence.play` called directly, bypassing the director, then travel | no |
| run2 | **brains off**, permanent transformations, travels | no |

**6 of 11** permanent-transformation-then-travel runs crashed. 0 of 6 controls crashed.

The single-run bisects (`skip_*`) are not conclusive on their own. The crash is intermittent: `verbose` and `final` have every flag of the crashing runs and did not crash.

## Backtraces

The full backtraces are in `docs/crash_evidence/transformation_travel/<run>.txt`, each with the 40 log lines before the crash. Every one of the six is **identical at every engine offset**. Only the libc load address differs, which is ASLR:

```
[1]  libc.so.6+3fd70        (signal handler)
[2]  main+42ada17           <- faulting frame
[3]  main+6f6c08
[4]  main+5b9ec4  \
[5]  main+5be642   |
[6]  main+5d4363   |  a block of 8 frames ...
[7]  main+44f714b  |
[8]  main+428c83d  |
[9]  main+428cbc4  |
[10] main+457f6e4 /
[11] main+6f77bd
[12] main+5b9ec4  \
...                |  ... repeated once more (nested)
[18] main+457f6e4 /
[19] main+2751224
[20] main+1661f9
[21] main+2c157
[22] libc.so.6+29ca8        (__libc_start_main)
[23] libc.so.6+29d65
[24] main+8a6da
```

No symbols are available: the official build is stripped. **No core dumps exist** either: `ulimit -c` is 0, the kernel core pattern is a plain `core`, and `coredumpctl` and systemd-coredump are not installed. So there is no `coredumpctl info` to attach.

## Reading the stack

The stack is shallow, at 24 frames from `main`. So this is **not** a deep scene-tree notification or a stack overflow. From the main loop (frames 19-21), one engine call path is entered twice, nested: frames 4-10 and 12-18 are the same seven functions. Each time it ends in a frame that differs (6f6c08 / 6f77bd), as if one handler calls another. The innermost one faults at `42ada17`.

That shape fits **a GDScript callback run from the main loop that calls another GDScript function, which then makes an engine call on a dead object**. Examples: a signal emitted in a handler of another signal, or a deferred call into a handler. The trigger is Mika's `action_finished` (navigate_to arrived) when her journey ends.

It does **not** look like a SkeletonModifier3D or spring-bone update crashing inside the skeleton or physics update. Those would show the skeleton and physics process path, not two nested script-call blocks.

## Best guess at the cause

**Something keeps a reference to a node of the outfit that was replaced, and touches it from a script handler when the journey ends.**

1. `WorldCharacter.swap_avatar()` `queue_free()`s the old avatar: the whole VRM, its Skeleton3D, MeshInstances, spring bones and the BoneAttachments for hands, chest and head are rebuilt for the new one.
2. A system that caches nodes from inside the avatar keeps the old ones. That system only refreshes on certain events. Candidates:
   - look-at or attention targets pointing at the other character's head;
   - the camera director's conversation or subject parts (`_conversation`, head targets);
   - `ObjectHandler` / `FootGuard` / `TeleportGuard` state;
   - the action bridge's observation builder (nearby lists, camera block);
   - any `Dictionary` / `Array` holding a node of the old avatar.
3. When Mika's journey ends, the `action_finished` / journey handlers run. One of them dereferences that stale node. A freed object reached through a typed or ptrcall path, or held inside a container, can crash rather than raise the usual "previously freed" script error. Area streaming has also just freed the old area's nodes.

Why only the **permanent** path, and only intermittently? The director's permanent branch writes `progress["appearance"]`, records the activity and emits `finished`. Those feed the overlay, the bridge and the planners, which then hold onto that moment's character state. Preview and bare swaps skip all of it. Whether the stale reference is still around when the journey ends depends on frame timing; adding `--verbose` was enough to hide it.

A **spring bone / skeleton** variant of the same idea is less likely but not ruled out: spring colliders or a modifier still pointing at the freed old Skeleton3D while the new area loads. The stack shape argues against it.

## Next steps (not done yet; the developer asked to pause)

- **Get symbols:**
  - build Godot 4.7.2 at `ed1daf0bf` with `debug_symbols=yes` (or a `template_debug` build), or use the official debug-symbols package if there is one;
  - run the same test under `gdb` with `ulimit -c unlimited`, so the faulting function is named;
  - then map `main+42ada17`, `6f6c08` and `6f77bd`.
- **Breadcrumbs:** log entry and exit of every handler connected to `WorldCharacter.action_finished`, `TravelController.journey_event` and `TransformationDirector.finished`. The last line before the crash names the handler.
- **Audit avatar-node caches:** after `swap_avatar`, emit `avatar_swapped` (it exists) and make every holder of avatar nodes re-resolve or drop them, guarding the rest with `is_instance_valid`.
- **Re-test:** 10 runs of "permanent transformation, then travel", which should give 0 crashes.

## Separate, unrelated crash seen once

`~/.cache/mika_qa/tfseq_choreo/dbg2`, at quit. A debug-only test set `layers = 0` on the wing meshes during the old real-time sequence, which has since been removed. It has a different backtrace and is not part of this issue.
