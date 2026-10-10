extends Node2D
# Campus Rush v4 - find your way from HOME to COLLEGE through the city.
# Route: Home -> LEFT at the junction -> RIGHT at the Cake Shop -> cross the HIGHWAY
#        (obey the signal!) -> STRAIGHT past DMart -> RIGHT at Burger King -> COLLEGE.
# Controls: WASD / Arrow keys. R or Enter to restart / next level.

const W := 1280
const H := 720
const WORLD_W := 2000
const WORLD_H := 1700
const PLAYER_SIZE := Vector2(22, 22)
const PLAYER_SPEED := 190.0
const START_TIME := 110.0
const M_PER_PX := 0.5                     # 1 pixel = 0.5 metre (route is ~1500 m)

const START_POS := Vector2(1000, 1610)
const ROUTE := [Vector2(1000, 1610), Vector2(1000, 1300), Vector2(500, 1300), Vector2(500, 300), Vector2(1680, 300)]
const WIN_ZONE := Rect2(1640, 250, 80, 28)

# Walkable streets (pavements). The player cannot leave these rectangles.
const CORRIDORS := [
	Rect2(950, 1250, 100, 390),    # A: home street
	Rect2(450, 1250, 600, 100),    # B: junction -> cake shop
	Rect2(450, 250, 100, 1100),    # C: cake shop -> burger king (crosses the highway)
	Rect2(450, 250, 1300, 100),    # D: burger king -> college
	Rect2(1000, 1250, 300, 100),   # temple street (dead end)
	Rect2(500, 710, 300, 100),     # park street (dead end)
	Rect2(250, 250, 200, 100),     # library street (dead end)
]
const DEAD_ENDS := [Rect2(1200, 1250, 100, 100), Rect2(700, 710, 100, 100), Rect2(250, 250, 100, 100)]

# The highway: 4 lanes, crossed by street C. Controlled by a traffic signal.
const HIGHWAY := Rect2(0, 900, 2000, 160)
const LANE_TOPS := [900, 940, 980, 1020]
const LANE_DIRS := [1, 1, -1, -1]
const CROSS_RECT := Rect2(450, 900, 100, 160)
const STOP_E := 425.0                     # eastbound cars stop with their front before this x
const STOP_W := 575.0                     # westbound cars stop with their front after this x
const GREEN_T := 6.0
const YELLOW_T := 1.5
const RED_T := 7.0                        # cars stopped = pedestrians may WALK

# Route checkpoints (reached in order) and the instruction shown for each step
const CHECKPOINTS := [Vector2(800, 1300), Vector2(500, 1200), Vector2(500, 820), Vector2(500, 520), Vector2(700, 300)]
const STEP_TEXTS := [
	"Leave home, walk to the junction and turn LEFT.",
	"Walk to the Cake Shop and turn RIGHT.",
	"Cross the HIGHWAY - wait for the WALK signal!",
	"Go STRAIGHT past DMart.",
	"Turn RIGHT at Burger King.",
	"Keep walking - the college is ahead!",
]

const VEHICLE_TYPES := ["car_red", "car_blue", "car_green", "bus", "auto"]
const PED_TYPES := ["ped_red", "ped_green"]
const PLANT_TYPES := ["tree", "bush", "pot"]
const SOUNDS := ["honk", "screech", "crash", "ding", "beep", "bump", "wrong", "win"]
const QUOTES := [
	"Who waits for the red light?",
	"The attendance sheet will not forgive you.",
	"Bro, the zebra crossing was right there.",
	"Next time, leave home 10 minutes earlier.",
	"Traffic 1 - Student 0.",
	"Your bunk plan has failed.",
]

var rng := RandomNumberGenerator.new()
var tex := {}                             # sprites by name
var sfx := {}                             # sound players by name
var buildings: Array = []                 # landmarks: {tex, pos, label, lpos, lsize, lcolor}
var plants: Array = []                    # {x, y, tex} (scenery)
var manholes: Array = []                  # Array of Rect2
var vehicles: Array = []                  # {rect, dir, cruise, spd, tex, lane}
var pedestrians: Array = []               # {axis, fixed, t, a, b, dir, speed, tex, phase}
var bubbles: Array = []                   # honk speech bubbles {pos, t}

