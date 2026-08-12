# -*- coding: utf-8 -*-
"""撤退判断プロトタイプ（フェーズ2）。

「進むか、降りるか」の判断が緊張感を生むかを確かめるための使い捨てCUI。
フェーズ2では、降りる旨味となるスピリット報酬・墓地の永続化・ログ記録を足し、
20ラン回して判定できる状態にする。

使い方:
    python3 main.py                普通に1ラン遊ぶ
    python3 main.py --seed 42      乱数シードを固定（同じ展開になる）
    python3 main.py --reset        墓地(graveyard.json)を初期化してから遊ぶ
"""

import argparse
import csv
import json
import os
import random

import config


# ---------------------------------------------------------------------------
# 表示ヘルパー
# ---------------------------------------------------------------------------

def display_name(adv):
    """表示名を組み立てる：［性格］［形容詞］［職業］［名前］。

    形容詞は初期は空。エンチャント取得で上書きされると差し込まれる。
    """
    parts = [adv["personality"]["name"]]
    if adv["adjective"]:
        parts.append(adv["adjective"])
    parts.append(adv["job"]["name"])
    parts.append(adv["name"])
    return " ".join(parts)


def print_header(adv):
    """画面上部に常に表示名を出す（形容詞の上書きが見えるように）。"""
    print("=" * 48)
    print("  " + display_name(adv))
    print("  HP {hp} / POW {pow}".format(hp=adv["hp"], pow=adv["pow"]))
    print("=" * 48)


def prompt_choice(prompt, count):
    """1〜count の整数を標準入力から得る。範囲外は聞き直す。"""
    while True:
        raw = input(prompt).strip()
        if raw.isdigit():
            n = int(raw)
            if 1 <= n <= count:
                return n
        print("  1〜{n} の番号を入力してください。".format(n=count))


# ---------------------------------------------------------------------------
# 墓地（graveyard.json）の永続化
# ---------------------------------------------------------------------------

def load_graveyard(path):
    """墓地を読み込む。無ければ空の辞書を返す。

    構造: {"層番号(文字列)": [スピリットカード, ...], ...}
    """
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}


def save_graveyard(path, graveyard):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(graveyard, f, ensure_ascii=False, indent=2)


def record_spirit(graveyard, adv, layer):
    """撤退・クリア時に冒険者をスピリットカードとして墓地に追加する（上限なし）。"""
    card = {
        "display_name": display_name(adv),
        "layer": layer,
        "job": adv["job"]["name"],  # 職業に応じた効果の元（今は出現効果=POW+1で共通）
    }
    graveyard.setdefault(str(layer), []).append(card)


# ---------------------------------------------------------------------------
# スピリットの再出現
# ---------------------------------------------------------------------------

def try_spirit_appearance(adv, graveyard, layer):
    """層到達時、その層の墓地から1体だけ抽選し、確率で出現させる。

    墓地が何体増えても出現は1体まで。戻り値: 出現したら True。
    """
    cards = graveyard.get(str(layer), [])
    if not cards:
        return False
    card = random.choice(cards)
    if random.random() >= config.SPIRIT_APPEAR_RATE:
        return False
    adv["pow"] += config.SPIRIT_POW_BONUS
    print("◆ {name}が加勢した（POW +{p}）".format(
        name=card["display_name"], p=config.SPIRIT_POW_BONUS))
    return True


# ---------------------------------------------------------------------------
# 冒険者の生成
# ---------------------------------------------------------------------------

def create_adventurer():
    """性格をランダム決定し、職業をプレイヤーが選択して冒険者を生成する。"""
    personality = random.choice(config.PERSONALITIES)
    name = random.choice(config.NAMES)

    print("\n--- 冒険者の生成 ---")
    print("性格（ランダム確定）：{p}".format(p=personality["name"]))
    print("職業を選んでください：")
    for i, job in enumerate(config.JOBS, start=1):
        hp = config.INITIAL_HP + job["hp_mod"]
        pow_ = config.INITIAL_POW + job["pow_mod"]
        print("  {i}. {name}（HP {hp} / POW {pow}）".format(
            i=i, name=job["name"], hp=hp, pow=pow_))
    idx = prompt_choice("職業番号 > ", len(config.JOBS))
    job = config.JOBS[idx - 1]

    max_hp = config.INITIAL_HP + job["hp_mod"] + personality["hp_bonus"]
    adv = {
        "personality": personality,
        "job": job,
        "name": name,
        "adjective": "",  # 初期は形容詞なし
        "hp": max_hp,
        "max_hp": max_hp,  # 撤退記録の「HP半分」判定に使う
        "pow": config.INITIAL_POW + job["pow_mod"] + personality["pow_bonus"],
    }
    return adv


# ---------------------------------------------------------------------------
# 戦闘解決
# ---------------------------------------------------------------------------

