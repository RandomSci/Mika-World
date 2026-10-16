# World look rules

Rules every scene, camera and cinematic in Mika World follows. Newer rules from the developer override older notes.

## 1. Camera: no close-ups, ever (permanent, 2026-10-16)

The developer's rule, for every scene, forever:

- **Never show close-ups of Mika or Luna.** No face shots, and no shot where a face fills more than **10% of the
  frame height**.
- **Only wide and medium-wide shots.** Full body, or at least knees up, always with the environment around them.
- **No face-focus shots and no face push-ins.**
- Scope in this branch: normal gameplay cameras (the director, combat framing, the follow camera) and the test scenes.
  The transformation sequences belong to the outfit session's system (Mika-Godot-Dev-L1Outfit), which already applies
  the rule there with full-body and silhouette shots. This branch does not touch them.

How the code keeps it:

| Where | What |
|---|---|
| `scripts/camera/framing_rule.gd` (`FramingRule`) | The rule in one place: `MAX_FACE_FRAC = 0.10` of the frame height, a head height of 0.26 m (chin to the top of the hair or ears, a margin over the face itself). `min_distance(fov)` gives the closest a lens may be. `enforce()` pulls a shot back along a clear line, opens the lens only as a last resort, and turns any face aim point into a chest aim point. |
| `scripts/camera/framing_guard.gd` (`FramingGuard`) | Last line of defence. It runs after every camera script, checks the live camera against every mage's head each frame, corrects it, and counts the corrections (`hits`, `worst_frac`) so QA can fail a scene whose own cameras break the rule. Installed in `main.gd`, Moonbloom Field and Starfall Hill. It leaves the transformation camera (`TransformCamera`) alone. |
| `CameraDirector._apply()` | Every director frame (chase, conversation, activity, dance, signature casts, fights, stargazing) goes through `FramingRule.enforce()`. The `face_close` and `hands` shots were replaced by full-body, medium-wide and low-silhouette shots. The conversation shot / reverse shot onto a speaker's face is gone (medium-wide two-shot only), the book close-up is now a medium-wide three-quarter, and the lying-down shot is wide. |
| `CombatFraming` | The "gather" beat's face push-in is now a medium-wide drift on her whole body, her hands and the sigil. |
| Scene QA (`--moonbloom-qa`, `--starfall-qa`) | Reports `largest_face_frac_of_frame`, `guard_corrections` and `rule_ok` per shot. |

When writing a new camera: frame knees-up or wider, aim at the chest (never the face), and run it through
`FramingRule.enforce()`. Check `rule_ok` in QA before showing anything.

Not shown to viewers and so left as they are (they verify the face rig itself): the face checks inside test
harnesses (`scripts/tests/*`, `scripts/face_test.gd`, the avatar lab's `faces` mode). Their images stay in QA output.

## 2. Characters

- Skin stays bright and clean, close to its real tone. Grade the environment, not the skin.
- No hard cast shadows on faces (`profile.face.receive_shadow`, default 0.15). Shade colours are light lavender,
  never dark grey.
- Eyes have catchlights. Faces are never frozen: blinks, soft moods, small head turns.

## 3. Test scenes

- Run only with a test flag (`--fresh` plus a `--save-path=user://test_*.json`), so no save is ever touched.
- Hold a steady 30 fps on the RTX 5050. Report FPS, draw calls, VRAM and GPU ms per shot.
- Record and look at every shot before showing it. Keep the Godot window uncovered while measuring, because GNOME
  throttles covered windows.