var state := "play"                       # play | dead | win | timeout
var level := 1
var time_left := START_TIME
var player := START_POS
var step := 0                             # which route instruction we are on
var quote := ""
var cam_off := Vector2.ZERO
var game_time := 0.0
var signal_time := 0.0
var light := "green"
var close_call_timer := 0.0
var screech_cooldown := 0.0
var bump_cooldown := 0.0
var bump_timer := 0.0
var honk_timer := 5.0
var honk_cooldown := 0.0
var beep_timer := 0.0
var wrong_timer := 0.0
var in_dead_end := false


func _ready() -> void:
	rng.randomize()
	var names: Array = ["player", "home", "college", "manhole", "cake_shop", "dmart", "burger_king", "temple", "park", "library", "turn_sign"] + VEHICLE_TYPES + PED_TYPES + PLANT_TYPES
	for n in names:
		tex[n] = load("res://assets/%s.png" % n)
	for n in SOUNDS:
		var ap := AudioStreamPlayer.new()
		ap.stream = load("res://assets/sounds/%s.wav" % n)
		add_child(ap)
		sfx[n] = ap
	build_buildings()
	build_plants()
	start_level()


func play_sfx(n: String) -> void:
	if sfx.has(n):
		sfx[n].play()


func build_buildings() -> void:
	buildings = [
		{"tex": "home", "pos": Vector2(915, 1642), "label": "HOME", "lpos": Vector2(66, 34), "lsize": 11, "lcolor": Color("5a3a22")},
		{"tex": "cake_shop", "pos": Vector2(300, 1260), "label": "CAKE SHOP", "lpos": Vector2(24, 15), "lsize": 11, "lcolor": Color("6e323c")},
		{"tex": "dmart", "pos": Vector2(250, 680), "label": "DMART", "lpos": Vector2(62, 22), "lsize": 20, "lcolor": Color.WHITE},
		{"tex": "burger_king", "pos": Vector2(440, 160), "label": "BURGER KING", "lpos": Vector2(32, 18), "lsize": 10, "lcolor": Color.WHITE},
		{"tex": "college", "pos": Vector2(1490, 196), "label": "COLLEGE", "lpos": Vector2(162, 18), "lsize": 12, "lcolor": Color.WHITE},
		{"tex": "temple", "pos": Vector2(1300, 1260), "label": "TEMPLE", "lpos": Vector2(36, 86), "lsize": 10, "lcolor": Color("333333")},
		{"tex": "park", "pos": Vector2(800, 715), "label": "PARK", "lpos": Vector2(46, 83), "lsize": 11, "lcolor": Color.WHITE},
		{"tex": "library", "pos": Vector2(130, 255), "label": "LIBRARY", "lpos": Vector2(40, 32), "lsize": 10, "lcolor": Color("7a3a2e")},
	]


func start_level() -> void:
	state = "play"
	time_left = START_TIME
	player = START_POS
	step = 0
	signal_time = rng.randf_range(0.0, GREEN_T + YELLOW_T + RED_T)
	light = light_state()
	close_call_timer = 0.0
	screech_cooldown = 0.0
	bump_cooldown = 0.0
	bump_timer = 0.0
	honk_timer = rng.randf_range(3.0, 6.0)
	honk_cooldown = 0.0
	wrong_timer = 0.0
	in_dead_end = false
	bubbles.clear()
	build_vehicles()
	build_manholes()
	build_pedestrians()


# ---------- world building ----------

