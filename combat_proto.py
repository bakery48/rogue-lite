# -*- coding: utf-8 -*-
"""戦闘プロトタイプ・スライス1（デッキ戦闘の核だけ）。

目的は「毎ターン何を切るか」の手触りを最短で確かめること。
1戦闘のみ。層・撤退・パッシブ・職業・スピリットはまだ入れない（後続スライス）。
カード・数値は全て下の CONFIG でいじれる置き石。

    python3 combat_proto.py            普通に1戦
    python3 combat_proto.py --seed 42  乱数固定
"""

import argparse
import random

# ===========================================================================
# CONFIG（ここだけ触れば調整できる）
# ===========================================================================

PLAYER_HP = 20
PLAYER_POW = 3
ENERGY_PER_TURN = 3
HAND_SIZE = 5

# カード定義。damage は「POW + value」、block は「value」、draw は「value枚」。
CARDS = {
	"打撃": {"cost": 1, "type": "attack", "value": 2},   # ダメージ POW+2
	"強打": {"cost": 2, "type": "attack", "value": 5},   # ダメージ POW+5
	"守り": {"cost": 1, "type": "block",  "value": 4},   # 防御 4
	"大盾": {"cost": 2, "type": "block",  "value": 8},   # 防御 8
	"疾風": {"cost": 0, "type": "draw",   "value": 1},   # 1枚引く
}

# 初期デッキ（スライス1は職業差なしの汎用デッキ）
STARTING_DECK = [
	"打撃", "打撃", "打撃", "打撃",
	"強打",
	"守り", "守り", "守り",
	"大盾",
	"疾風",
]

# 敵。attacks は毎ターンの攻撃予告をターン順に巡回。
ENEMY = {
	"name": "層の番人",
	"hp": 30,
	"attacks": [6, 6, 9, 6, 12],
}


# ===========================================================================
# 状態
# ===========================================================================

def make_player():
	deck = STARTING_DECK[:]
	random.shuffle(deck)
	return {
		"hp": PLAYER_HP,
		"pow": PLAYER_POW,
		"block": 0,
		"energy": 0,
		"draw_pile": deck,
		"hand": [],
		"discard": [],
	}


def make_enemy():
	return {"name": ENEMY["name"], "hp": ENEMY["hp"], "turn": 0}


# ===========================================================================
# デッキ操作
# ===========================================================================

def draw_cards(p, n):
	drawn = 0
	for _ in range(n):
		if not p["draw_pile"]:
			if not p["discard"]:
				break  # 引く札が尽きた
			p["draw_pile"] = p["discard"]
			p["discard"] = []
			random.shuffle(p["draw_pile"])
		p["hand"].append(p["draw_pile"].pop())
		drawn += 1
	return drawn


def start_turn(p):
	p["block"] = 0
	p["energy"] = ENERGY_PER_TURN
	draw_cards(p, HAND_SIZE - len(p["hand"]))


def enemy_intent(e):
	pattern = ENEMY["attacks"]
	return pattern[e["turn"] % len(pattern)]


# ===========================================================================
# 表示
# ===========================================================================

def show_state(p, e):
	print("\n" + "=" * 50)
	print("  敵：{name}  HP {hp}   … 次の攻撃 ▶ {atk}".format(
		name=e["name"], hp=e["hp"], atk=enemy_intent(e)))
	print("-" * 50)
	print("  あなた  HP {hp}  防御 {blk}  POW {pow}  E {en}/{emax}".format(
		hp=p["hp"], blk=p["block"], pow=p["pow"],
		en=p["energy"], emax=ENERGY_PER_TURN))
	print("  手札：")
	for i, name in enumerate(p["hand"], start=1):
		c = CARDS[name]
		print("   {i}. {name}  (c{cost})  {desc}".format(
			i=i, name=name, cost=c["cost"], desc=card_desc(p, name)))
	print("  （山札{d} / 捨札{s}）".format(d=len(p["draw_pile"]), s=len(p["discard"])))
	print("=" * 50)


def card_desc(p, name):
	c = CARDS[name]
	if c["type"] == "attack":
		return "攻撃 {dmg}".format(dmg=p["pow"] + c["value"])
	if c["type"] == "block":
		return "防御 {v}".format(v=c["value"])
	if c["type"] == "draw":
		return "{v}枚引く".format(v=c["value"])
	return ""


# ===========================================================================
# カード効果
# ===========================================================================

def play_card(p, e, idx):
	"""手札の idx(0始まり) を使う。使えたら True。"""
	name = p["hand"][idx]
	c = CARDS[name]
	if c["cost"] > p["energy"]:
		print("  エネルギーが足りない。")
		return False

	p["energy"] -= c["cost"]
	p["hand"].pop(idx)

	if c["type"] == "attack":
		dmg = p["pow"] + c["value"]
		e["hp"] -= dmg
		print("  ▶ {name}：{dmg} ダメージ（敵HP {hp}）".format(
			name=name, dmg=dmg, hp=max(e["hp"], 0)))
	elif c["type"] == "block":
		p["block"] += c["value"]
		print("  ▶ {name}：防御 +{v}（防御 {blk}）".format(
			name=name, v=c["value"], blk=p["block"]))
	elif c["type"] == "draw":
		got = draw_cards(p, c["value"])
		print("  ▶ {name}：{n}枚引いた".format(name=name, n=got))

	p["discard"].append(name)
	return True


def enemy_attack(p, e):
	atk = enemy_intent(e)
	dmg = max(0, atk - p["block"])
	p["hp"] -= dmg
	blocked = atk - dmg
	print("\n  ◆ {name}の攻撃 {atk}（防御{blk}で {b} 軽減）→ {d} ダメージ  残HP {hp}".format(
		name=e["name"], atk=atk, blk=p["block"], b=blocked, d=dmg, hp=p["hp"]))
	e["turn"] += 1


# ===========================================================================
# 戦闘ループ
# ===========================================================================

def combat():
	p = make_player()
	e = make_enemy()

	print("戦闘プロトタイプ・スライス1")
	print("入力：数字=そのカードを使う / e=ターン終了 / q=中断")

	while True:
		start_turn(p)

		# プレイヤーのターン
		while True:
			show_state(p, e)
			raw = input("> ").strip().lower()
			if raw == "q":
				print("中断。")
				return
			if raw == "e":
				break
			if raw.isdigit():
				i = int(raw)
				if 1 <= i <= len(p["hand"]):
					play_card(p, e, i - 1)
					if e["hp"] <= 0:
						print("\n★ 敵を倒した！ 勝利。")
						return
					continue
			print("  数字（手札番号）/ e / q を入力。")

		# ターン終了：手札を捨てて敵の攻撃
		p["discard"].extend(p["hand"])
		p["hand"] = []
		enemy_attack(p, e)
		if p["hp"] <= 0:
			print("\n× 倒れた。敗北。")
			return


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("--seed", type=int, default=None)
	args = parser.parse_args()
	if args.seed is not None:
		random.seed(args.seed)
	combat()


if __name__ == "__main__":
	main()
