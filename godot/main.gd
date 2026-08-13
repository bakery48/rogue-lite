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
var debug_dialog: AcceptDialog = null

# --- 状態 ---
var graveyard: Dictionary = {}
var seed_value = null   # int または null
var reset_flag := false

signal choice_selected(index: int)
signal name_submitted(text: String)


func _ready() -> void:
	_build_ui()
	_parse_cmdline()

	if seed_value != null:
		seed(seed_value)

	if reset_flag:
		_save_graveyard({})
		log_line("墓地を初期化しました。")

	graveyard = _load_graveyard()

	log_line("撤退判断プロトタイプ v0.5（Godot / 分岐マップ・パッシブ・職業・スピリット）")
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

	# デバッグ用：名前/敵/カードの一覧をいつでも確認できるボタン（ゲーム進行とは独立）
	var debug_row := HBoxContainer.new()
	vbox.add_child(debug_row)
	for spec in [
		["名前一覧", _debug_names_text],
		["敵一覧", _debug_enemies_text],
		["カード一覧", _debug_cards_text],
	]:
		var label: String = spec[0]
		var gen: Callable = spec[1]
		var b := Button.new()
		b.text = "デバッグ：%s" % label
		b.pressed.connect(func(): _show_debug_popup(label, gen.call()))
		debug_row.add_child(b)
	vbox.add_child(HSeparator.new())

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


# ---------------------------------------------------------------------------
# デバッグ一覧（名前 / 敵 / カード）
# ---------------------------------------------------------------------------

func _show_debug_popup(title: String, bbcode_text: String) -> void:
	# 前のデバッグダイアログが開いたままだと exclusive window 同士が衝突するので先に閉じる
	# queue_free() はフレーム末まで実体が残るため、即時 hide() してから解放する
	if debug_dialog != null and is_instance_valid(debug_dialog):
		debug_dialog.hide()
		debug_dialog.queue_free()
		debug_dialog = null

	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.size = Vector2i(560, 640)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 560)
	dialog.add_child(scroll)

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.custom_minimum_size = Vector2(500, 0)
	rtl.text = bbcode_text
	scroll.add_child(rtl)

	add_child(dialog)
	debug_dialog = dialog
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.tree_exiting.connect(func():
		if debug_dialog == dialog:
			debug_dialog = null)
	dialog.popup_centered()


func _debug_names_text() -> String:
	var text = "[b]人名候補：全%d種[/b]\n（「名前を選ぶ」で毎回4件がランダム抽出される）\n\n" % Cfg.NAMES.size()
	text += ", ".join(Cfg.NAMES)
	return text


func _debug_enemies_text() -> String:
	var text = "[b]層のボス（各層の最終アクション）[/b]\n"
	for layer_num in Cfg.LAYER_ENEMIES:
		var e = Cfg.LAYER_ENEMIES[layer_num]
		text += "  第%d層：%s　HP %d　攻撃 %s\n" % [
			layer_num, e.name, e.hp, str(e.attacks)]

	text += "\n[b]雑魚（戦闘ノード）[/b]\n"
	text += "  HP = 基礎 + 層×%d　攻撃 = 基礎 + (層-1)×%d\n" % [
		Cfg.MINOR_HP_PER_LAYER, Cfg.MINOR_ATK_PER_LAYER]
	for arch in Cfg.MINOR_ARCHETYPES:
		text += "  %s　基礎HP %d　基礎攻撃 %d\n" % [arch.name, arch.hp, arch.atk]

	text += "\n[b]スピリット（探索・加勢）[/b]\n"
	text += "  出現率 %d%%　攻撃カード：POW+%d\n" % [
		int(Cfg.SPIRIT_APPEAR_RATE * 100), Cfg.SPIRIT_CARD_VALUE]
	return text


func _debug_cards_text() -> String:
	var text = "[b]カード定義[/b]\n"
	for cn in Cfg.CARDS:
		var c = Cfg.CARDS[cn]
		var desc := ""
		match c.type:
			"attack": desc = "攻撃：POW+%d" % c.value
			"block":  desc = "防御：+%d" % c.value
			"draw":   desc = "ドロー：%d枚" % c.value
		text += "  %s　cost %d　%s\n" % [cn, c.cost, desc]

	text += "\n[b]職業別 初期デッキ[/b]\n"
	for job in Cfg.JOBS:
		text += "  %s（特性：%s）\n    %s\n" % [job.name, job.trait, ", ".join(job.deck)]

	text += "\n[b]パッシブ（祭壇）[/b]\n"
	for p in Cfg.PASSIVES:
		text += "  %s　%s\n" % [p.adjective, p.desc]
	return text


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


