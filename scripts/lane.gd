extends RefCounted
## A one-way traffic lane: a polyline on the ground that cars follow by distance travelled.

var points: PackedVector3Array
var cum: PackedFloat32Array
var length := 0.0


func _init(pts: PackedVector3Array) -> void:
	points = pts
	cum.append(0.0)
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
		cum.append(length)


func _segment(s: float) -> int:
	return clampi(cum.bsearch(s, true) - 1, 0, cum.size() - 2)


func sample(s: float) -> Vector3:
	s = clampf(s, 0.0, length)
	var i := _segment(s)
	var seg := cum[i + 1] - cum[i]
	var t := 0.0 if seg <= 0.0 else (s - cum[i]) / seg
	return points[i].lerp(points[i + 1], t)


func tangent(s: float) -> Vector3:
	var i := _segment(clampf(s, 0.0, length))
	return (points[i + 1] - points[i]).normalized()


## Distance along the lane of the closest point to p.
func project(p: Vector3) -> float:
	var best_s := 0.0
	var best_d := INF
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * t)
		if d < best_d:
			best_d = d
			best_s = cum[i] + ab.length() * t
	return best_s


## Gives the lane heights from the ground (hills, car park ramps), adding a point every couple of metres.
func drape(height_at: Callable) -> void:
	var out := PackedVector3Array()
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var n := maxi(int(ceil(Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) / 2.0)), 1)
		for k in n:
			var p := a.lerp(b, float(k) / n)
			p.y = height_at.call(p)
			out.append(p)
	var last := points[points.size() - 1]
	last.y = height_at.call(last)
	out.append(last)
	points = out
	cum = PackedFloat32Array([0.0])
	length = 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
		cum.append(length)
