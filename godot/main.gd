# 撤退判断プロトタイプ（Godot版）。
#
# Python版 main.py の忠実移植。ロジックは同じで、UIをテキスト主体の最小構成にしてある。
# アート・演出は作らない（検証が通ってから）。
#
# コマンドライン:
#   godot --path godot -- --seed 42     乱数シードを固定
#   godot --path godot -- --reset       墓地(user://graveyard.json)を初期化
extends Control

const Cfg = preload("res://config.gd")

const CSV_HEADER := "run_id,seed,性格,職業,名前,最終形容詞,最終表示名,到達層,結末,最終HP,最終POW,スピリット出現回数,撤退時の残HP割合,迷ったか"

# --- UI ノード ---
var header_label: Label
var combat_label: Label
var log_label: RichTextLabel
var prompt_label: Label
var choice_box: HBoxContainer

# --- 状態 ---
var graveyard: Dictionary = {}
var seed_value = null   # int または null
var reset_flag := false

signal choice_selected(index: int)


func _ready() -> void:
	_build_ui()
	_parse_cmdline()

	if seed_value != null:
		seed(seed_value)

	if reset_flag:
		_save_graveyard({})
		log_line("墓地を初期化しました。")

	graveyard = _load_graveyard()

	log_line("撤退判断プロトタイプ v0.4（Godot / カード戦闘 B1）")
	await run_game()


# ---------------------------------------------------------------------------
# UI 構築とヘルパー
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	# 画面上部に常に表示名を出す（形容詞の上書きが見える）
	header_label = Label.new()
	header_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(header_label)

	# 戦闘中の敵/自分の状態（戦闘外では空）
	combat_label = Label.new()
	combat_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(combat_label)

	vbox.add_child(HSeparator.new())

	# 戦闘ログなどの流れ表示（自動で末尾に追従）
	log_label = RichTextLabel.new()
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(log_label)

	prompt_label = Label.new()
	prompt_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(prompt_label)

	choice_box = HBoxContainer.new()
	vbox.add_child(choice_box)


func log_line(text: String) -> void:
	log_label.append_text(text + "\n")


func update_header(adv: Dictionary) -> void:
	header_label.text = "%s\nHP %d / POW %d" % [display_name(adv), adv.hp, adv.pow]


# 選択肢ボタンを出し、押されるまで待って選ばれた番号(0始まり)を返す。
func present_choices(prompt_text: String, labels: Array) -> int:
	prompt_label.text = prompt_text
	for i in labels.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, labels[i]]
		b.pressed.connect(func(): choice_selected.emit(i))
		choice_box.add_child(b)
	var idx: int = await choice_selected
	for c in choice_box.get_children():
		c.queue_free()
	prompt_label.text = ""
	return idx


# ---------------------------------------------------------------------------
# 表示名
# ---------------------------------------------------------------------------

func display_name(adv: Dictionary) -> String:
	# 表示名：［性格］［形容詞］［職業］［名前］。形容詞は初期は空。
	var parts := [adv.personality.name]
	if adv.adjective != "":
		parts.append(adv.adjective)
	parts.append(adv.job.name)
	parts.append(adv.name)
	return " ".join(parts)


# ---------------------------------------------------------------------------
# 冒険者の生成
# ---------------------------------------------------------------------------

func create_adventurer() -> Dictionary:
	var personality = Cfg.PERSONALITIES[randi() % Cfg.PERSONALITIES.size()]
	var adv_name = Cfg.NAMES[randi() % Cfg.NAMES.size()]

	log_line("\n--- 冒険者の生成 ---")
	log_line("性格（ランダム確定）：%s" % personality.name)

	var labels := []
	for job in Cfg.JOBS:
		labels.append("%s（HP %d / POW %d）" % [
			job.name, Cfg.INITIAL_HP + job.hp_mod, Cfg.INITIAL_POW + job.pow_mod])
	var idx = await present_choices("職業を選んでください", labels)
	var job = Cfg.JOBS[idx]

	var max_hp = Cfg.INITIAL_HP + job.hp_mod + personality.hp_bonus
	return {
		"personality": personality,
		"job": job,
		"name": adv_name,
		"adjective": "",
		"hp": max_hp,
		"max_hp": max_hp,
		"pow": Cfg.INITIAL_POW + job.pow_mod + personality.pow_bonus,
		"deck": Cfg.STARTING_DECK.duplicate(),  # ランを通して持つデッキ（B1は職業共通）
	}


# ---------------------------------------------------------------------------
# 戦闘解決（カード制）
# ---------------------------------------------------------------------------

