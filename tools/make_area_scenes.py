#!/usr/bin/env python3
"""Write scenes/areas/<area>.tscn for every area in data/world.json whose script exists."""
import json, os
root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
world = json.load(open(os.path.join(root, "data/world.json")))
scripts = {"sanctuary": "res://scripts/world/sanctuary.gd"}
for a in world["areas"]:
    s = scripts.get(a, f"res://scripts/areas/{a}.gd")
    if not os.path.exists(os.path.join(root, s[6:])):
        continue
    open(os.path.join(root, f"scenes/areas/{a}.tscn"), "w").write(
        f'[gd_scene format=3]\n\n[ext_resource type="Script" path="{s}" id="1"]\n\n[node name="{a}" type="Node3D"]\nscript = ExtResource("1")\n')
    print("scene", a)