func build_plants() -> void:
	plants.clear()
	var blockers: Array = []
	for c in CORRIDORS:
		blockers.append(c.grow(4))
	blockers.append(HIGHWAY.grow(6))
	for b in buildings:
		var bt: Texture2D = tex[b["tex"]]
		blockers.append(Rect2(b["pos"], Vector2(bt.get_width(), bt.get_height())).grow(8))
	for c in CORRIDORS:
		if c.size.x > c.size.y:
			var x := c.position.x + 30.0
			while x < c.end.x - 20.0:
				try_plant(Vector2(x, c.position.y - 38.0), blockers)
				try_plant(Vector2(x + 60.0, c.end.y + 38.0), blockers)
				x += 120.0
		else:
			var y := c.position.y + 30.0
			while y < c.end.y - 20.0:
				try_plant(Vector2(c.position.x - 28.0, y), blockers)
				try_plant(Vector2(c.end.x + 28.0, y + 60.0), blockers)
				y += 120.0
	plants.sort_custom(func(a, b): return a["y"] < b["y"])


func try_plant(center: Vector2, blockers: Array) -> void:
	var ptype: String = PLANT_TYPES[rng.randi() % PLANT_TYPES.size()]
	var t: Texture2D = tex[ptype]
	var r := Rect2(center - Vector2(t.get_width(), t.get_height()) / 2.0, Vector2(t.get_width(), t.get_height()))
	if r.position.x < 0 or r.position.y < 0 or r.end.x > WORLD_W or r.end.y > WORLD_H:
		return
	for bl in blockers:
		if r.intersects(bl):
			return
	for p in plants:
		if abs(p["x"] - center.x) < 40.0 and abs(p["y"] - center.y) < 40.0:
			return
	plants.append({"x": center.x, "y": center.y, "tex": ptype})


func build_manholes() -> void:
	manholes.clear()
	var tries := 0
	while manholes.size() < 8 + level and tries < 300:
		tries += 1
		var c: Rect2 = CORRIDORS[rng.randi() % 4]       # only on the main route streets
		var p := Vector2(rng.randf_range(c.position.x + 24.0, c.end.x - 56.0), rng.randf_range(c.position.y + 24.0, c.end.y - 56.0))
		var r := Rect2(p, Vector2(32, 32))
		if HIGHWAY.grow(40).intersects(r) or p.distance_to(START_POS) < 160.0:
			continue
		var ok := true
		for m in manholes:
			if m.position.distance_to(p) < 70.0:
				ok = false
		for cp in CHECKPOINTS:
			if cp.distance_to(p) < 60.0:
				ok = false
		if ok:
			manholes.append(r)


func build_vehicles() -> void:
	vehicles.clear()
	var speed_scale := 1.0 + 0.12 * (level - 1)
	for lane in LANE_TOPS.size():
		var lane_speed := rng.randf_range(130.0, 200.0) * speed_scale
		for j in 6:
			var vname: String = VEHICLE_TYPES[rng.randi() % VEHICLE_TYPES.size()]
			var t: Texture2D = tex[vname]
			var size := Vector2(t.get_width(), t.get_height())
			var x := (float(j) / 6.0) * WORLD_W + rng.randf_range(-40.0, 40.0)
			var rect := Rect2(Vector2(x, LANE_TOPS[lane] + (40.0 - size.y) / 2.0), size)
			var cruise := lane_speed * rng.randf_range(0.92, 1.08)
			vehicles.append({"rect": rect, "dir": float(LANE_DIRS[lane]), "cruise": cruise, "spd": cruise, "tex": vname, "lane": lane})


func build_pedestrians() -> void:
	pedestrians.clear()
	# [axis, fixed coordinate, min, max]  - each person walks between two turning points
	var paths := [
		["y", 975.0, 1380.0, 1560.0],
		["x", 1325.0, 620.0, 880.0],
		["y", 478.0, 1100.0, 1230.0],
		["y", 525.0, 770.0, 870.0],
		["y", 475.0, 540.0, 670.0],
		["x", 322.0, 760.0, 1000.0],
		["x", 278.0, 1150.0, 1420.0],
	]
	for pa in paths:
		pedestrians.append({
			"axis": pa[0], "fixed": pa[1], "a": pa[2], "b": pa[3],
			"t": rng.randf_range(pa[2], pa[3]),
			"dir": 1.0 if rng.randf() < 0.5 else -1.0,
			"speed": rng.randf_range(40.0, 70.0),
			"tex": PED_TYPES[rng.randi() % PED_TYPES.size()],
			"phase": rng.randf_range(0.0, 6.28),
		})


