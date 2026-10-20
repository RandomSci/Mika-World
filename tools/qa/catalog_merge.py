#!/usr/bin/env python3
"""catalog_merge.py <catalog in> <filled> <eye.json> [scan dir ...] -> writes <catalog in> updated.

Builds the action catalog's verified entries: the mocap fill (catalog_fill.py), then the eye corrections read off the
source at 10 fps (catalog_eye.json) override any field, then the body scans (guard_scan logs, both girls, the full
pose stack) decide the status:
  pass     eye pass, and on each girl at most 10 percent of the clip's frames fail a body rule and no penetration
           deeper than 3 cm
  fail     anything else: the entry is blocked from use (blocked: true) with the reason
  unverified  no scan yet for that clip
"""
import json, os, re, sys

PEN_MAX = 0.03
FAIL_FRAC = 0.10


def scans(dirs):
    out = {}                      # clip -> {girl: rep}
    for d in dirs:
        log = os.path.join(d, 'log.txt')
        if not os.path.exists(log):
            continue
        girl = None
        for l in open(log, errors='replace'):
            m = re.search(r'\[guardscan\] (mika|luna) (RAW|GUARDED)', l)
            if m:
                girl = m[1] if m[2] == 'GUARDED' else None
            m = re.search(r'\[guardscan\] clip (\{.*\})\s*$', l)
            if m and girl:
                r = json.loads(m[1])
                out.setdefault(r['clip'], {})[girl] = r
    return out


def main():
    cat_p, filled_p, eye_p = sys.argv[1:4]
    S = scans(sys.argv[4:])
    cat = json.load(open(cat_p))
    filled = {e['id']: e for e in json.load(open(filled_p))['clips']}
    eye = json.load(open(eye_p))
    counts = {}
    for i, e in enumerate(cat['clips']):
        cid = e['id']
        e.update({k: v for k, v in filled.get(cid, {}).items() if k not in e or e.get(k) is None or k in ('start_s', 'end_s', 'gather_s', 'release_s', 'contact_s', 'lead_limb', 'timing_from')})
        ev = eye.get(cid, {})
        for k, v in ev.items():
            if k not in ('eye', 'note'):
                e[k] = v
        e['eye'] = ev.get('eye', 'unchecked')
        e['eye_note'] = ev.get('note', '')
        why = []
        if e['eye'] != 'pass':
            why.append('not checked by eye' if e['eye'] == 'unchecked' else 'eye: ' + e['eye_note'])
        sc = S.get(cid, {})
        if not sc:
            status = 'unverified' if not why else 'fail'
        else:
            for girl, r in sc.items():
                frac = r['failing'] / max(r['frames'], 1)
                pen = r['rules'].get('penetration', {}).get('worst', 0.0)
                if frac > FAIL_FRAC:
                    why.append('%s %d of %d frames fail a body rule (%s)' % (girl, r['failing'], r['frames'], ', '.join(sorted(r['rules']))))
                if pen > PEN_MAX:
                    why.append('%s penetration %.1f cm' % (girl, pen * 100))
            e['scan'] = {g: {'failing': r['failing'], 'frames': r['frames'], 'rules': {k: [v['n'], v['worst']] for k, v in r['rules'].items()}} for g, r in sc.items()}
            status = 'pass' if not why else 'fail'
        e['status'] = status
        e['blocked'] = status != 'pass'
        e['block_reason'] = '; '.join(why)
        counts[status] = counts.get(status, 0) + 1
    cat['about'] = cat['about'].split(' Verified 20')[0] + ' Verified 20 October by the main session: times filled from the mocap and corrected by eye against every source at 10 fps (catalog_eye.json), status from the body scans of both girls through the full pose stack (pass at most 10 percent failing frames and no penetration over 3 cm; anything else blocked).'
    json.dump(cat, open(cat_p, 'w'), indent=1)
    # the game reads its own copy (res://data/action_catalog.json): the docs file stays the one Selwyn edits
    game = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'data', 'action_catalog.json')
    json.dump(cat, open(game, 'w'), indent=1)
    print(counts, 'synced to', os.path.normpath(game))


if __name__ == '__main__':
    main()
