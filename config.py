# -*- coding: utf-8 -*-
"""数値・定義の集約ファイル。

バランス調整はロジック(main.py)を開かず、このファイルだけを編集して行う。
性格・エンチャント・職業・人名は、リストに1行足すだけで追加できる。
"""

# ---- 基本パラメータ ----
INITIAL_HP = 10            # 冒険者の基準HP
INITIAL_POW = 3           # 冒険者の基準POW

BATTLES_PER_LAYER = 3      # 各層で必要な勝利数
HP_RECOVER_PER_LAYER = 3   # 層クリアごとのHP回復量
MAX_LAYER = 5              # 最終層。ここをクリアするとラン終了

DICE_SIDES = 6             # 戦闘判定に使うダイスの面数(1d6)

DEFAULT_ENCHANT_CHOICES = 3  # エンチャント選択肢数の既定値

# ---- スピリット（墓地の再出現） ----
SPIRIT_APPEAR_RATE = 0.40  # その層の墓地から1体選び、出現する確率
SPIRIT_POW_BONUS = 1       # 出現時のPOW上昇（そのラン中永続）

# ---- 永続化ファイル ----
GRAVEYARD_FILE = "graveyard.json"  # 墓地（層ごとにスピリットを保持）
RUNS_CSV_FILE = "runs.csv"         # 1ラン1行の記録

# ---- 層ごとの数値 ----
# キーは層番号(1始まり)。target=目標値, fail_damage=失敗時ダメージ。
LAYERS = {
    1: {"target": 6,  "fail_damage": 1},
    2: {"target": 7,  "fail_damage": 2},
    3: {"target": 9,  "fail_damage": 3},
    4: {"target": 10, "fail_damage": 4},
    5: {"target": 12, "fail_damage": 5},
}

# ---- 職業 ----
# 基準HP/POWからの配分差(mod)だけを持つ。1行足せば追加できる。
#   hp_mod  : INITIAL_HP への補正
#   pow_mod : INITIAL_POW への補正
JOBS = [
    {"name": "戦士",     "hp_mod": +2, "pow_mod": 0},   # HP10+2=12 / POW3
    {"name": "魔法使い", "hp_mod": -2, "pow_mod": +1},  # HP10-2=8  / POW4
    {"name": "盗賊",     "hp_mod": 0,  "pow_mod": 0},   # HP10      / POW3
]

# ---- 性格 ----
# 必ずメリット/デメリットを対で持たせる。1行足せば追加できる。
# フィールド:
#   name                  : 表示上の形容詞(例「シャイな」)
#   hp_bonus              : 初期HP補正
#   pow_bonus             : 初期POW補正
#   enchant_choices       : エンチャント選択肢数
#   pow_gain_interval     : POW上昇の間隔(層)。2なら「2層に1回」だけPOWが上がる
#   fail_damage_bonus     : 戦闘失敗時ダメージへの補正
#   reroll_on_fail        : 失敗しても1回だけ再判定するか
#   retreat_needs_half_hp : 撤退記録にHP半分以上が必要か(フェーズ2で使用)
PERSONALITIES = [
    {"name": "シャイな",       "hp_bonus": 0, "pow_bonus": 1,
     "enchant_choices": 2, "pow_gain_interval": 1,
     "fail_damage_bonus": 0, "reroll_on_fail": False,
     "retreat_needs_half_hp": False},
    {"name": "目立ちたがりな", "hp_bonus": 0, "pow_bonus": 0,
     "enchant_choices": 4, "pow_gain_interval": 1,
     "fail_damage_bonus": 1, "reroll_on_fail": False,
     "retreat_needs_half_hp": False},
    {"name": "慎重な",         "hp_bonus": 3, "pow_bonus": 0,
     "enchant_choices": 3, "pow_gain_interval": 2,
     "fail_damage_bonus": 0, "reroll_on_fail": False,
     "retreat_needs_half_hp": False},
    {"name": "無謀な",         "hp_bonus": 0, "pow_bonus": 0,
     "enchant_choices": 3, "pow_gain_interval": 1,
     "fail_damage_bonus": 0, "reroll_on_fail": True,
     "retreat_needs_half_hp": True},
]

# ---- エンチャント ----
# 形容詞の付け替え(改名の手触り)を見るのが目的。効果は全てPOW +1。
# 1行足せば追加できる。
ENCHANTMENTS = [
    {"adjective": "火炎の", "pow": 1},
    {"adjective": "静寂の", "pow": 1},
    {"adjective": "鋼の",   "pow": 1},
    {"adjective": "疾風の", "pow": 1},
    {"adjective": "深淵の", "pow": 1},
    {"adjective": "星屑の", "pow": 1},
]

# ---- 人名 ----
NAMES = [
    "アレックス", "ベルナ", "カイト", "ディーナ", "エリオ",
    "フィオナ", "ガロ", "ハンナ", "イヴァン", "ジュナ",
    "クレア", "ルーカス", "ミラ", "ノア", "オルガ", "レン",
]
