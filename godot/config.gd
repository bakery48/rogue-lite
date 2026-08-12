# 数値・定義の集約ファイル（Godot版）。
#
# バランス調整はこのファイルだけを編集する。
# 性格・パッシブ・職業・カード・敵は、配列/辞書に1行足すだけで追加できる。
extends RefCounted

# ---- 基本パラメータ ----
const INITIAL_HP := 30            # 冒険者の基準HP
const INITIAL_POW := 3            # 冒険者の基準POW（攻撃カードの基礎値）

const HP_RECOVER_PER_LAYER := 5   # 層クリアごとのHP回復量
const MAX_LAYER := 5              # 最終層。ここをクリアするとラン終了

# ---- 層の分岐マップ（B2） ----
const ACTIONS_PER_LAYER := 7      # 1層のアクション数。最後の1つは層のボス戦
const REST_HEAL := 8              # 休息ノードの回復量（最大HPまで）

# ---- カード戦闘 ----
const ENERGY_PER_TURN := 3        # 毎ターンのエネルギー（職業/パッシブで増える）
const HAND_SIZE := 5              # 毎ターン引く手札の枚数（職業/パッシブで増える）

# カード定義。
#   type "attack" … ダメージ = POW + value (+ 攻撃パッシブ)
#   type "block"  … 防御 = value (+ 防御パッシブ)
#   type "draw"   … value 枚引く
const CARDS := {
	"打撃": {"cost": 1, "type": "attack", "value": 2},
	"強打": {"cost": 2, "type": "attack", "value": 5},
	"守り": {"cost": 1, "type": "block",  "value": 4},
	"大盾": {"cost": 2, "type": "block",  "value": 8},
	"疾風": {"cost": 0, "type": "draw",   "value": 1},
	"魔弾": {"cost": 2, "type": "attack", "value": 6},   # 魔法使い
	"短剣": {"cost": 0, "type": "attack", "value": 1},   # 盗賊
	"集中": {"cost": 1, "type": "draw",   "value": 2},   # 魔法使い
}

# ---- スピリット（カード化・B5） ----
const SPIRIT_APPEAR_RATE := 0.50  # 層開始時、その層の墓地から1体が加勢する確率
const SPIRIT_CARD_VALUE := 5      # スピリットカードの攻撃値（ダメージ = POW + これ）

# ---- 層のボス敵（各層の最後のアクション） ----
const LAYER_ENEMIES := {
	1: {"name": "スライム王",   "hp": 22, "attacks": [4, 5, 4]},
	2: {"name": "ゴブリン長",   "hp": 30, "attacks": [5, 6, 5, 8]},
	3: {"name": "オーガ",       "hp": 38, "attacks": [6, 8, 6, 10]},
	4: {"name": "ワイバーン",   "hp": 50, "attacks": [8, 9, 11, 9]},
	5: {"name": "層の主",       "hp": 64, "attacks": [9, 11, 13, 11, 16]},
}

# ---- 雑魚敵（戦闘ノード。層で強くなる） ----
const MINOR_ARCHETYPES := [
	{"name": "コウモリ",     "hp": 7,  "atk": 3},
	{"name": "骸骨兵",       "hp": 10, "atk": 3},
	{"name": "ゴブリン斥候", "hp": 9,  "atk": 4},
]
const MINOR_HP_PER_LAYER := 4
const MINOR_ATK_PER_LAYER := 1

# ---- 永続化ファイル（user:// 以下に保存） ----
const GRAVEYARD_FILE := "graveyard.json"
const RUNS_CSV_FILE := "runs.csv"

# ---- 職業（B4） ----
# 基準からの配分差(mod) ＋ 常時特性(bonus) ＋ 初期デッキ。
#   block_bonus  … 防御カードの防御量に加算
#   attack_bonus … 攻撃カードのダメージに加算
#   draw_bonus   … 毎ターン引く枚数に加算
#   energy_bonus … 毎ターンのエネルギーに加算
const JOBS := [
	{"name": "戦士", "hp_mod": 5, "pow_mod": 0,
	 "block_bonus": 2, "attack_bonus": 0, "draw_bonus": 0, "energy_bonus": 0,
	 "trait": "防御カード+2", "deck": [
		"打撃", "打撃", "打撃", "打撃", "強打", "強打", "守り", "守り", "大盾", "大盾"]},
	{"name": "魔法使い", "hp_mod": -5, "pow_mod": 1,
	 "block_bonus": 0, "attack_bonus": 1, "draw_bonus": 0, "energy_bonus": 0,
	 "trait": "攻撃カード+1", "deck": [
		"打撃", "打撃", "打撃", "魔弾", "魔弾", "強打", "集中", "守り", "守り", "疾風"]},
	{"name": "盗賊", "hp_mod": 0, "pow_mod": 0,
	 "block_bonus": 0, "attack_bonus": 0, "draw_bonus": 1, "energy_bonus": 0,
	 "trait": "毎ターン手札+1", "deck": [
		"打撃", "打撃", "打撃", "短剣", "短剣", "守り", "守り", "疾風", "疾風", "疾風"]},
]

# ---- 性格 ----
# enchant_choices … 祭壇で提示されるパッシブの数
# retreat_needs_half_hp … 撤退時HPが半分以下だと記録失敗
#   ※ fail_damage_bonus / reroll_on_fail / pow_gain_interval はダイス時代の名残で現在未使用。
const PERSONALITIES := [
	{"name": "シャイな",       "hp_bonus": 0, "pow_bonus": 1,
	 "enchant_choices": 2, "pow_gain_interval": 1,
	 "fail_damage_bonus": 0, "reroll_on_fail": false,
	 "retreat_needs_half_hp": false},
	{"name": "目立ちたがりな", "hp_bonus": 0, "pow_bonus": 0,
	 "enchant_choices": 4, "pow_gain_interval": 1,
	 "fail_damage_bonus": 1, "reroll_on_fail": false,
	 "retreat_needs_half_hp": false},
	{"name": "慎重な",         "hp_bonus": 8, "pow_bonus": 0,
	 "enchant_choices": 3, "pow_gain_interval": 2,
	 "fail_damage_bonus": 0, "reroll_on_fail": false,
	 "retreat_needs_half_hp": false},
	{"name": "無謀な",         "hp_bonus": 0, "pow_bonus": 0,
	 "enchant_choices": 3, "pow_gain_interval": 1,
	 "fail_damage_bonus": 0, "reroll_on_fail": true,
	 "retreat_needs_half_hp": true},
]

# ---- パッシブ（祭壇で獲得・B3） ----
# 効果は field/amount で累積。通り名(adjective)は最新1つだけが表示名に乗る。
const PASSIVES := [
	{"adjective": "剛力の", "field": "pow",    "amount": 1, "desc": "POW+1"},
	{"adjective": "鋼の",   "field": "block",  "amount": 2, "desc": "防御カード+2"},
	{"adjective": "烈火の", "field": "attack", "amount": 1, "desc": "攻撃カード+1"},
	{"adjective": "疾風の", "field": "energy", "amount": 1, "desc": "エネルギー+1"},
	{"adjective": "明晰の", "field": "draw",   "amount": 1, "desc": "毎ターン手札+1"},
	{"adjective": "星屑の", "field": "pow",    "amount": 2, "desc": "POW+2"},
]

# ---- 人名 ----
const NAMES := [
	"アレックス", "ベルナ", "カイト", "ディーナ", "エリオ",
	"フィオナ", "ガロ", "ハンナ", "イヴァン", "ジュナ",
	"クレア", "ルーカス", "ミラ", "ノア", "オルガ", "レン",
]