func ped_pos(p: Dictionary) -> Vector2:
	if p["axis"] == "x":
		return Vector2(p["t"], p["fixed"])
	return Vector2(p["fixed"], p["t"])


func ped_rect(p: Dictionary) -> Rect2:
	return Rect2(ped_pos(p) - Vector2(9, 12), Vector2(18, 26))


# ---------- signal ----------

func light_state() -> String:
	var t := fmod(signal_time, GREEN_T + YELLOW_T + RED_T)
	if t < GREEN_T:
		return "green"
	elif t < GREEN_T + YELLOW_T:
		return "yellow"
	return "red"


# ---------- main loop ----------

func _process(delta: float) -> void:
	game_time += delta
	if state == "play":
		signal_time += delta
		var new_light := light_state()
		if new_light == "red" and light != "red":
			play_sfx("ding")                      # the signal turned red for cars: WALK
		light = new_light
		update_player(delta)
		update_vehicles(delta)
		update_pedestrians(delta)
		update_honks(delta)
		update_signal_beeps(delta)
		check_collisions()
		time_left -= delta
		if time_left <= 0.0 and state == "play":
			state = "timeout"
			quote = "Late again. The gate is already closed."
	else:
		if Input.is_physical_key_pressed(KEY_R) or Input.is_physical_key_pressed(KEY_ENTER):
			if state == "win":
				level += 1
			else:
				level = 1
			start_level()
	close_call_timer = max(0.0, close_call_timer - delta)
	screech_cooldown = max(0.0, screech_cooldown - delta)
	bump_cooldown = max(0.0, bump_cooldown - delta)
	bump_timer = max(0.0, bump_timer - delta)
	honk_cooldown = max(0.0, honk_cooldown - delta)
	wrong_timer = max(0.0, wrong_timer - delta)
	for b in bubbles:
		b["t"] -= delta
	bubbles = bubbles.filter(func(b): return b["t"] > 0.0)
	cam_off = Vector2(clampf(player.x - W / 2.0, 0.0, float(WORLD_W - W)), clampf(player.y - H / 2.0, 0.0, float(WORLD_H - H)))
	queue_redraw()


func in_corridor(pt: Vector2) -> bool:
	for c in CORRIDORS:
		if c.has_point(pt):
			return true
	return false


func can_stand(pos: Vector2) -> bool:
	var r := Rect2(pos - PLAYER_SIZE / 2.0, PLAYER_SIZE).grow(-2.0)
	return in_corridor(r.position) and in_corridor(Vector2(r.end.x, r.position.y)) and in_corridor(Vector2(r.position.x, r.end.y)) and in_corridor(r.end)


