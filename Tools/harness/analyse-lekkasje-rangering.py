# -*- coding: utf-8 -*-
"""Rangerer lekkasjene i poeng per runde per SETE (snitt over alle roller)."""
import glob, json, math, os, sys

STIKK = 12
MAAL = 100


def les(m):
    ut = []
    for f in sorted(glob.glob(os.path.expanduser(m))):
        for l in open(f):
            l = l.strip()
            if l:
                try:
                    ut.append(json.loads(l))
                except Exception:
                    pass
    return ut


def se(xs):
    n = len(xs)
    if n < 2:
        return (sum(xs) / max(1, n), 0.0, n)
    mu = sum(xs) / float(n)
    v = sum((x - mu) ** 2 for x in xs) / (n - 1.0)
    return (mu, math.sqrt(v / n), n)


def lagpoeng(bud, st):
    if bud >= 2000:
        return MAAL if st == STIKK else -MAAL
    if bud >= 1000:
        return (MAAL // 2 + MAAL // 4) if st == STIKK else -(MAAL // 2 + MAAL // 4)
    return 3 * bud if st >= bud else -3 * bud


def main(m, tittel):
    d = les(m)
    n = len(d)
    print("=" * 70)
    print("%s   n=%d runder (= %d setrunder)" % (tittel, n, 4 * n))
    print("=" * 70)
    print("Alle tall: poeng per runde per SETE, snittet over alle fire setene.")
    print("Dette er ANGER mot en allvitende dobbeltdummy-dommer - en")
    print("overgrense, ikke oppnaaelig gevinst.")
    print("")

    rader = []

    # 1 budgivning: hindsight-optimalt bud gitt DD-par
    xs = []
    for r in d:
        for s in range(4):
            lag = s == r["budgiver"] or s == r["makker"]
            if not lag or r["bud"] >= 1000:
                xs.append(0.0)
                continue
            par = r["ddpar"]
            beste = max([0] + [lagpoeng(k, par) for k in range(5, 13)])
            xs.append((beste - lagpoeng(r["bud"], par)) / 2.0)
    rader.append(("Budgivning (budnivaa mot DD-par)", se(xs)))

    # 2 vrak/trumf/etterlysning
    xs = []
    for r in d:
        ekstra = max(0, r.get("gp_beste", -1) - r.get("gp_aktuell", -1)) if r.get("gp_aktuell", -1) >= 0 else 0
        for s in range(4):
            lag = s == r["budgiver"] or s == r["makker"]
            if not lag or r["bud"] >= 1000:
                xs.append(0.0)
                continue
            xs.append((lagpoeng(r["bud"], min(STIKK, r["ddpar"] + ekstra))
                       - lagpoeng(r["bud"], r["ddpar"])) / 2.0)
    rader.append(("Vrak, trumf og etterlysning", se(xs)))

    # 3 kortspill budgiverlaget
    xs = []
    for r in d:
        lagsete = set([r["budgiver"]])
        if r["makker"] >= 0:
            lagsete.add(r["makker"])
        lt = sum(r["ddtap"][s] for s in lagsete) - sum(r.get("tidlig_delta", []))
        lt = max(0, lt)
        for s in range(4):
            if s not in lagsete or r["bud"] >= 1000:
                xs.append(0.0)
                continue
            xs.append((lagpoeng(r["bud"], min(STIKK, r["lagstikk"] + lt))
                       - lagpoeng(r["bud"], r["lagstikk"])) / 2.0)
    rader.append(("Kortspill - budgiverlaget", se(xs)))

    # 4 kortspill forsvaret
    xs = []
    for r in d:
        lagsete = set([r["budgiver"]])
        if r["makker"] >= 0:
            lagsete.add(r["makker"])
        ft = sum(r["ddtap"][s] for s in range(4) if s not in lagsete)
        for s in range(4):
            if s in lagsete or r["bud"] >= 1000:
                xs.append(0.0)
                continue
            xs.append((lagpoeng(r["bud"], r["lagstikk"])
                       - lagpoeng(r["bud"], max(0, r["lagstikk"] - ft))) / 3.0)
    rader.append(("Kortspill - forsvaret", se(xs)))

    rader.sort(key=lambda x: -x[1][0])
    for navn, t in rader:
        print("  %-36s %6.2f  +/- %.2f" % (navn, t[0], 1.96 * t[1]))
    print("")
    print("  Sum av lekkasjene: %.2f poeng/runde/sete" % sum(t[0] for _, t in rader))
    alle = [r["poeng"][s] for r in d for s in range(4)]
    print("  Faktisk snitt:     %.2f poeng/runde/sete" % (sum(alle) / float(len(alle))))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")
