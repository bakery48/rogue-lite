# 数値・定義の集約ファイル（Godot版）。
#
# バランス調整はこのファイルだけを編集する。
# 性格・エンチャント・職業・カード・敵は、配列/辞書に1行足すだけで追加できる。
extends RefCounted

# ---- 基本パラメータ ----
const INITIAL_HP := 30            # 冒険者の基準HP（カード戦闘用に大きめ）
const INITIAL_POW := 3            # 冒険者の基準POW（攻撃カードの基礎値）

const HP_RECOVER_PER_LAYER := 5   # 層クリアごとのHP回復量
const MAX_LAYER := 5              # 最終層。ここをクリアするとラン終了

# ---- カード戦闘 ----
const ENERGY_PER_TURN := 3        # 毎ターンのエネルギー
const HAND_SIZE := 5              # 毎ターン引く手札の枚数

# カード定義。
#   type "attack" … ダメージ = POW + value
#   type "block"  … 防御 = value
#   type "draw"   … value 枚引く
const CARDS := {
	"打撃": {"cost": 1, "type": "attack", "value": 2},
	"強打": {"cost": 2, "type": "attack", "value": 5},
	"守り": {"cost": 1, "type": "block",  "value": 4},
	"大盾": {"cost": 2, "type": "block",  "value": 8},
	"疾風": {"cost": 0, "type": "draw",   "value": 1},
}

# 初期デッキ（B1では職業共通の汎用デッキ。職業別はB4で）
const STARTING_DECK := [
	"打撃", "打撃", "打撃", "打撃",
	"強打",
	"守り", "守り", "守り",
	"大盾",
	"疾風",
]

# 層ごとの敵。hp と attacks（毎ターンの攻撃をターン順に巡回）。
const LAYER_ENEMIES := {
	1: {"name": "スライム",   "hp": 18, "attacks": [4, 5, 4]},
	2: {"name": "ゴブリン",   "hp": 26, "attacks": [5, 6, 5, 8]},
	3: {"name": "オーガ",     "hp": 34, "attacks": [6, 8, 6, 10]},
	4: {"name": "ワイバーン", "hp": 46, "attacks": [8, 9, 11, 9]},
	5: {"name": "層の主",     "hp": 60, "attacks": [9, 11, 13, 11, 16]},
}

# ---- スピリット（墓地の再出現） ----
const SPIRIT_APPEAR_RATE := 0.40  # その層の墓地から1体選び、出現する確率
const SPIRIT_POW_BONUS := 1       # 出現時のPOW上昇（そのラン中永続。B5でカード化予定）

# ---- 永続化ファイル（user:// 以下に保存） ----
const GRAVEYARD_FILE := "graveyard.json"
const RUNS_CSV_FILE := "runs.csv"

# ---- 職業 ----
# 基準HP/POWからの配分差(mod)。職業別デッキ/能力はB4で追加予定。
const JOBS := [
	{"name": "戦士",     "hp_mod": 5,  "pow_mod": 0},   # HP35 / POW3
	{"name": "魔法使い", "hp_mod": -5, "pow_mod": 1},   # HP25 / POW4
	{"name": "盗賊",     "hp_mod": 0,  "pow_mod": 0},   # HP30 / POW3
]

# ---- 性格 ----
# メリット/デメリットを対で持たせる。
#   ※ fail_damage_bonus / reroll_on_fail はダイス時代の名残で、カード戦闘では現在未使用。
#     カード用の効果はB以降で貼り替える。
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

# ---- エンチャント ----
# 形容詞の付け替え(改名)を見るのが目的。今はPOW +1。B3でパッシブ効果に発展。
const ENCHANTMENTS := [
	{"adjective": "火炎の", "pow": 1},
	{"adjective": "静寂の", "pow": 1},
	{"adjective": "鋼の",   "pow": 1},
	{"adjective": "疾風の", "pow": 1},
	{"adjective": "深淵の", "pow": 1},
	{"adjective": "星屑の", "pow": 1},
]

# ---- 人名 ----
const NAMES := [
	"アレックス", "ベルナ", "カイト", "ディーナ", "エリオ",
	"フィオナ", "ガロ", "ハンナ", "イヴァン", "ジュナ",
	"クレア", "ルーカス", "ミラ", "ノア", "オルガ", "レン",
]