# テキスト入力欄を出し、決定されるまで待って入力文字列(前後空白除去)を返す。
func prompt_text_input(prompt_text: String, placeholder: String) -> String:
	prompt_label.text = prompt_text
	var line := LineEdit.new()
	line.placeholder_text = placeholder
	line.max_length = 12
	line.custom_minimum_size = Vector2(240, 0)
	choice_box.add_child(line)
	var btn := Button.new()
	btn.text = "決定"
	choice_box.add_child(btn)
	line.text_submitted.connect(func(t): name_submitted.emit(t))
	btn.pressed.connect(func(): name_submitted.emit(line.text))
	line.grab_focus()
	var text: String = await name_submitted
	for c in choice_box.get_children():
		c.queue_free()
	prompt_label.text = ""
	return text.strip_edges()


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

func choose_name() -> String:
	# 名前を決める：ランダム候補から選ぶ / 引き直す / 自分で入力する。
	while true:
		var pool = Cfg.NAMES.duplicate()
		pool.shuffle()
		var candidates = pool.slice(0, 4)
		var labels = candidates.duplicate()
		labels.append("自分で入力する")
		labels.append("候補を引き直す")
		var idx = await present_choices("名前を選ぶ（候補から / 自分で入力）", labels)

		if idx < candidates.size():
			return candidates[idx]
		elif idx == candidates.size():
			var typed = await prompt_text_input("冒険者の名前を入力してください", "名前を入力…")
			if typed != "":
				return typed
			log_line("（名前が空でした。もう一度選んでください）")
		# 「引き直す」または空入力 → ループして再提示
	return Cfg.NAMES[0]  # 到達しない（while true）。型解決のための保険。


func create_adventurer() -> Dictionary:
	var personality = Cfg.PERSONALITIES[randi() % Cfg.PERSONALITIES.size()]

	log_line("\n--- 冒険者の生成 ---")
	log_line("性格（ランダム確定）：%s" % personality.name)

	var adv_name = await choose_name()
	log_line("名前：%s" % adv_name)

	var labels := []
	for job in Cfg.JOBS:
		labels.append("%s（HP %d / POW %d）" % [
			job.name, Cfg.INITIAL_HP + job.hp_mod, Cfg.INITIAL_POW + job.pow_mod])
	var idx = await present_choices("職業を選んでください", labels)
	var job = Cfg.JOBS[idx]

	var max_hp = Cfg.INITIAL_HP + job.hp_mod + personality.hp_bonus
	log_line("  → %s（特性：%s）" % [job.name, job.trait])
	return {
		"personality": personality,
		"job": job,
		"name": adv_name,
		"adjective": "",
		"hp": max_hp,
		"max_hp": max_hp,
		"pow": Cfg.INITIAL_POW + job.pow_mod + personality.pow_bonus,
		# デッキとカード定義（スピリットで動的に増える）
		"deck": job.deck.duplicate(),
		"card_defs": Cfg.CARDS.duplicate(true),
		# 累積する戦闘ボーナス（職業特性＋パッシブ）
		"block_bonus": int(job.block_bonus),
		"attack_bonus": int(job.attack_bonus),
		"draw_bonus": int(job.draw_bonus),
		"energy_bonus": int(job.energy_bonus),
	}


# ---------------------------------------------------------------------------
# 戦闘解決（カード制）
# ---------------------------------------------------------------------------

func resolve_battle(adv: Dictionary, enemy: Dictionary) -> bool:
	# カード戦闘。戻り値: 全滅したら false、敵を倒したら true。
	# enemy は {name, hp, attacks, turn} の辞書（雑魚もボスも共通）。
	var draw_pile: Array = adv.deck.duplicate()
	draw_pile.shuffle()
	var hand: Array = []
	var discard: Array = []
	var block := 0
	var energy := 0
	var hand_size = Cfg.HAND_SIZE + adv.draw_bonus
	var energy_max = Cfg.ENERGY_PER_TURN + adv.energy_bonus

	log_line("\n― 戦闘：%s（HP %d） ―" % [enemy.name, enemy.hp])

	while true:
		# ターン開始：防御リセット、エネルギー回復、手札を引く
		block = 0
		energy = energy_max
		_draw_cards(adv, draw_pile, hand, discard, hand_size - hand.size())

		# プレイヤーのターン
		while true:
			_update_combat_status(adv, enemy, block, energy, energy_max, draw_pile, discard)
			var labels := []
			for card_name in hand:
				labels.append(_card_label(adv, card_name))
			labels.append("― ターン終了 ―")
			var idx = await present_choices("カードを使う / ターン終了", labels)

			if idx == hand.size():
				break  # ターン終了

			var cn: String = hand[idx]
			var c = adv.card_defs[cn]
			if c.cost > energy:
				log_line("  （エネルギー不足：%s は使えない）" % cn)
				continue
			energy -= c.cost
			hand.remove_at(idx)
			match c.type:
				"attack":
					var dmg = adv.pow + c.value + adv.attack_bonus
					enemy.hp -= dmg
					log_line("  ▶ %s：%d ダメージ（敵HP %d）" % [cn, dmg, max(enemy.hp, 0)])
				"block":
					var b = c.value + adv.block_bonus
					block += b
					log_line("  ▶ %s：防御 +%d（防御 %d）" % [cn, b, block])
				"draw":
					var got = _draw_cards(adv, draw_pile, hand, discard, c.value)
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