def resolve_layer(adv, layer_num):
    """その層の戦闘を BATTLES_PER_LAYER 回勝つまで解決する。

    戻り値: 全滅したら False、層を突破したら True。
    """
    layer = config.LAYERS[layer_num]
    target = layer["target"]
    fail_damage = layer["fail_damage"] + adv["personality"]["fail_damage_bonus"]
    reroll = adv["personality"]["reroll_on_fail"]

    wins = 0
    while wins < config.BATTLES_PER_LAYER:
        roll = random.randint(1, config.DICE_SIDES)
        total = roll + adv["pow"]
        detail = "判定 {roll}+{pow}={total} vs {target}".format(
            roll=roll, pow=adv["pow"], total=total, target=target)
        success = total >= target

        # 無謀な：失敗しても1回だけ再判定
        if not success and reroll:
            r2 = random.randint(1, config.DICE_SIDES)
            t2 = r2 + adv["pow"]
            detail += " → 再判定 {roll}+{pow}={total}".format(
                roll=r2, pow=adv["pow"], total=t2)
            if t2 >= target:
                success = True

        if success:
            wins += 1
            print("  {detail} → 勝利({w}/{n})  残HP {hp}".format(
                detail=detail, w=wins, n=config.BATTLES_PER_LAYER,
                hp=adv["hp"]))
        else:
            adv["hp"] -= fail_damage
            print("  {detail} → 失敗  -{dmg}HP  残HP {hp}".format(
                detail=detail, dmg=fail_damage, hp=adv["hp"]))
            if adv["hp"] <= 0:
                return False
    return True


# ---------------------------------------------------------------------------
# エンチャント
# ---------------------------------------------------------------------------

def choose_enchant(adv, layer_num):
    """3択(性格により2〜4択)からエンチャントを選ぶ。形容詞を上書きしPOW上昇。

    ただしPOW上昇は性格の pow_gain_interval に従い、間引かれることがある。
    """
    n = adv["personality"]["enchant_choices"]
    n = min(n, len(config.ENCHANTMENTS))
    options = random.sample(config.ENCHANTMENTS, n)

    print("\n--- エンチャント選択（{n}択） ---".format(n=n))
    for i, ench in enumerate(options, start=1):
        print("  {i}. {adj}（POW +{pow}）".format(
            i=i, adj=ench["adjective"], pow=ench["pow"]))
    idx = prompt_choice("エンチャント番号 > ", n)
    chosen = options[idx - 1]

    adv["adjective"] = chosen["adjective"]  # 形容詞は常に上書き

    interval = adv["personality"]["pow_gain_interval"]
    if layer_num % interval == 0:
        adv["pow"] += chosen["pow"]
        print("  → {name}（POW +{pow}）".format(
            name=display_name(adv), pow=chosen["pow"]))
    else:
        print("  → {name}（この層ではPOWは上がらない）".format(
            name=display_name(adv)))


# ---------------------------------------------------------------------------
# 撤退 / 続行
# ---------------------------------------------------------------------------

def ask_retreat(adv, current_layer):
    """★検証対象。判断材料を必ず表示してから撤退/続行を問う。

    戻り値: 撤退なら True、続行なら False。
    """
    next_layer = current_layer + 1
    nxt = config.LAYERS[next_layer]

    print("\n" + "-" * 48)
    print("★ 撤退 / 続行 の選択（第{cur}層クリア）".format(cur=current_layer))
    print("  現在  ： HP {hp} / POW {pow} / 到達 第{cur}層".format(
        hp=adv["hp"], pow=adv["pow"], cur=current_layer))
    print("  次の層： 第{n}層  目標値 {t} / 失敗ダメージ {d}".format(
        n=next_layer, t=nxt["target"],
        d=nxt["fail_damage"] + adv["personality"]["fail_damage_bonus"]))
    print("  撤退すると記録される表示名： {name}".format(name=display_name(adv)))
    print("-" * 48)
    print("  1. 撤退する（ラン終了）")
    print("  2. 続行する（第{n}層へ）".format(n=next_layer))
    idx = prompt_choice("選択 > ", 2)
    return idx == 1


# ---------------------------------------------------------------------------
# ラン進行
# ---------------------------------------------------------------------------

