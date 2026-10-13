#!/usr/bin/env bash
# Copies locally-licensed source assets that are NOT committed to git:
#  - Mixamo FBX animations (Adobe Mixamo terms: use in projects OK, no redistribution of raw files)
# Mika.vrm is the user's own VRoid avatar (VRM meta: allowRedistribution=true, modification allowed)
# and is committed. Re-run after a fresh clone.
set -eu
cd "$(dirname "$0")/.."
SRC="${MIXAMO_SRC:-$HOME/Downloads}"
mkdir -p assets/animations/mixamo
for f in "Standing Idle" "Walking" "Run Forward" "Jog Forward" "Prepare and cast" "Spell Casting" \
         "Wide Arm Spell Casting" "Standing 2H Magic Attack 01" "Standing 1H Magic Attack 03" \
         "Look Around" "Waving" "Standing React Death Forward" "Sitting Idle" \
         "Step Hip Hop Dance" "Snake Hip Hop Dance" "Booty Hip Hop Dance" "Belly Dance" "Stand To Sit" "Sit To Stand" \
         "Lying Down" "Picking Up Object Chest Level" "Picking Up_Floor" "Putting Down" "Pointing" "Arm Stretching" \
         "Neck Stretching" "Waking"; do
  n=$(echo "$f" | tr 'A-Z ' 'a-z_')
  cp -n "$SRC/$f.fbx" "assets/animations/mixamo/$n.fbx"
done
echo "Mixamo clips copied. Import settings (.fbx.import, retarget BoneMap) are tracked in git."
