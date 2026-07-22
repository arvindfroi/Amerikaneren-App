# -*- coding: utf-8 -*-
"""Hvor i runden taper budgiverlaget / forsvaret dobbeltdummy-stikk?"""
import glob, json, math, os, sys
from collections import Counter


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


def main(monster, tittel):
    d = [r for r in les(monster) if "lagtap_stikk" in r]
    if not d:
        print("ingen runder med per-stikk-data i " + monster)
        return
    print("=" * 74)
    print("%s   runder med per-stikk-data: %d" % (tittel, len(d)))
    print("=" * 74)
    print("")
    print("DD-tap per stikknummer (stikk 1-2 maales bare samlet, se under).")
    print("  stikk |  budgiverlaget  |    forsvaret    | fase")
    for k in range(12):
        lag = snitt_se([r["lagtap_stikk"][k] for r in d])
        fors = snitt_se([r["forsvartap_stikk"][k] for r in d])
        igjen = 12 - k
        fase = "eksakt sluttspill" if igjen <= 6 else "graadig utrulling"
        if k < 2:
            fase = "(ikke attribuert)"
        print("   %2d   | %6.3f +/-%.3f | %6.3f +/-%.3f | %d stikk igjen, %s"
              % (k + 1, lag[0], 1.96 * lag[1], fors[0], 1.96 * fors[1], igjen, fase))
    sumlag = snitt_se([sum(r["lagtap_stikk"]) for r in d])
    sumfor = snitt_se([sum(r["forsvartap_stikk"]) for r in d])
    print("  sum    | %6.3f +/-%.3f | %6.3f +/-%.3f" % (sumlag[0], 1.96 * sumlag[1],
                                                        sumfor[0], 1.96 * sumfor[1]))
    grad_lag = snitt_se([sum(r["lagtap_stikk"][2:6]) for r in d])
    eks_lag = snitt_se([sum(r["lagtap_stikk"][6:]) for r in d])
    grad_for = snitt_se([sum(r["forsvartap_stikk"][2:6]) for r in d])
    eks_for = snitt_se([sum(r["forsvartap_stikk"][6:]) for r in d])
    print("")
    print("  stikk 3-6  (graadig utrulling foer eksaktgrensen):")
    print("    budgiverlaget %6.3f +/-%.3f | forsvaret %6.3f +/-%.3f"
          % (grad_lag[0], 1.96 * grad_lag[1], grad_for[0], 1.96 * grad_for[1]))
    print("  stikk 7-12 (hele resten loeses eksakt per verden):")
    print("    budgiverlaget %6.3f +/-%.3f | forsvaret %6.3f +/-%.3f"
          % (eks_lag[0], 1.96 * eks_lag[1], eks_for[0], 1.96 * eks_for[1]))
    t12 = snitt_se([sum(r.get("tidlig_delta", [])) for r in d])
    print("  stikk 1-2  (samlet W-endring, negativ = laget mistet stikk): %6.3f +/-%.3f"
          % (t12[0], 1.96 * t12[1]))

    print("")
    print("-- AUKSJONEN --")
    tall = [r for r in d if r["bud"] < 1000]
    over = []
    antall_hev = []
    for r in tall:
        andres = [b[1] for b in r["budhist"] if b[0] != r["budgiver"] and 0 < b[1] < 1000]
        nod = max([5] + [max(andres) + 1] if andres else [5])
        over.append(r["bud"] - nod)
        antall_hev.append(sum(1 for b in r["budhist"] if b[0] == r["budgiver"] and b[1] > 0))
    c = Counter(over)
    print("  bud minus laveste vinnende bud: " + "  ".join("%+d:%d" % (k, c[k]) for k in sorted(c)))
    print("  antall egne hevinger fra budvinneren: " +
          "  ".join("%d:%d" % (k, Counter(antall_hev)[k]) for k in sorted(set(antall_hev))))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