func _draw_cards(adv: Dictionary, draw_pile: Array, hand: Array, discard: Array, n: int) -> int:
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
	var c = adv.card_defs[card_name]
	var desc := ""
	match c.type:
		"attack":
			desc = "攻撃 %d" % (adv.pow + c.value + adv.attack_bonus)
		"block":
			desc = "防御 %d" % (c.value + adv.block_bonus)
		"draw":
			desc = "%d枚引く" % c.value
	if c.get("spirit", false):
		return "《%s》(c%d) %s" % [card_name, c.cost, desc]
	return "%s(c%d) %s" % [card_name, c.cost, desc]


func _update_combat_status(adv: Dictionary, enemy: Dictionary,
		block: int, energy: int, energy_max: int, draw_pile: Array, discard: Array) -> void:
	var intent = enemy.attacks[enemy.turn % enemy.attacks.size()]
	combat_label.text = "敵 %s HP %d  ▶次の攻撃 %d    ｜    HP %d  防御 %d  E%d/%d  （山%d/捨%d）" % [
		enemy.name, max(enemy.hp, 0), intent,
		adv.hp, block, energy, energy_max,
		draw_pile.size(), discard.size()]


# ---------------------------------------------------------------------------
# 層の分岐マップ（B2）
# ---------------------------------------------------------------------------

func run_layer_map(adv: Dictionary, layer_num: int) -> bool:
	# 1層＝ACTIONS_PER_LAYER個のアクション。最後はボス戦。
	# 戻り値: 全滅したら false、層を踏破したら true。
	var last = Cfg.ACTIONS_PER_LAYER
	for step in range(1, last + 1):
		if step == last:
			# 最後のアクション＝層のボス
			var edef = Cfg.LAYER_ENEMIES[layer_num]
			var boss = {"name": edef.name, "hp": edef.hp,
				"attacks": edef.attacks, "turn": 0}
			log_line("\n【%d/%d】ボス出現：%s" % [step, last, boss.name])
			if not await resolve_battle(adv, boss):
				return false
		else:
			# 分岐：1〜3個の行き先から選ぶ
			var nodes = _generate_nodes()
			var labels := []
			for t in nodes:
				labels.append(_node_label(t))
			log_line("\n【%d/%d】分かれ道（%d択）" % [step, last, nodes.size()])
			var idx = await present_choices("進む先を選ぶ", labels)
			if not await _resolve_node(adv, nodes[idx], layer_num):
				return false
	return true


func _generate_nodes() -> Array:
	# 4種から1〜3個を重複なしで提示（1個なら強制、3個なら選択の幅が広い）。
	var types = ["battle", "rest", "altar", "explore"]
	types.shuffle()
	var count = randi_range(1, 3)
	return types.slice(0, count)


func _node_label(t: String) -> String:
	match t:
		"battle":  return "戦闘（雑魚と戦う）"
		"rest":    return "休息（HP+%d）" % Cfg.REST_HEAL
		"altar":   return "祭壇（パッシブ獲得）"
		"explore": return "探索（スピリットを探す）"
	return t


func _resolve_node(adv: Dictionary, t: String, layer_num: int) -> bool:
	# 戻り値: 全滅したら false。それ以外 true。
	match t:
		"battle":
			var enemy = _make_minor_enemy(layer_num)
			return await resolve_battle(adv, enemy)
		"rest":
			var before = adv.hp
			adv.hp = min(adv.hp + Cfg.REST_HEAL, adv.max_hp)
			log_line("  休息した。HP %d → %d" % [before, adv.hp])
			update_header(adv)
		"altar":
			await choose_passive(adv)
		"explore":
			_find_spirit_card(adv, layer_num)
	return true


