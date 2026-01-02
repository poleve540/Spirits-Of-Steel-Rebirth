extends Node
class_name CountryData

# =========================================================
# Identity & Flags
# =========================================================
var country_name: String
var is_player: bool = false # If true, AI logic is skipped

# =========================================================
# Stats
# =========================================================
var political_power: int = 50
var money: float = 40000.0
var manpower: int = 50000
var stability: float = 0.5      # 0.0 to 1.0
var war_support: float = 0.5    # 0.0 to 1.0

# =========================================================
# Daily Gains
# =========================================================
var daily_pp_gain: int = 2
var daily_money_income: float = 1000
var daily_manpower_growth: int = 600

var allowedCountries: Array[String] = [] # for pathfinding

# =========================================================
# Training / Troop Pools
# =========================================================
var deploy_pid: int = -1 

# --- Training ---
class TroopTraining:
	var divisions: int
	var days_left: int
	var daily_cost: float
	
	func _init(_divisions: int, _days: int, _daily_cost: float):
		divisions = _divisions
		days_left = _days
		daily_cost = _daily_cost

# --- Ready (not deployed) ---
class ReadyTroop:
	var divisions: int
	func _init(_divisions: int):
		divisions = _divisions

var ongoing_training: Array[TroopTraining] = []
var ready_troops: Array[ReadyTroop] = []

# =========================================================
# AI Internal State (New)
# =========================================================
# Randomize this in _init so not all countries think on Day 1
var ai_think_interval: int = 5 
var ai_days_until_think: int = 0 

# Defines how aggressive the AI is with spending
var ai_budget_safety_margin: float = 0.2 # Keep 20% of income as backup

# =========================================================
# Initialization
# =========================================================
func _init(p_name: String) -> void:
	country_name = p_name
	self.name = p_name
	allowedCountries.append(p_name)
	
	# Initialize AI staggering
	# Some countries think every 3 days, some every 7. 
	# Starts with a random offset so they don't all spike the CPU on day 0.
	ai_think_interval = randi_range(3, 8)
	ai_days_until_think = randi_range(0, ai_think_interval)

# =========================================================
# Combat Modifiers
# =========================================================
func get_max_morale() -> float:
	var base := 60.0 + (stability * 40.0)
	if money < 0: base *= 0.5
	return base

func get_attack_efficiency() -> float:
	var eff := 0.9 + (war_support * 0.3)
	if money < 0: eff *= 0.7
	return eff

func get_defense_efficiency() -> float:
	var eff := 1.0 + (stability * 0.15)
	if money < 0: eff *= 0.8
	return eff

# =========================================================
# Daily Turn Processing
# =========================================================
func process_turn() -> void:
	# 1. Update Economy (Always happens daily)
	political_power += daily_pp_gain
	money += (daily_money_income - calculate_army_upkeep())
	manpower += daily_manpower_growth
	
	# 2. Process active training queues (Always happens daily)
	_process_training()

	# 3. AI Logic (Only if not player, and only on specific days)
	if not is_player:
		_process_ai_decisions()

# =========================================================
# AI LOGIC ENGINE (Performant)
# =========================================================
func _process_ai_decisions() -> void:
	# Decrease counter
	ai_days_until_think -= 1
	
	# If it's not time to think yet, exit immediately (Performance Saver)
	if ai_days_until_think > 0:
		return

	# Reset timer
	ai_days_until_think = ai_think_interval
	
	# --- AI BRAIN START ---
	
	# 1. Check for Deployment
	# If we have troops sitting in the pool, put them on the map!
	if not ready_troops.is_empty():
		_ai_handle_deployment()

	# 2. Check for Training
	# Only train if we are rich enough and have manpower
	_ai_consider_recruitment()

func _ai_handle_deployment() -> void:
	# Clone the list to avoid modification issues while iterating
	var troops_to_deploy = ready_troops.duplicate()
	
	for troop in troops_to_deploy:
		# AI strategy: Just put them somewhere valid for now.
		# In the future, you could check for borders with enemies.
		deploy_ready_troop_to_random(troop)

func _ai_consider_recruitment() -> void:
	# AI Rules for recruitment:
	# 1. Don't go bankrupt. Keep a buffer of cash equal to 10 days of income.
	var safety_buffer = daily_money_income * 10.0
	
	if money < safety_buffer:
		return # Too poor to train right now
		
	if manpower < 10000:
		return # Not enough men

	# 2. Decide what to train
	# Standard AI Division: 5 Divisions, takes 10 days, cost 50/day
	var divs_to_train = 5
	var train_time = 10
	var cost = 50.0
	
	# Check if we can afford the FULL cost upfront (or daily flow)
	# This function already checks manpower/money internally
	var success = train_troops(divs_to_train, train_time, cost)
	
	if success:
		# Optional: Print for debug only if needed
		# print("%s AI started training %d divisions." % [country_name, divs_to_train])
		pass

# =========================================================
# Training Logic (Core)
# =========================================================
func _process_training() -> void:
	for training in ongoing_training:
		var daily_cost := training.divisions * training.daily_cost
		
		if money >= daily_cost:
			money -= daily_cost
			training.days_left -= 1
		else:
			# Pause training if no money (or cancel it?)
			continue
	
	for i in range(ongoing_training.size() - 1, -1, -1):
		var training = ongoing_training[i]
		if training.days_left <= 0:
			ready_troops.append(ReadyTroop.new(training.divisions))
			ongoing_training.remove_at(i)

func calculate_army_upkeep() -> float:
	var total := 0.0
	# Assuming TroopManager is a global singleton
	for troop in TroopManager.get_troops_for_country(country_name):
		total += troop.divisions * 10 # Example upkeep cost
	return total

func train_troops(divisions: int, days: int, cost_per_day: float) -> bool:
	var manpower_needed := divisions * 1000 # Adjusted from 10k to 1k for balance?
	var first_day_cost := divisions * cost_per_day
	
	if manpower < manpower_needed:
		return false
	if money < first_day_cost:
		return false
	
	manpower -= manpower_needed
	money -= first_day_cost
	
	ongoing_training.append(
		TroopTraining.new(divisions, days, cost_per_day)
	)
	return true

func deploy_ready_troop_to_random(troop: ReadyTroop) -> bool:
	var index = ready_troops.find(troop)
	if index == -1: return false
	
	var my_provinces: Array = MapManager.country_to_provinces.get(country_name, [])
	if my_provinces.is_empty():
		# Fallback: if map manager fails, try to find *any* province (dangerous but prevents crash)
		return false
		
	var random_province_id = my_provinces.pick_random()
	TroopManager.create_troop(country_name, troop.divisions, random_province_id)
	
	ready_troops.remove_at(index)
	return true