func resolve_layer(adv: Dictionary, layer_num: int) -> bool:
	# 1層＝1戦闘（B1）。戻り値: 全滅したら false、敵を倒したら true。
	var edef = Cfg.LAYER_ENEMIES[layer_num]
	var enemy = {"name": edef.name, "hp": edef.hp, "attacks": edef.attacks, "turn": 0}

	# 戦闘中だけ使う一時状態
	var draw_pile: Array = adv.deck.duplicate()
	draw_pile.shuffle()
	var hand: Array = []
	var discard: Array = []
	var block := 0
	var energy := 0

	log_line("\n― 戦闘：%s（HP %d） ―" % [enemy.name, enemy.hp])

	while true:
		# ターン開始：防御リセット、エネルギー回復、手札を引く
		block = 0
		energy = Cfg.ENERGY_PER_TURN
		_draw_cards(draw_pile, hand, discard, Cfg.HAND_SIZE - hand.size())

		# プレイヤーのターン
		while true:
			_update_combat_status(adv, enemy, block, energy, draw_pile, discard)
			var labels := []
			for card_name in hand:
				labels.append(_card_label(adv, card_name))
			labels.append("― ターン終了 ―")
			var idx = await present_choices("カードを使う / ターン終了", labels)

			if idx == hand.size():
				break  # ターン終了

			var cn: String = hand[idx]
			var c = Cfg.CARDS[cn]
			if c.cost > energy:
				log_line("  （エネルギー不足：%s は使えない）" % cn)
				continue
			energy -= c.cost
			hand.remove_at(idx)
			match c.type:
				"attack":
					var dmg = adv.pow + c.value
					enemy.hp -= dmg
					log_line("  ▶ %s：%d ダメージ（敵HP %d）" % [cn, dmg, max(enemy.hp, 0)])
				"block":
					block += c.value
					log_line("  ▶ %s：防御 +%d（防御 %d）" % [cn, c.value, block])
				"draw":
					var got = _draw_cards(draw_pile, hand, discard, c.value)
					log_line("  ▶ %s：%d枚引いた" % [cn, got])
			discard.append(cn)
			if enemy.hp <= 0:
				log_line("  ★ %s を倒した！" % enemy.name)
				combat_label.text = ""
				return true

		# ターン終了：手札を捨てて敵の攻撃
		discard.append_array(hand)
		hand.clear()
		var atk = enemy.attacks[enemy.turn % enemy.attacks.size()]
		var dmg = max(0, atk - block)
		adv.hp -= dmg
		log_line("  ◆ %sの攻撃 %d（防御%dで軽減）→ %d ダメージ  残HP %d" % [
			enemy.name, atk, block, dmg, adv.hp])
		enemy.turn += 1
		update_header(adv)
		if adv.hp <= 0:
			combat_label.text = ""
			return false
	return false  # 到達しない（while true）。型解決のための保険。


func _draw_cards(draw_pile: Array, hand: Array, discard: Array, n: int) -> int:
	# 山札から n 枚 hand へ。尽きたら捨札を再シャッフルして山札に戻す。
	var got := 0
	for _i in range(n):
		if draw_pile.is_empty():
			if discard.is_empty():
				break
			draw_pile.append_array(discard)
			discard.clear()
			draw_pile.shuffle()
		hand.append(draw_pile.pop_back())
		got += 1
	return got


func _card_label(adv: Dictionary, card_name: String) -> String:
	var c = Cfg.CARDS[card_name]
	var desc := ""
	match c.type:
		"attack":
			desc = "攻撃 %d" % (adv.pow + c.value)
		"block":
			desc = "防御 %d" % c.value
		"draw":
			desc = "%d枚引く" % c.value
	return "%s(c%d) %s" % [card_name, c.cost, desc]


func _update_combat_status(adv: Dictionary, enemy: Dictionary,
		block: int, energy: int, draw_pile: Array, discard: Array) -> void:
	var intent = enemy.attacks[enemy.turn % enemy.attacks.size()]
	combat_label.text = "敵 %s HP %d  ▶次の攻撃 %d    ｜    HP %d  防御 %d  ⚡%d/%d  （山%d/捨%d）" % [
		enemy.name, max(enemy.hp, 0), intent,
		adv.hp, block, energy, Cfg.ENERGY_PER_TURN,
		draw_pile.size(), discard.size()]


# ---------------------------------------------------------------------------
# エンチャント
# ---------------------------------------------------------------------------

