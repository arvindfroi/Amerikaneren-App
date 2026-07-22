#!/usr/bin/env python3
"""Robust analyse av de parrede rundedifferansene i ~/ismcts/resultater.jsonl.

Utbetalingsfordelingen i Amerikaneren har svært tunge haler (Amerikaner
±50, solo ±100 ved mål på 100), så et snitt med standardfeil kan se
signifikant ut på grunn av en håndfull runder. Derfor rapporteres fire ting
ved siden av hverandre:

  * snitt ± SE  (og t = snitt/SE)
  * 10 % trimmet snitt – tåler de tunge halene
  * tegntest    – bryr seg bare om FORTEGNET på hver runde
  * bootstrap-KI (persentil, 20 000 gjentrekninger)

Bruk:
    analyse.py merke [merke ...]        – én rad per merke
    analyse.py --slaa-sammen m1 m2      – slår sammen rundene før analysen
"""
import json
import math
import os
import random
import sys

STI = os.path.expanduser("~/ismcts/resultater.jsonl")


def les(merker):
    """Rundedifferansene per merke, siste fullførte kjøring vinner."""
    ut = {}
    with open(STI, encoding="utf-8") as f:
        for linje in f:
            try:
                d = json.loads(linje)
            except json.JSONDecodeError:
                continue
            if d.get("maaling") != "h2h":
                continue
            m = d.get("merke")
            if merker and m not in merker:
                continue
            diff = d.get("differanser")
            if not diff:
                continue
            ut.setdefault(m, [])
            # Flere kjøringer med samme merke, men ulike «fra», slås sammen.
            ut[m].append((d.get("fra", 0), diff, d))
    return ut


def trimmet(x, andel=0.1):
    s = sorted(x)
    k = int(len(s) * andel)
    kjerne = s[k:len(s) - k] if len(s) - 2 * k > 0 else s
    return sum(kjerne) / len(kjerne), len(kjerne)


def tegntest(x):
    pluss = sum(1 for v in x if v > 0)
    minus = sum(1 for v in x if v < 0)
    n = pluss + minus
    if n == 0:
        return pluss, minus, 1.0
    # Tosidig binomial mot p = 0.5, normaltilnærming med kontinuitetskorreksjon.
    k = max(pluss, minus)
    z = (k - 0.5 - n / 2) / math.sqrt(n / 4)
    p = 2 * (1 - 0.5 * (1 + math.erf(z / math.sqrt(2))))
    return pluss, minus, min(1.0, p)


def bootstrap(x, gjentrekninger=20000, frø=12345):
    rng = random.Random(frø)
    n = len(x)
    snitt = []
    for _ in range(gjentrekninger):
        s = 0.0
        for _ in range(n):
            s += x[rng.randrange(n)]
        snitt.append(s / n)
    snitt.sort()
    lav = snitt[int(0.025 * gjentrekninger)]
    høy = snitt[int(0.975 * gjentrekninger) - 1]
    andelOverNull = sum(1 for v in snitt if v > 0) / gjentrekninger
    return lav, høy, andelOverNull


def rapporter(navn, x, ekstra=""):
    n = len(x)
    m = sum(x) / n
    var = sum((v - m) ** 2 for v in x) / (n - 1)
    se = math.sqrt(var / n)
    tm, nk = trimmet(x)
    pluss, minus, p = tegntest(x)
    lav, høy, over = bootstrap(x)
    print(f"── {navn} {ekstra}")
    print(f"   n           = {n} parrede runder")
    print(f"   snitt       = {m:+.3f} ± {se:.3f}  (t = {m/se:.2f})")
    print(f"   trimmet 10% = {tm:+.3f}  (n_kjerne = {nk})")
    print(f"   tegntest    = {pluss} positive mot {minus} negative "
          f"({100*pluss/max(1,pluss+minus):.1f} %), p = {p:.4f}")
    print(f"   bootstrap   = [{lav:+.3f}, {høy:+.3f}]  "
          f"(andel gjentrekninger over 0: {100*over:.1f} %)")
    return {"navn": navn, "n": n, "snitt": m, "se": se, "trimmet": tm,
            "pluss": pluss, "minus": minus, "tegntest_p": p,
            "bootstrap_lav": lav, "bootstrap_hoy": høy}


def main():
    args = sys.argv[1:]
    slåSammen = False
    parret = False
    if args and args[0] == "--slaa-sammen":
        slåSammen = True
        args = args[1:]
    elif args and args[0] == "--parret":
        parret = True
        args = args[1:]
    if parret and len(args) == 2:
        # Punktene er kjørt på de SAMME utdelingene, så differansen mellom
        # dem kan tas runde for runde. Det fjerner utdelingsvariansen, som
        # ellers dominerer helt.
        data = les(set(args))
        a, b = [], []
        for _, d, _ in data.get(args[0], []):
            a += d
        for _, d, _ in data.get(args[1], []):
            b += d
        if len(a) != len(b) or not a:
            print(f"── kan ikke parre {args[0]} og {args[1]}: "
                  f"n = {len(a)} mot {len(b)}")
            return
        rapporter(f"{args[0]} − {args[1]}", [x - y for x, y in zip(a, b)], "(parret)")
        return
    if not args:
        print(__doc__)
        return
    data = les(set(args))
    if slåSammen:
        alle = []
        for m in args:
            for _, diff, _ in data.get(m, []):
                alle += diff
        if alle:
            rapporter("+".join(args), alle, "(slått sammen)")
        return
    for m in args:
        biter = data.get(m, [])
        if not biter:
            print(f"── {m}: ingen data")
            continue
        alle = []
        for _, diff, _ in biter:
            alle += diff
        d = biter[-1][2]
        ekstra = (f"[ISMCTS {d.get('ismcts_iter_per_trekk', 0):.0f} iter/trekk, "
                  f"PIMC {d.get('pimc_verdener_per_trekk', 0):.0f} verdener/trekk]")
        rapporter(m, alle, ekstra)


if __name__ == "__main__":
    main()
