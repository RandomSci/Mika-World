class_name AvatarLook
extends RefCounted
## Render and spring fixes applied to every avatar once it is set up (2026-10-19, Selwyn: "black outline shards poking
## through the outfit", "hair and cloth shattering into glassy shards", "hair and cloth rendered opaque with alpha
## scissor"):
##  - the body's inverted-hull outline is dropped: under a skin-tight bodice it poked out as black shards. The thin
##    outlines on accessories stay (a little thinner);
##  - hair and cloth surfaces render opaque with alpha scissor (the MToon cutout variant: crisp strand and lace edges,
##    no sorting);
##  - hair and cloth spring chains get more drag and stiffness and a smaller collision radius, so neighbouring
##    strands and panels move together instead of tearing the mesh between them (the chains themselves are already
##    length-locked by the VRM spring logic).

const CUTOUT_CULL_OFF := "res://addons/Godot-MToon-Shader/mtoon_cutout_cull_off.gdshader"
const CLOTH_HINTS := ["Hair", "Skirt", "Sleeve", "Bodice", "BackBow", "Bow", "Cape", "Ribbon"]


static func apply(c: Node) -> void:
	var avatar: Node = c.get("avatar")
	if avatar == null:
		return
	var cutout: Shader = load(CUTOUT_CULL_OFF)
	var outlines_off := 0
	var cut := 0
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var nm := String(m.name)
		var cloth := false
		for h in CLOTH_HINTS:
			if nm.contains(h):
				cloth = true
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si)
			if not (mat is ShaderMaterial):
				continue
			var sm := (mat as ShaderMaterial).duplicate() as ShaderMaterial
			var path := String(sm.shader.resource_path) if sm.shader else ""
			if not path.contains("mtoon"):
				continue
			if nm == "Body" and sm.next_pass:
				sm.next_pass = null
				outlines_off += 1
			elif sm.next_pass is ShaderMaterial:
				var op := (sm.next_pass as ShaderMaterial).duplicate() as ShaderMaterial
				var w = op.get_shader_parameter("_OutlineWidth")
				if w != null:
					op.set_shader_parameter("_OutlineWidth", float(w) * 0.6)
				sm.next_pass = op
			if cloth and path.ends_with("mtoon_cull_off.gdshader"):
				sm.shader = cutout
				sm.set_shader_parameter("_AlphaCutoutEnable", 1.0)
				sm.set_shader_parameter("_Cutoff", 0.5)
				cut += 1
			m.set_surface_override_material(si, sm)
	print("[look] %s: body outline off (%d), %d hair/cloth surfaces alpha-scissor" % [String(c.get("character_id")), outlines_off, cut])


## Before the avatar enters the tree (the VRM secondary builds its runtime from these in _ready).
static func calm_springs(avatar: Node) -> int:
	var sec = avatar.find_child("secondary", true, false)
	if sec == null or sec.get("spring_bones") == null:
		return 0
	var n := 0
	for sb in sec.spring_bones:
		var cm := String(sb.comment)
		if cm.begins_with("Hair") or cm.begins_with("Sleeve") or cm.begins_with("Skirt") or cm.contains("Bow") or cm.contains("Ribbon"):
			sb.set("drag_force_scale", clampf(float(sb.get("drag_force_scale")) * 1.35, 0.0, 0.92))
			sb.set("stiffness_scale", float(sb.get("stiffness_scale")) * 1.2)
			sb.set("hit_radius_scale", float(sb.get("hit_radius_scale")) * 0.8)
			n += 1
	return n