func choose_enchant(adv: Dictionary, layer_num: int) -> void:
	var n = min(adv.personality.enchant_choices, Cfg.ENCHANTMENTS.size())
	var pool = Cfg.ENCHANTMENTS.duplicate()
	pool.shuffle()
	var options = pool.slice(0, n)

	log_line("\n--- エンチャント選択（%d択） ---" % n)
	var labels := []
	for e in options:
		labels.append("%s（POW +%d）" % [e.adjective, e.pow])
	var idx = await present_choices("エンチャントを選んでください", labels)
	var chosen = options[idx]

	adv.adjective = chosen.adjective  # 形容詞は常に上書き

	var interval = adv.personality.pow_gain_interval
	if layer_num % interval == 0:
		adv.pow += chosen.pow
		log_line("  → %s（POW +%d）" % [display_name(adv), chosen.pow])
	else:
		log_line("  → %s（この層ではPOWは上がらない）" % display_name(adv))
	update_header(adv)


# ---------------------------------------------------------------------------
# 撤退 / 続行（★検証対象）
# ---------------------------------------------------------------------------

func ask_retreat(adv: Dictionary, current_layer: int) -> bool:
	# 戻り値: 撤退なら true、続行なら false。
	var next_layer = current_layer + 1
	var nxt = Cfg.LAYER_ENEMIES[next_layer]

	log_line("\n" + "-".repeat(40))
	log_line("★ 撤退 / 続行 の選択（第%d層クリア）" % current_layer)
	log_line("  現在  ： HP %d / POW %d / 到達 第%d層" % [adv.hp, adv.pow, current_layer])
	log_line("  次の層： 第%d層  敵 %s（HP %d / 攻撃 最大%d）" % [
		next_layer, nxt.name, nxt.hp, nxt.attacks.max()])
	log_line("  撤退すると記録される表示名： %s" % display_name(adv))
	log_line("-".repeat(40))

	var idx = await present_choices("撤退 or 続行", [
		"撤退する（ラン終了）", "続行する（第%d層へ）" % next_layer])
	return idx == 0


# ---------------------------------------------------------------------------
# スピリット（墓地の再出現）
# ---------------------------------------------------------------------------

func try_spirit_appearance(adv: Dictionary, layer: int) -> bool:
	# その層の墓地から1体だけ抽選し、確率で出現。何体増えても出現は1体まで。
	var key = str(layer)
	if not graveyard.has(key) or graveyard[key].is_empty():
		return false
	var cards = graveyard[key]
	var card = cards[randi() % cards.size()]
	if randf() >= Cfg.SPIRIT_APPEAR_RATE:
		return false
	adv.pow += Cfg.SPIRIT_POW_BONUS
	log_line("◆ %sが加勢した（POW +%d）" % [card.display_name, Cfg.SPIRIT_POW_BONUS])
	return true


func record_spirit(adv: Dictionary, layer: int) -> void:
	# 撤退・クリア時に冒険者をスピリットカードとして墓地に追加（上限なし）。
	var key = str(layer)
	if not graveyard.has(key):
		graveyard[key] = []
	graveyard[key].append({
		"display_name": display_name(adv),
		"layer": layer,
		"job": adv.job.name,
	})


# ---------------------------------------------------------------------------
# ラン進行
# ---------------------------------------------------------------------------

