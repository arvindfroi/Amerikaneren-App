# -*- coding: utf-8 -*-
"""Aggregerer lekkasjeloggene: hvor taper MesterAI poeng?"""
import glob, json, math, sys, os
from collections import Counter

STIKK_TOTALT = 12
MAAL_POENG = 100


def les(monster):
    ut = []
    for f in sorted(glob.glob(os.path.expanduser(monster))):
        for l in open(f):
            l = l.strip()
            if not l:
                continue
            try:
                ut.append(json.loads(l))
            except Exception:
                pass
    return ut


def snitt_se(xs):
    n = len(xs)
    if n == 0:
        return (0.0, 0.0, 0)
    m = sum(xs) / float(n)
    if n < 2:
        return (m, 0.0, n)
    v = sum((x - m) ** 2 for x in xs) / (n - 1.0)
    return (m, math.sqrt(v / n), n)


def fmt(t):
    m, se, n = t
    return "%7.3f +/- %.3f (n=%d)" % (m, 1.96 * se, n)


def poeng_budgiver(bud, lagstikk):
    if bud >= 2000:
        return MAAL_POENG if lagstikk == STIKK_TOTALT else -MAAL_POENG
    if bud >= 1000:
        return (MAAL_POENG // 2) if lagstikk == STIKK_TOTALT else -(MAAL_POENG // 2)
    return (2 * bud) if lagstikk >= bud else -(2 * bud)


def poeng_makker(bud, lagstikk):
    if bud >= 2000:
        return 0
    if bud >= 1000:
        return (MAAL_POENG // 4) if lagstikk == STIKK_TOTALT else -(MAAL_POENG // 4)
    return bud if lagstikk >= bud else -bud


def lagpoeng(bud, lagstikk):
    return poeng_budgiver(bud, lagstikk) + poeng_makker(bud, lagstikk)


def main(monster, tittel):
    d = les(monster)
    if not d:
        print("ingen data for " + monster)
        return
    print("=" * 78)
    print("%s   runder: %d" % (tittel, len(d)))
    print("=" * 78)

    tall = [r for r in d if r["bud"] < 1000]
    amer = [r for r in d if r["bud"] >= 1000]
    print("")
    print("-- MELDINGSFORDELING --")
    print("  tallbud: %d (%.0f %%), amerikaner/solo: %d (%.0f %%)"
          % (len(tall), 100.0 * len(tall) / len(d), len(amer), 100.0 * len(amer) / len(d)))
    if amer:
        print("  amerikaner/solo klarte: %d av %d" % (sum(1 for r in amer if r["klarte"]), len(amer)))

    print("")
    print("-- 1. BUDGIVNING (bare tallbud) --")
    holdt = [1.0 if r["klarte"] else 0.0 for r in tall]
    print("  kontrakten holdt:            " + fmt(snitt_se(holdt)))
    print("  faktiske lagstikk minus bud: " + fmt(snitt_se([r["lagstikk"] - r["bud"] for r in tall])))
    print("  DD-par minus bud:            " + fmt(snitt_se([r["ddpar"] - r["bud"] for r in tall])))
    print("  snittbud %.2f | snitt lagstikk %.2f | snitt DD-par %.2f"
          % (sum(r["bud"] for r in tall) / float(len(tall)),
             sum(r["lagstikk"] for r in tall) / float(len(tall)),
             sum(r["ddpar"] for r in tall) / float(len(tall))))
    c = Counter(r["lagstikk"] - r["bud"] for r in tall)
    print("  fordeling (lagstikk - bud):  " + "  ".join("%+d:%d" % (k, c[k]) for k in sorted(c)))
    c2 = Counter(r["ddpar"] - r["bud"] for r in tall)
    print("  fordeling (DD-par  - bud):   " + "  ".join("%+d:%d" % (k, c2[k]) for k in sorted(c2)))
    cb = Counter(r["bud"] for r in tall)
    print("  budnivaa:                    " + "  ".join("%d:%d" % (k, cb[k]) for k in sorted(cb)))

    tap_bud = []
    for r in tall:
        par = r["ddpar"]
        beste = max([0] + [lagpoeng(n, par) for n in range(5, 13)])
        tap_bud.append((beste - lagpoeng(r["bud"], par)) / 2.0)
    print("  budtap med fasit (poeng/runde per lagsete): " + fmt(snitt_se(tap_bud)))

    g = [r for r in d if r.get("gp_aktuell", -1) >= 0]
    if g:
        bedre = [1.0 if max(r["gp_andre"]) > r["gp_aktuell"] else 0.0 for r in g]
        print("  et annet sete hadde hoyere fullinfo-potensial: " + fmt(snitt_se(bedre)))

    print("")
    print("-- 2. VRAK, TRUMF OG ETTERLYSNING (fullinfo-utrulling som overdommer) --")
    if g:
        avvik = [r["gp_aktuell"] - r["ddpar"] for r in g]
        lik = sum(1 for a in avvik if a == 0)
        print("  kalibrering (gp_aktuell - DD-par): " + fmt(snitt_se(avvik)))
        print("    identisk i %d av %d runder (%.0f %%)" % (lik, len(g), 100.0 * lik / len(g)))
        tt = [max(0, max(r["gp_per_trumf"]) - r["gp_sammetrumf"]) for r in g]
        tv = [max(0, r["gp_sammetrumf"] - r["gp_sammevrak"]) for r in g]
        to = [max(0, r["gp_sammevrak"] - r["gp_aktuell"]) for r in g]
        ta = [max(0, r["gp_beste"] - r["gp_aktuell"]) for r in g]
        print("  tap i stikk - trumffarge:   " + fmt(snitt_se(tt)))
        print("  tap i stikk - vrak:         " + fmt(snitt_se(tv)))
        print("  tap i stikk - etterlysning: " + fmt(snitt_se(to)))
        print("  tap i stikk - samlet:       " + fmt(snitt_se(ta)))
        pt = []
        for r in g:
            if r["bud"] >= 1000:
                continue
            ekstra = max(0, r["gp_beste"] - r["gp_aktuell"])
            pt.append((lagpoeng(r["bud"], r["ddpar"] + ekstra) - lagpoeng(r["bud"], r["ddpar"])) / 2.0)
        print("  -> poeng/runde per lagsete: " + fmt(snitt_se(pt)))

    print("")
    print("-- 3. KORTSPILL (dobbeltdummy-fasit) --")
    print("  DD-par minus faktiske lagstikk: " + fmt(snitt_se([r["ddpar"] - r["lagstikk"] for r in d])))
    print("  W-endring stikk 1-2 samlet:     " + fmt(snitt_se([sum(r.get("tidlig_delta", [])) for r in d])))
    print("    (negativ = budgiverlaget mistet stikk, positiv = forsvaret ga bort stikk)")
    t1 = [r["tidlig_delta"][0] for r in d if len(r.get("tidlig_delta", [])) > 0]
    t2 = [r["tidlig_delta"][1] for r in d if len(r.get("tidlig_delta", [])) > 1]
    print("    stikk 1: " + fmt(snitt_se(t1)))
    print("    stikk 2: " + fmt(snitt_se(t2)))

    lagtap, forsvarstap, budgivertap, makkertap = [], [], [], []
    for r in d:
        lag = set([r["budgiver"]])
        if r["makker"] >= 0:
            lag.add(r["makker"])
        lagtap.append(sum(r["ddtap"][s] for s in range(4) if s in lag))
        forsvarstap.append(sum(r["ddtap"][s] for s in range(4) if s not in lag))
        budgivertap.append(r["ddtap"][r["budgiver"]])
        if r["makker"] >= 0:
            makkertap.append(r["ddtap"][r["makker"]])
    print("  DD-tap fra stikk 3 og ut (stikk/runde):")
    print("    budgiverlaget samlet: " + fmt(snitt_se(lagtap)))
    print("      derav budgiver:     " + fmt(snitt_se(budgivertap)))
    print("      derav makker:       " + fmt(snitt_se(makkertap)))
    print("    forsvaret (3 seter):  " + fmt(snitt_se(forsvarstap)))
    print("      per forsvarssete:   " + fmt(snitt_se([x / 3.0 for x in forsvarstap])))

    pk_lag, pk_for = [], []
    for r in d:
        if r["bud"] >= 1000:
            continue
        lag = set([r["budgiver"]])
        if r["makker"] >= 0:
            lag.add(r["makker"])
        lt = sum(r["ddtap"][s] for s in range(4) if s in lag)
        ft = sum(r["ddtap"][s] for s in range(4) if s not in lag)
        na = lagpoeng(r["bud"], r["lagstikk"])
        pk_lag.append((lagpoeng(r["bud"], min(STIKK_TOTALT, r["lagstikk"] + lt)) - na) / 2.0)
        pk_for.append((na - lagpoeng(r["bud"], max(0, r["lagstikk"] - ft))) / 3.0)
    print("  -> budgiverlagets kortspilltap (poeng/runde per lagsete): " + fmt(snitt_se(pk_lag)))
    print("  -> forsvarets kortspilltap    (poeng/runde per sete):     " + fmt(snitt_se(pk_for)))

    print("")
    print("-- 4. POENGREGNSKAP --")
    for rolle in ("budgiver", "makker", "forsvar"):
        ps = []
        for r in d:
            for s in range(4):
                if rolle == "budgiver" and s == r["budgiver"]:
                    ps.append(r["poeng"][s])
                elif rolle == "makker" and s == r["makker"]:
                    ps.append(r["poeng"][s])
                elif rolle == "forsvar" and s != r["budgiver"] and s != r["makker"]:
                    ps.append(r["poeng"][s])
        print("  %-9s poeng/runde: %s" % (rolle, fmt(snitt_se(ps))))
    print("  alle seter:          " + fmt(snitt_se([r["poeng"][s] for r in d for s in range(4)])))

    # sete 0 spesielt (nyttig i mot-vanskelig-oppsettet)
    print("  sete 0 poeng/runde:  " + fmt(snitt_se([r["poeng"][0] for r in d])))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
