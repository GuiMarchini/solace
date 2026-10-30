class_name WorldLayout
extends RefCounted
## Where the places of the first environment ("The Sunken Sands") are. One source of
## truth shared by the terrain (which shapes the ground under each site: the oasis basin,
## the flattened avenue) and the world builder (which puts the ruins on it), so they can
## never disagree.
##
## Seen from the spawn (0, 0) looking toward -Z: the Pilgrim's Colonnade leads from a
## gateway arch to the Watchers' ring; the Drowned Court (flooded ruins) lies ahead-right;
## sandstone mesas frame the playable sea of dunes; far away the Fallen Blade, the
## Sleeping Warden and the Spire City with its beacon pull the eye.

## The Pilgrim's Colonnade: centreline from the gateway to the Watchers (XZ), half width.
const AVENUE_A := Vector2(-4.0, -195.0)
const AVENUE_B := Vector2(52.0, -405.0)
const AVENUE_HALF_WIDTH := 13.0
## The sand is calmed (no columns) from near the start to the gateway, so the arch and
## the colonnade behind it are in sight from the first moment.
const APPROACH_A := Vector2(2.0, -40.0)
const APPROACH_HALF_WIDTH := 30.0
## The Watchers' ring.
const WATCHERS := Vector2(60.0, -432.0)

## The Drowned Court: centre, radius of open water, radius where the basin meets the dunes.
const OASIS := Vector2(255.0, -255.0)
const OASIS_WATER_RADIUS := 78.0
const OASIS_RIM_RADIUS := 150.0
## Depth of the basin floor below the water at its centre (m).
const OASIS_DEPTH := 6.0

## Sandstone mesas inside the playable square (solid, framing): centre XZ, radius, height.
const NEAR_MESAS := [
	[Vector2(-470.0, -240.0), 34.0, 62.0],
	[Vector2(-520.0, -330.0), 22.0, 44.0],
	[Vector2(500.0, 190.0), 30.0, 54.0],
	[Vector2(-400.0, 450.0), 40.0, 48.0],
	[Vector2(470.0, -520.0), 26.0, 70.0],
]
## Mesas of the far wall (scenery, beyond the playable square).
const FAR_MESAS := [
	[Vector2(-1250.0, -350.0), 260.0, 210.0],
	[Vector2(-1500.0, 300.0), 320.0, 170.0],
	[Vector2(-1050.0, -1350.0), 220.0, 260.0],
	[Vector2(1350.0, -750.0), 300.0, 230.0],
	[Vector2(1250.0, 450.0), 240.0, 160.0],
	[Vector2(1750.0, -1700.0), 380.0, 300.0],
	[Vector2(-300.0, 1600.0), 340.0, 150.0],
	[Vector2(600.0, 1500.0), 260.0, 190.0],
]

## Distant landmarks.
const FALLEN_BLADE := Vector2(-560.0, -1250.0)
const WARDEN := Vector2(760.0, -1450.0)
const SPIRE_CITY := Vector2(-300.0, -2400.0)
## A colossal aqueduct striding along the western horizon (from, to).
const FAR_AQUEDUCT := [Vector2(-1650.0, -500.0), Vector2(-1250.0, -1900.0)]
## Giant broken columns on the southern horizon (behind the start).
const FAR_COLUMNS := Vector2(450.0, 1650.0)

## The water surface height (m), set by the terrain once the basin is shaped.
static var water_level := 0.0


## Distance (m) from a point to the segment a-b.
static func segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Distance (m) from a point to the avenue's centre segment.
static func avenue_distance(p: Vector2) -> float:
	var ab := AVENUE_B - AVENUE_A
	var t := clampf((p - AVENUE_A).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(AVENUE_A + ab * t)


## True where the sword rides on the oasis water instead of the sand.
static func on_water(x: float, z: float) -> bool:
	return Vector2(x, z).distance_to(OASIS) < OASIS_RIM_RADIUS and DuneTerrain.instance != null \
			and DuneTerrain.instance.height_at(x, z) < water_level - 0.05
