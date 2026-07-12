class_name RoadGraph
extends RefCounted
## Waypoint graph along the road network. NPCs use it to commute between
## buildings without a runtime navmesh bake (cheap + deterministic on mobile).

const STEP := 12.0
const MERGE_DIST := 5.0
const LINK_DIST := 13.5

var astar := AStar3D.new()
var _next_id := 0


func build(terrain: Terrain) -> void:
	for road in MapLayout.ROADS:
		var pts: Array = road.points
		for i in pts.size() - 1:
			_add_polyline_segment(terrain, pts[i], pts[i + 1])
	# Link everything that sits close enough (joins crossings + spurs).
	var ids := astar.get_point_ids()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a := ids[i]
			var b := ids[j]
			if astar.are_points_connected(a, b):
				continue
			if astar.get_point_position(a).distance_to(astar.get_point_position(b)) <= LINK_DIST:
				astar.connect_points(a, b)


func _add_polyline_segment(terrain: Terrain, a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	var steps := maxi(int(length / STEP), 1)
	var prev_id := -1
	for s in steps + 1:
		var p := a.lerp(b, float(s) / steps)
		var pos := Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
		var id := _get_or_add(pos)
		if prev_id >= 0 and prev_id != id and not astar.are_points_connected(prev_id, id):
			astar.connect_points(prev_id, id)
		prev_id = id


func _get_or_add(pos: Vector3) -> int:
	if astar.get_point_count() > 0:
		var nearest := astar.get_closest_point(pos)
		if astar.get_point_position(nearest).distance_to(pos) < MERGE_DIST:
			return nearest
	var id := _next_id
	_next_id += 1
	astar.add_point(id, pos)
	return id


## World-space path between two arbitrary points, walking the road network.
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	if astar.get_point_count() == 0:
		result.append(to)
		return result
	var a := astar.get_closest_point(from)
	var b := astar.get_closest_point(to)
	var road_path := astar.get_point_path(a, b)
	for p in road_path:
		result.append(p)
	result.append(to)
	return result
