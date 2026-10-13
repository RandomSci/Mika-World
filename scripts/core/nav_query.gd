class_name NavQuery
extends RefCounted
## Path queries with the search limit raised. Godot's NavigationServer stops a path search after
## `path_search_max_polygons` (default 4096) polygons; a large forest navmesh has 13,000+, so distant targets
## (the frontier road, the den) silently became "unreachable" through NavigationServer3D.map_get_path.
## Every path in the project goes through here or through a NavigationAgent3D with the same limit.

const MAX_POLYGONS := 200000


static func path(map: RID, from: Vector3, to: Vector3, optimize := true) -> PackedVector3Array:
	var q := NavigationPathQueryParameters3D.new()
	q.map = map
	q.start_position = from
	q.target_position = to
	q.path_search_max_polygons = MAX_POLYGONS
	q.path_postprocessing = NavigationPathQueryParameters3D.PATH_POSTPROCESSING_CORRIDORFUNNEL if optimize else NavigationPathQueryParameters3D.PATH_POSTPROCESSING_EDGECENTERED
	var r := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, r)
	return r.path


static func configure_agent(agent: NavigationAgent3D) -> void:
	agent.path_search_max_polygons = MAX_POLYGONS