func run_game() -> void:
	var adv = await create_adventurer()

	var ending := ""       # "death" / "retreat" / "clear"
	var reached := 0
	var spirit_appearances := 0

	for layer_num in range(1, Cfg.MAX_LAYER + 1):
		reached = layer_num
		log_line("\n\n########## 第%d層 ##########" % layer_num)
		update_header(adv)

		# a. スピリット抽選（その層の墓地から1体だけ）
		if try_spirit_appearance(adv, layer_num):
			spirit_appearances += 1

		# b. 戦闘を解決（カード制）
		var survived = await resolve_layer(adv, layer_num)
		update_header(adv)
		if not survived:
			ending = "death"
			break

		# d. HP回復
		adv.hp += Cfg.HP_RECOVER_PER_LAYER
		log_line("\n第%d層突破。HP +%d → 残HP %d" % [
			layer_num, Cfg.HP_RECOVER_PER_LAYER, adv.hp])
		update_header(adv)

		# e. エンチャント
		await choose_enchant(adv, layer_num)

		# 最終層クリアなら自動的にラン終了
		if layer_num == Cfg.MAX_LAYER:
			ending = "clear"
			break

		# ★ 撤退 / 続行
		if await ask_retreat(adv, layer_num):
			ending = "retreat"
			break

	# 記録（撤退・クリアのみ。全滅は何も残さない）
	var hp_ratio = ""
	var recorded := false
	if ending == "retreat":
		hp_ratio = snappedf(float(adv.hp) / float(adv.max_hp), 0.01)
		# 無謀な：撤退時HPが半分以下だと記録失敗
		if adv.personality.retreat_needs_half_hp and adv.hp * 2 <= adv.max_hp:
			log_line("\n※ HPが半分以下のため、スピリットの記録に失敗した。")
		else:
			record_spirit(adv, reached)
			recorded = true
	elif ending == "clear":
		record_spirit(adv, reached)
		recorded = true

	print_result(adv, reached, ending, spirit_appearances, recorded)
	_save_graveyard(graveyard)

	# 検証の主データ：迷ったか（1〜5）
	log_line("\n今回の撤退/続行の判断で、どれくらい迷いましたか？")
	log_line("  1（即決） 〜 5（かなり悩んだ）")
	var hesitation = (await present_choices("迷ったか", ["1", "2", "3", "4", "5"])) + 1
	append_run_log(adv, reached, ending, spirit_appearances, hp_ratio, hesitation)
	log_line("記録しました（user://%s）。" % Cfg.RUNS_CSV_FILE)
	log_line("\n（ウィンドウを閉じて終了。もう一度遊ぶには再実行してください）")


func print_result(adv: Dictionary, reached: int, ending: String,
		spirit_appearances: int, recorded: bool) -> void:
	var labels = {
		"death": "全滅（何も記録されない）",
		"retreat": "撤退",
		"clear": "第%d層クリア" % Cfg.MAX_LAYER,
	}
	log_line("\n" + "=".repeat(40))
	log_line("  ラン終了")
	log_line("  最終表示名   ： %s" % display_name(adv))
	log_line("  到達層       ： 第%d層" % reached)
	log_line("  結末         ： %s" % labels.get(ending, ending))
	log_line("  最終HP/POW   ： %d / %d" % [adv.hp, adv.pow])
	log_line("  スピリット出現： %d回" % spirit_appearances)
	if ending == "retreat" or ending == "clear":
		log_line("  墓地への記録 ： %s" % ("成功" if recorded else "失敗"))
	log_line("=".repeat(40))
	update_header(adv)


# ---------------------------------------------------------------------------
# 永続化（user:// 以下）
# ---------------------------------------------------------------------------

func _graveyard_path() -> String:
	return "user://" + Cfg.GRAVEYARD_FILE


func _runs_path() -> String:
	return "user://" + Cfg.RUNS_CSV_FILE


func _load_graveyard() -> Dictionary:
	var path = _graveyard_path()
	if not FileAccess.file_exists(path):
		return {}
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text = f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if typeof(data) == TYPE_DICTIONARY:
		return data
	return {}


func _save_graveyard(gv: Dictionary) -> void:
	var f = FileAccess.open(_graveyard_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(gv, "  "))
	f.close()


func _next_run_id() -> int:
	var path = _runs_path()
	if not FileAccess.file_exists(path):
		return 1
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 1
	var count := 0
	while not f.eof_reached():
		var line = f.get_line().strip_edges()
		if line == "" or line.begins_with("run_id"):
			continue
		count += 1
	f.close()
	return count + 1


func append_run_log(adv: Dictionary, reached: int, ending: String,
		spirit_appearances: int, hp_ratio, hesitation: int) -> void:
	var path = _runs_path()
	var exists = FileAccess.file_exists(path)
	var run_id = _next_run_id()

	var f
	if exists:
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
		f.store_line(CSV_HEADER)
	if f == null:
		return

	var seed_field = "" if seed_value == null else str(seed_value)
	var row = [
		str(run_id), seed_field, adv.personality.name, adv.job.name, adv.name,
		adv.adjective, display_name(adv), str(reached), ending,
		str(adv.hp), str(adv.pow), str(spirit_appearances),
		str(hp_ratio), str(hesitation),
	]
	f.store_line(",".join(row))
	f.close()


# ---------------------------------------------------------------------------
# コマンドライン引数（--seed / --reset）
# ---------------------------------------------------------------------------

func _parse_cmdline() -> void:
	var all_args = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i in all_args.size():
		var arg: String = all_args[i]
		if arg == "--reset":
			reset_flag = true
		elif arg == "--seed":
			if i + 1 < all_args.size():
				seed_value = int(all_args[i + 1])
		elif arg.begins_with("--seed="):
			seed_value = int(arg.substr("--seed=".length()))
