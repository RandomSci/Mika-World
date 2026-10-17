#!/usr/bin/env bash
# Copies locally-licensed source assets that are NOT committed to git:
#  - Mixamo FBX animations (Adobe Mixamo terms: use in projects OK, no redistribution of raw files)
# Mika.vrm is the user's own VRoid avatar (VRM meta: allowRedistribution=true, modification allowed)
# and is committed. Re-run after a fresh clone.
set -eu
cd "$(dirname "$0")/.."
SRC="${MIXAMO_SRC:-$HOME/Downloads}"
# an existing working copy that already has the clips (e.g. the main DEV checkout): copied from there first
FROM="${MIXAMO_FROM:-$HOME/Downloads/Mika-Godot-Dev}"
mkdir -p assets/animations/mixamo assets/animations/mixamo_sword
if [ -d "$FROM/assets/animations/mixamo" ] && [ "$(cd "$FROM" && pwd)" != "$(pwd)" ]; then
  cp -n "$FROM"/assets/animations/mixamo/*.fbx assets/animations/mixamo/ 2>/dev/null || true
  cp -n "$FROM"/assets/animations/mixamo_sword/*.fbx assets/animations/mixamo_sword/ 2>/dev/null || true
  echo "Mixamo clips copied from $FROM."
  exit 0
fi
for f in "Standing Idle" "Walking" "Run Forward" "Jog Forward" "Prepare and cast" "Spell Casting" \
         "Wide Arm Spell Casting" "Standing 2H Magic Attack 01" "Standing 1H Magic Attack 03" \
         "Look Around" "Waving" "Standing React Death Forward" "Sitting Idle" \
         "Step Hip Hop Dance" "Snake Hip Hop Dance" "Booty Hip Hop Dance" "Belly Dance" "Stand To Sit" "Sit To Stand" \
         "Lying Down" "Picking Up Object Chest Level" "Picking Up_Floor" "Putting Down" "Pointing" "Arm Stretching" \
         "Neck Stretching" "Waking"; do
  n=$(echo "$f" | tr 'A-Z ' 'a-z_')
  cp -n "$SRC/$f.fbx" "assets/animations/mixamo/$n.fbx"
done
# the dance wing's party routines (the owner's Mixamo FBX, kept in Mika-Live's assets)
DANCE_SRC="${DANCE_SRC:-$HOME/Documents/Mika-Live/assets/animations/mixamo-source/dance}"
for f in "Macarena Dance" "Chicken Dance" "Ymca Dance"; do
  n=$(echo "$f" | tr 'A-Z ' 'a-z_')
  cp -n "$DANCE_SRC/$f.fbx" "assets/animations/mixamo/$n.fbx"
done
echo "Mixamo clips copied. Import settings (.fbx.import, retarget BoneMap) are tracked in git."