func _make_minor_enemy(layer_num: int) -> Dictionary:
	var arch = Cfg.MINOR_ARCHETYPES[randi() % Cfg.MINOR_ARCHETYPES.size()]
	var hp = arch.hp + layer_num * Cfg.MINOR_HP_PER_LAYER
	var atk = arch.atk + (layer_num - 1) * Cfg.MINOR_ATK_PER_LAYER
	return {"name": arch.name, "hp": hp,
		"attacks": [atk, atk + 1, atk], "turn": 0}


# ---------------------------------------------------------------------------
# 祭壇：パッシブ獲得（B3）
# ---------------------------------------------------------------------------

func choose_passive(adv: Dictionary) -> void:
	var n = min(adv.personality.enchant_choices, Cfg.PASSIVES.size())
	var pool = Cfg.PASSIVES.duplicate()
	pool.shuffle()
	var options = pool.slice(0, n)

	log_line("  --- 祭壇：パッシブ選択（%d択） ---" % n)
	var labels := []
	for e in options:
		labels.append("%s（%s）" % [e.adjective, e.desc])
	var idx = await present_choices("祭壇：パッシブを選ぶ", labels)
	var chosen = options[idx]

	# 通り名（形容詞）は常に最新1つで上書き。効果は field ごとに累積。
	adv.adjective = chosen.adjective
	match chosen.field:
		"pow":    adv.pow += chosen.amount
		"block":  adv.block_bonus += chosen.amount
		"attack": adv.attack_bonus += chosen.amount
		"energy": adv.energy_bonus += chosen.amount
		"draw":   adv.draw_bonus += chosen.amount
	log_line("  → %s（%s）" % [display_name(adv), chosen.desc])
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
	# 層開始時、その層の墓地から1体だけ抽選し、確率で加勢（スピリットカード化）。
	var key = str(layer)
	if not graveyard.has(key) or graveyard[key].is_empty():
		return false
	if randf() >= Cfg.SPIRIT_APPEAR_RATE:
		return false
	var cards = graveyard[key]
	var card = cards[randi() % cards.size()]
	log_line("\n◆ 過去の魂が加勢した：%s" % card.get("display_name", "さまよう魂"))
	_add_spirit_card(adv, card.get("name", "魂"), Cfg.SPIRIT_CARD_VALUE)
	return true


func _find_spirit_card(adv: Dictionary, layer: int) -> void:
	# 探索ノード：墓地に縁があればその魂、無ければ「さまよう魂」をデッキへ。
	var key = str(layer)
	var label := "さまよう魂"
	if graveyard.has(key) and not graveyard[key].is_empty():
		var cards = graveyard[key]
		var card = cards[randi() % cards.size()]
		label = card.get("name", "さまよう魂")
		log_line("  探索で魂を見つけた：%s" % card.get("display_name", label))
	else:
		log_line("  探索で さまよう魂 を見つけた")
	_add_spirit_card(adv, label, Cfg.SPIRIT_CARD_VALUE)


func _add_spirit_card(adv: Dictionary, spirit_name: String, value: int) -> void:
	# スピリットカードをデッキとカード定義に加える（そのラン限定）。
	adv.card_defs[spirit_name] = {
		"cost": 1, "type": "attack", "value": value, "spirit": true}
	adv.deck.append(spirit_name)
	log_line("  → スピリットカード《%s》がデッキに加わった（攻撃 POW+%d）" % [spirit_name, value])


func record_spirit(adv: Dictionary, layer: int) -> void:
	# 撤退・クリア時に冒険者をスピリットとして墓地に追加（上限なし）。
	var key = str(layer)
	if not graveyard.has(key):
		graveyard[key] = []
	graveyard[key].append({
		"display_name": display_name(adv),
		"name": adv.name,
		"pow": adv.pow,
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

		# a. スピリット抽選（その層の墓地から1体だけ、カード化して加勢）
		if try_spirit_appearance(adv, layer_num):
			spirit_appearances += 1

		# b. 7アクションの分岐マップ（戦闘/休息/祭壇/探索 → 最後はボス）
		var survived = await run_layer_map(adv, layer_num)
		update_header(adv)
		if not survived:
			ending = "death"
			break

		# d. HP回復
		adv.hp += Cfg.HP_RECOVER_PER_LAYER
		log_line("\n第%d層 踏破。HP +%d → 残HP %d" % [
			layer_num, Cfg.HP_RECOVER_PER_LAYER, adv.hp])
		update_header(adv)

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
