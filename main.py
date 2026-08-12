# -*- coding: utf-8 -*-
"""撤退判断プロトタイプ（フェーズ1）。

「進むか、降りるか」の判断が緊張感を生むかを確かめるための使い捨てCUI。
このフェーズでは 1ラン を最後まで通すことだけを目的とする。
スピリット記録・ログ出力・シード固定はフェーズ2で追加する。
"""

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

    adv = {
        "personality": personality,
        "job": job,
        "name": name,
        "adjective": "",  # 初期は形容詞なし
        "hp": config.INITIAL_HP + job["hp_mod"] + personality["hp_bonus"],
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
    attempt = 0
    while wins < config.BATTLES_PER_LAYER:
        attempt += 1
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

def run_game():
    adv = create_adventurer()

    ending = None       # "death" / "retreat" / "clear"
    reached = 0

    for layer_num in range(1, config.MAX_LAYER + 1):
        reached = layer_num
        print("\n\n########## 第{n}層 ##########".format(n=layer_num))
        print_header(adv)

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

    print_result(adv, reached, ending)


def print_result(adv, reached, ending):
    labels = {
        "death": "全滅（何も記録されない）",
        "retreat": "撤退（スピリットとして記録予定）",
        "clear": "第{n}層クリア（記録予定）".format(n=config.MAX_LAYER),
    }
    print("\n" + "=" * 48)
    print("  ラン終了")
    print("  最終表示名 ： {name}".format(name=display_name(adv)))
    print("  到達層     ： 第{n}層".format(n=reached))
    print("  結末       ： {label}".format(label=labels.get(ending, ending)))
    print("  最終HP/POW ： {hp} / {pow}".format(hp=adv["hp"], pow=adv["pow"]))
    print("=" * 48)


def main():
    print("撤退判断プロトタイプ v0.1（フェーズ1）")
    run_game()


if __name__ == "__main__":
    main()
