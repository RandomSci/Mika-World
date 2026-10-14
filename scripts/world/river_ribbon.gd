class_name RiverRibbon
extends RefCounted
## A river or stream surface as ONE continuous mesh (V3 continuation - the developer: "river waters doesn't have fixed
## shape like that ... make it realistic"). The old water was a row of flat rectangles, each at its own height and
## angle, so their straight edges and steps showed on the banks. This is a ribbon following the channel's centre
## line: a cross-section every couple of metres at the water level there, wide enough that its edges are buried in
## the banks - the shoreline is wherever the terrain rises out of the water, curved and irregular like a real one.
## UV.y runs along the flow (metres), UV.x across it; vertex colour alpha fades the outer rim (shader foam/depth do
## the rest).

## centre: Array[Vector3] (x, water level, z) along the flow; half_w: Array[float] half widths (metres).
static func build(centre: Array, half_w: Array, mat: Material, across := 6) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := centre.size()
	var along := 0.0
	var rows: Array = []
	for i in n:
		var p: Vector3 = centre[i]
		var a: Vector3 = centre[maxi(i - 1, 0)]
		var b: Vector3 = centre[mini(i + 1, n - 1)]
		var t := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		if t.length() < 0.01:
			t = Vector3(0, 0, 1)
		var side := Vector3(-t.z, 0, t.x)
		if i > 0:
			along += Vector2(p.x - (centre[i - 1] as Vector3).x, p.z - (centre[i - 1] as Vector3).z).length()
		var row := []
		for k in across + 1:
			var u := float(k) / across * 2.0 - 1.0              # -1 .. 1 across
			var w := float(half_w[i]) * u
			row.append([p + side * w, Vector2(w, along)])
		rows.append(row)
	for i in n - 1:
		for k in across:
			var q := [rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k]]
			for idx in [0, 2, 1, 0, 3, 2]:          # clockwise seen from above = the front face in Godot
				var v: Array = q[idx]
				st.set_normal(Vector3.UP)
				st.set_uv(v[1])
				st.add_vertex(v[0])
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The realistic forest-stream water (tea-dark in the deeps, clear over stones, grey foam, strong reflections).
static func forest_water() -> ShaderMaterial:
	var wm := Kit.shader_mat("res://shaders/nature/stylized_water.gdshader", {"noise_tex": Kit.noise(), "flow": Vector2(0.0, 0.05),
		"depth_scale": 0.9, "ripple": 0.1, "foam_width": 0.12})
	tune_forest(wm)
	return wm


## A forest river reflects the canopy, not the sky: dark green-brown sheen, clear shallows over the stones, a thin
## line of foam only where it breaks round rocks and banks.
static func tune_forest(wm: ShaderMaterial) -> void:
	for kv in [["shallow", Color(0.42, 0.46, 0.36)], ["deep", Color(0.015, 0.03, 0.022)], ["sky_tint", Color(0.16, 0.21, 0.17)],
			["foam_color", Color(0.66, 0.7, 0.66)], ["spec", 0.7], ["sheen_base", 0.05], ["sheen_fres", 0.32], ["foam_amount", 0.35],
			["foam_width", 0.12], ["shore_soft", 0.1], ["ripple", 0.1]]:
		wm.set_shader_parameter(kv[0], kv[1])
