# Mika World: Arcane Sanctuary (Godot 4 prototype)

This is a *standalone native Godot 4 project*. It does not modify the streaming app.

## Run it

1. Download and extract this ZIP somewhere (e.g. `~/Downloads/Mika-Godot-World-Proof`).
2. Install Godot 4 (standard editor from https://godotengine.org/download/linux/ ).
3. Launch from the extracted folder:

```bash
cd ~/Downloads/Mika-Godot-World-Proof
./run.sh
```

If the script cannot find Godot, download the official Godot 4 Linux editor, unpack it and run the editor executable, then import/open `project.godot` from this folder and press **F6** (current scene) or **F5** (project).

## Controls

- Left mouse drag: orbit camera.
- Scroll: zoom.
- Space: trigger a glow pulse from the spell altar.
- M: toggle demo character visibility (if present).
- R: reset camera.
- Escape: release mouse if needed.

## Add Mika's actual avatar

The included character is **only a procedural stand-in**. Your existing actual VRM model isn't in this ZIP.

For Godot, use a VRM-importer addon compatible with your Godot 4 version, or convert the VRM to a compatible `.glb` using an appropriate tool. Do not overwrite the original avatar. When a compatible file is ready, put it at the project root as `mika.glb` and open the project in the Godot editor so the asset is imported. The script attempts to load this scene automatically at next run. Depending on its original armature, orientation, and scale you may need adjustments; animation retargeting is a later task.

This is a **visual proof of concept**, not a drop-in replacement for the Three.js stage, planner, voice or OBS workflow. It uses simple procedural geometry (no commercial art assets) so it's immediately openable without asset downloads.