func update_player(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	var move := dir.normalized() * PLAYER_SPEED * delta
	# move on each axis separately so you can slide along walls
	var nx := player + Vector2(move.x, 0.0)
	if can_stand(nx):
		player = nx
	var ny := player + Vector2(0.0, move.y)
	if can_stand(ny):
		player = ny


func update_vehicles(delta: float) -> void:
	for v in vehicles:
		var r: Rect2 = v["rect"]
		var dir: float = v["dir"]
		var target: float = v["cruise"]
		# 1. traffic signal: stop before the crossing when it is not green
		if light != "green":
			var front := r.end.x if dir > 0.0 else r.position.x
			var to_line := (STOP_E - front) if dir > 0.0 else (front - STOP_W)
			var min_dist := 60.0 if light == "yellow" else -6.0     # on yellow, close cars may still pass
			if to_line > min_dist and to_line < 300.0:
				target = minf(target, maxf(0.0, to_line * 2.5))
		# 2. keep a gap to the car in front
		var gap := 9999.0
		var ahead_spd := 0.0
		for o in vehicles:
			if o != v and o["lane"] == v["lane"]:
				var orect: Rect2 = o["rect"]
				var g := (orect.position.x - r.end.x) if dir > 0.0 else (r.position.x - orect.end.x)
				if g >= 0.0 and g < gap:
					gap = g
					ahead_spd = o["spd"]
		if gap < 120.0:
			target = minf(target, maxf(0.0, (gap - 34.0) * 3.0))
		# 3. accelerate / brake smoothly
		var spd: float = v["spd"]
		if spd < target:
			spd = minf(target, spd + 220.0 * delta)
		else:
			spd = maxf(target, spd - 450.0 * delta)
		v["spd"] = spd
		r.position.x += dir * spd * delta
		# 4. wrap around the world
		if dir > 0.0 and r.position.x > WORLD_W + 60:
			var sx := -r.size.x - 40.0
			for o in vehicles:
				if o != v and o["lane"] == v["lane"]:
					sx = minf(sx, (o["rect"] as Rect2).position.x - r.size.x - 80.0)
			r.position.x = sx
		elif dir < 0.0 and r.end.x < -60:
			var sx2 := float(WORLD_W) + 40.0
			for o in vehicles:
				if o != v and o["lane"] == v["lane"]:
					sx2 = maxf(sx2, (o["rect"] as Rect2).end.x + 80.0)
			r.position.x = sx2
		v["rect"] = r


func update_pedestrians(delta: float) -> void:
	for p in pedestrians:
		p["t"] += p["dir"] * p["speed"] * delta
		if p["t"] > p["b"]:            # reached a turning point: turn around
			p["t"] = p["b"]
			p["dir"] = -1.0
		elif p["t"] < p["a"]:
			p["t"] = p["a"]
			p["dir"] = 1.0


func update_honks(delta: float) -> void:
	honk_timer -= delta
	if honk_timer <= 0.0:
		var best = null
		var best_d := 650.0
		for v in vehicles:
			var c: Vector2 = (v["rect"] as Rect2).get_center()
			var d := c.distance_to(player)
			if d < best_d and v["spd"] > 20.0:
				best_d = d
				best = v
		if best != null:
			honk_from(best)
			honk_timer = rng.randf_range(4.0, 9.0)
		else:
			honk_timer = 1.5
	# angry honks when you walk across during a green light
	if honk_cooldown <= 0.0 and HIGHWAY.has_point(player) and light == "green":
		for v in vehicles:
			var c2: Vector2 = (v["rect"] as Rect2).get_center()
			if c2.distance_to(player) < 320.0 and v["spd"] > 20.0:
				honk_from(v)
				break


func honk_from(v: Dictionary) -> void:
	play_sfx("honk")
	honk_cooldown = 1.5
	var r: Rect2 = v["rect"]
	bubbles.append({"pos": Vector2(r.get_center().x - 26.0, r.position.y - 4.0), "t": 0.8})


func update_signal_beeps(delta: float) -> void:
	# pedestrian signal ticks while it is safe to walk and you are near
	if light == "red" and player.distance_to(CROSS_RECT.get_center()) < 450.0:
		beep_timer -= delta
		if beep_timer <= 0.0:
			play_sfx("beep")
			beep_timer = 0.6
	else:
		beep_timer = 0.0


func check_collisions() -> void:
	var pr := Rect2(player - PLAYER_SIZE / 2.0, PLAYER_SIZE)
	for v in vehicles:
		var r: Rect2 = v["rect"]
		if pr.intersects(r.grow(-3)):
			die()
			return
		if v["spd"] > 20.0 and pr.grow(16).intersects(r) and screech_cooldown <= 0.0:
			close_call_timer = 0.8
			screech_cooldown = 1.2
			play_sfx("screech")
			if honk_cooldown <= 0.0:
				honk_from(v)
	for m in manholes:
		if pr.intersects(m.grow(-6)):
			die()
			return
	for p in pedestrians:
		if bump_cooldown <= 0.0 and pr.intersects(ped_rect(p)):
			time_left -= 2.0
			bump_cooldown = 1.0
			bump_timer = 1.0
			play_sfx("bump")
	# route checkpoints, in order
	if step < CHECKPOINTS.size() and player.distance_to(CHECKPOINTS[step]) < 55.0:
		step += 1
		play_sfx("ding")
	# dead ends
	var inside := false
	for de in DEAD_ENDS:
		if de.has_point(player):
			inside = true
	if inside and not in_dead_end:
		play_sfx("wrong")
		wrong_timer = 2.5
	in_dead_end = inside
	# the college gate
	if WIN_ZONE.has_point(player):
		state = "win"
		play_sfx("win")


func die() -> void:
	state = "dead"
	quote = QUOTES[rng.randi() % QUOTES.size()]
	play_sfx("crash")


func distance_left_m() -> int:
	var best_d := 1.0e9
	var best_rem := 0.0
	for i in ROUTE.size() - 1:
		var a: Vector2 = ROUTE[i]
		var b: Vector2 = ROUTE[i + 1]
		var q := Geometry2D.get_closest_point_to_segment(player, a, b)
		var d := player.distance_to(q)
		if d < best_d:
			best_d = d
			var rem := q.distance_to(b)
			for j in range(i + 1, ROUTE.size() - 1):
				rem += (ROUTE[j] as Vector2).distance_to(ROUTE[j + 1])
			best_rem = rem
	return int(round(best_rem * M_PER_PX))


# ---------- drawing ----------

func to_screen(p: Vector2) -> Vector2:
	return p - cam_off


func rect_screen(r: Rect2) -> Rect2:
	return Rect2(r.position - cam_off, r.size)


func tex_at(name: String, pos: Vector2, flip: bool = false, tint: Color = Color.WHITE) -> void:
	var t: Texture2D = tex[name]
	var sp := pos - cam_off
	if sp.x > W + 60 or sp.y > H + 60 or sp.x + t.get_width() < -60 or sp.y + t.get_height() < -60:
		return
	if flip:
		draw_set_transform(Vector2(sp.x + t.get_width(), sp.y), 0.0, Vector2(-1, 1))
		draw_texture(t, Vector2.ZERO, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture(t, sp, tint)


func text_at(msg: String, pos: Vector2, size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, pos - cam_off, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func text_hud(msg: String, pos: Vector2, size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, pos, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func draw_traffic_light(pos: Vector2) -> void:
	draw_rect(rect_screen(Rect2(pos.x + 8, pos.y + 40, 4, 22)), Color("555555"))
	draw_rect(rect_screen(Rect2(pos.x, pos.y, 20, 42)), Color("222222"))
	var red_on := light == "red"
	var yel_on := light == "yellow"
	var grn_on := light == "green"
	draw_circle(to_screen(pos + Vector2(10, 8)), 5.0, Color("ff3b30") if red_on else Color("4a1a1a"))
	draw_circle(to_screen(pos + Vector2(10, 21)), 5.0, Color("ffd60a") if yel_on else Color("4a4210"))
	draw_circle(to_screen(pos + Vector2(10, 34)), 5.0, Color("30d158") if grn_on else Color("12361c"))


func _draw() -> void:
	# 1. grass with a faint grid so you can see the map scroll
	draw_rect(Rect2(0, 0, W, H), Color("78b66b"))
	for gx in range(0, WORLD_W + 1, 100):
		draw_line(to_screen(Vector2(gx, 0)), to_screen(Vector2(gx, WORLD_H)), Color(0, 0, 0, 0.05), 1.0)
	for gy in range(0, WORLD_H + 1, 100):
		draw_line(to_screen(Vector2(0, gy)), to_screen(Vector2(WORLD_W, gy)), Color(0, 0, 0, 0.05), 1.0)
	# 2. streets (pavements)
	for c in CORRIDORS:
		draw_rect(rect_screen(c), Color("b8b2a7"))
		draw_rect(rect_screen(c), Color("8f8a80"), false, 3.0)
	# 3. highway + lane markings + zebra crossing
	draw_rect(rect_screen(HIGHWAY), Color("3b3f46"))
	draw_rect(rect_screen(Rect2(0, 900, WORLD_W, 3)), Color.WHITE)
	draw_rect(rect_screen(Rect2(0, 1057, WORLD_W, 3)), Color.WHITE)
	draw_rect(rect_screen(Rect2(0, 979, WORLD_W, 4)), Color("f4c430"))
	for x in range(0, WORLD_W, 60):
		draw_rect(rect_screen(Rect2(x, 939, 30, 2)), Color(1, 1, 1, 0.5))
		draw_rect(rect_screen(Rect2(x, 1019, 30, 2)), Color(1, 1, 1, 0.5))
	var zy := 906
	while zy < 1056:
		draw_rect(rect_screen(Rect2(CROSS_RECT.position.x + 8, zy, CROSS_RECT.size.x - 16, 10)), Color(1, 1, 1, 0.85))
		zy += 20
	# stop lines
	draw_rect(rect_screen(Rect2(STOP_E, 900, 4, 80)), Color.WHITE)
	draw_rect(rect_screen(Rect2(STOP_W, 980, 4, 80)), Color.WHITE)
	# 4. landmarks
	for b in buildings:
		tex_at(b["tex"], b["pos"])
		text_at(b["label"], (b["pos"] as Vector2) + (b["lpos"] as Vector2), b["lsize"], b["lcolor"])
	# dead end signs
	for de in DEAD_ENDS:
		text_at("DEAD END", Vector2(de.position.x + 14, de.position.y + 54), 14, Color("b00020"))
	# 5. plants
	for pl in plants:
		var pt: Texture2D = tex[pl["tex"]]
		tex_at(pl["tex"], Vector2(pl["x"] - pt.get_width() / 2.0, pl["y"] - pt.get_height() / 2.0))
	# 6. turning-point signs and manholes
	for p in pedestrians:
		var a_pos := Vector2(p["a"], p["fixed"]) if p["axis"] == "x" else Vector2(p["fixed"], p["a"])
		var b_pos := Vector2(p["b"], p["fixed"]) if p["axis"] == "x" else Vector2(p["fixed"], p["b"])
		tex_at("turn_sign", a_pos + Vector2(-11, -34))
		tex_at("turn_sign", b_pos + Vector2(-11, -34))
	for m in manholes:
		tex_at("manhole", m.position)
	# 7. traffic lights and the WALK / WAIT board
	draw_traffic_light(Vector2(400, 860))
	draw_traffic_light(Vector2(580, 1068))
	var walk := light == "red"
	var board := Rect2(CROSS_RECT.end.x + 10, 1066, 62, 22)
	draw_rect(rect_screen(board), Color("0b3d1e") if walk else Color("4a1010"))
	text_at("WALK" if walk else "WAIT", Vector2(board.position.x + 8, board.position.y + 17), 15, Color("30d158") if walk else Color("ff6b60"))
	# 8. people
	for p in pedestrians:
		var pp := ped_pos(p)
		var bob := sin(game_time * 8.0 + p["phase"]) * 1.5
		tex_at(p["tex"], pp + Vector2(-12, -24 + bob))
	# 9. vehicles
	for v in vehicles:
		var r: Rect2 = v["rect"]
		tex_at(v["tex"], r.position, v["dir"] < 0.0)
	# 10. player
	var tint := Color.WHITE if state != "dead" else Color(1, 0.4, 0.4)
	tex_at("player", player - Vector2(14, 28), false, tint)
	# 11. honk bubbles and messages above the player
	for bb in bubbles:
		draw_rect(rect_screen(Rect2(bb["pos"].x - 4, bb["pos"].y - 18, 62, 20)), Color("ffe066"))
		text_at("BEEP!", Vector2(bb["pos"].x + 2, bb["pos"].y - 3), 15, Color.BLACK)
	if bump_timer > 0.0 and state == "play":
		text_at("Excuse me! -2s", player + Vector2(-50, -56), 20, Color("ffb3a7"))
	if close_call_timer > 0.0 and state == "play":
		text_at("Close call!", player + Vector2(-40, -40), 20, Color("fff3b0"))
	draw_hud()


func draw_hud() -> void:
	# instruction panel
	draw_rect(Rect2(10, 10, 700, 66), Color(0, 0, 0, 0.62))
	var shown := mini(step, STEP_TEXTS.size() - 1)
	text_hud("STEP %d / %d" % [shown + 1, STEP_TEXTS.size()], Vector2(22, 32), 15, Color("9ad0ff"))
	text_hud(STEP_TEXTS[shown], Vector2(22, 62), 24, Color.WHITE)
	if wrong_timer > 0.0:
		draw_rect(Rect2(10, 82, 700, 34), Color("8b0000"))
		text_hud("DEAD END! Go back and check the route.", Vector2(22, 106), 20, Color.WHITE)
	# minimap
	var o := Vector2(W - 200, 10)
	var s := 0.09
	draw_rect(Rect2(o - Vector2(4, 4), Vector2(188, 161)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(o, Vector2(WORLD_W * s, WORLD_H * s)), Color("3f6b3a"))
	draw_rect(Rect2(o + HIGHWAY.position * s, HIGHWAY.size * s), Color("555555"))
	for c in CORRIDORS:
		draw_rect(Rect2(o + c.position * s, c.size * s), Color("d0cabd"))
	draw_circle(o + START_POS * s, 3.5, Color("4da3ff"))
	draw_circle(o + Vector2(1680, 270) * s, 4.0, Color("ffd166"))
	draw_circle(o + player * s, 3.5, Color("ff453a"))
	# bottom bar
	draw_rect(Rect2(0, H - 44, W, 44), Color(0, 0, 0, 0.62))
	var left := distance_left_m()
	var total := int(round(route_length() * M_PER_PX))
	text_hud("Time: %d   Level: %d" % [int(ceil(time_left)), level], Vector2(20, H - 14), 20, Color.WHITE)
	text_hud("To college: %d m" % left, Vector2(330, H - 14), 20, Color.WHITE)
	var frac := clampf(1.0 - float(left) / float(total), 0.0, 1.0)
	draw_rect(Rect2(600, H - 32, 300, 16), Color("444444"))
	draw_rect(Rect2(602, H - 30, 296.0 * frac, 12), Color("06d6a0"))
	text_hud("Signal: %s" % light.to_upper(), Vector2(930, H - 14), 20, Color("30d158") if light == "red" else (Color("ffd60a") if light == "yellow" else Color("ff6b60")))
	# end screens
	if state != "play":
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.65))
		var title := "YOU MADE IT TO CLASS!"
		var sub := "Press R / Enter for the next level"
		if state == "dead":
			title = "YOU DIED"
			sub = "Press R / Enter to try again"
		elif state == "timeout":
			title = "TIME'S UP"
			sub = "Press R / Enter to try again"
		text_hud(title, Vector2(W / 2.0 - 220, H / 2.0 - 30), 48, Color.WHITE)
		if state != "win":
			text_hud(quote, Vector2(W / 2.0 - 260, H / 2.0 + 20), 24, Color("ffd166"))
		text_hud(sub, Vector2(W / 2.0 - 200, H / 2.0 + 70), 22, Color.WHITE)


func route_length() -> float:
	var total := 0.0
	for i in ROUTE.size() - 1:
		total += (ROUTE[i] as Vector2).distance_to(ROUTE[i + 1])
	return total