def run_game(graveyard):
    """1ランを進める。ログ記録用の辞書を返す。"""
    adv = create_adventurer()

    ending = None       # "death" / "retreat" / "clear"
    reached = 0
    spirit_appearances = 0

    for layer_num in range(1, config.MAX_LAYER + 1):
        reached = layer_num
        print("\n\n########## 第{n}層 ##########".format(n=layer_num))
        print_header(adv)

        # a. スピリット抽選（その層の墓地から1体だけ）
        if try_spirit_appearance(adv, graveyard, layer_num):
            spirit_appearances += 1

        # b. 戦闘を解決
        survived = resolve_layer(adv, layer_num)
        if not survived:
            ending = "death"
            break

        # d. HP回復
        adv["hp"] += config.HP_RECOVER_PER_LAYER
        print("\n第{n}層突破。HP +{r} → 残HP {hp}".format(
            n=layer_num, r=config.HP_RECOVER_PER_LAYER, hp=adv["hp"]))

        # e. エンチャント
        choose_enchant(adv, layer_num)

        # 最終層クリアなら自動的にラン終了
        if layer_num == config.MAX_LAYER:
            ending = "clear"
            break

        # ★ 撤退 / 続行
        if ask_retreat(adv, layer_num):
            ending = "retreat"
            break

    # 記録（撤退・クリアのみ。全滅は何も残さない）
    hp_ratio = ""
    recorded = False
    if ending == "retreat":
        hp_ratio = round(adv["hp"] / adv["max_hp"], 2)
        # 無謀な：撤退時HPが半分以下だと記録失敗
        if adv["personality"]["retreat_needs_half_hp"] and adv["hp"] * 2 <= adv["max_hp"]:
            print("\n※ HPが半分以下のため、スピリットの記録に失敗した。")
        else:
            record_spirit(graveyard, adv, reached)
            recorded = True
    elif ending == "clear":
        record_spirit(graveyard, adv, reached)
        recorded = True

    print_result(adv, reached, ending, spirit_appearances, recorded)

    return {
        "adv": adv,
        "reached": reached,
        "ending": ending,
        "spirit_appearances": spirit_appearances,
        "hp_ratio": hp_ratio,
    }


def print_result(adv, reached, ending, spirit_appearances, recorded):
    labels = {
        "death": "全滅（何も記録されない）",
        "retreat": "撤退",
        "clear": "第{n}層クリア".format(n=config.MAX_LAYER),
    }
    print("\n" + "=" * 48)
    print("  ラン終了")
    print("  最終表示名   ： {name}".format(name=display_name(adv)))
    print("  到達層       ： 第{n}層".format(n=reached))
    print("  結末         ： {label}".format(label=labels.get(ending, ending)))
    print("  最終HP/POW   ： {hp} / {pow}".format(hp=adv["hp"], pow=adv["pow"]))
    print("  スピリット出現： {n}回".format(n=spirit_appearances))
    if ending in ("retreat", "clear"):
        print("  墓地への記録 ： {s}".format(s="成功" if recorded else "失敗"))
    print("=" * 48)


# ---------------------------------------------------------------------------
# ログ（runs.csv）
# ---------------------------------------------------------------------------

CSV_HEADER = [
    "run_id", "seed", "性格", "職業", "名前", "最終形容詞", "最終表示名",
    "到達層", "結末", "最終HP", "最終POW",
    "スピリット出現回数", "撤退時の残HP割合", "迷ったか",
]


def next_run_id(path):
    """runs.csv の既存行数から次の run_id を決める。"""
    if not os.path.exists(path):
        return 1
    with open(path, "r", encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    # ヘッダー行を除いたデータ行数 + 1
    data_rows = [r for r in rows if r and r[0] != "run_id"]
    return len(data_rows) + 1


def append_run_log(path, result, seed, hesitation):
    """1ラン1行で runs.csv に追記する。無ければヘッダーを書く。"""
    adv = result["adv"]
    run_id = next_run_id(path)
    write_header = not os.path.exists(path)
    row = [
        run_id,
        "" if seed is None else seed,
        adv["personality"]["name"],
        adv["job"]["name"],
        adv["name"],
        adv["adjective"],
        display_name(adv),
        result["reached"],
        result["ending"],
        adv["hp"],
        adv["pow"],
        result["spirit_appearances"],
        result["hp_ratio"],
        hesitation,
    ]
    with open(path, "a", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        if write_header:
            writer.writerow(CSV_HEADER)
        writer.writerow(row)


# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

def parse_args():
    parser = argparse.ArgumentParser(description="撤退判断プロトタイプ")
    parser.add_argument("--seed", type=int, default=None,
                        help="乱数シードを固定する（同じシードなら同じ展開）")
    parser.add_argument("--reset", action="store_true",
                        help="墓地(graveyard.json)を初期化してから開始する")
    return parser.parse_args()


def main():
    args = parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    if args.reset:
        save_graveyard(config.GRAVEYARD_FILE, {})
        print("墓地を初期化しました。")

    graveyard = load_graveyard(config.GRAVEYARD_FILE)

    print("撤退判断プロトタイプ v0.2（フェーズ2）")
    result = run_game(graveyard)

    # 墓地を保存
    save_graveyard(config.GRAVEYARD_FILE, graveyard)

    # 検証の主データ：迷ったか（1〜5）を聞いて記録
    print("\n今回の撤退/続行の判断で、どれくらい迷いましたか？")
    print("  1（即決） 〜 5（かなり悩んだ）")
    hesitation = prompt_choice("迷ったか > ", 5)
    append_run_log(config.RUNS_CSV_FILE, result, args.seed, hesitation)
    print("記録しました（{csv}）。".format(csv=config.RUNS_CSV_FILE))


if __name__ == "__main__":
    main()
