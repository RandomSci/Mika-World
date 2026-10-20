#!/usr/bin/env python3
"""jitter_layers.py <log.txt>: the tremble after each modifier of her stack (melee_exchange --jitter-layers): the
layer where the reversal share and the second difference jump is the one that adds it."""
import re, sys
from collections import OrderedDict
import numpy as np
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from jitter_report import qmul, rotvec

B = ["Head", "RightHand", "RightUpperLeg", "UpperChest"]
L = OrderedDict()
for l in open(sys.argv[1], errors='replace'):
    m = re.match(r'\[ljit\] (\S+) (\d+) ([-\d. ]+)$', l.strip())
    if m:
        L.setdefault(m[1], {})[int(m[2])] = list(map(float, m[3].split()))
print('%-22s' % 'after layer' + ''.join('%22s' % b for b in B))
for layer, fr in L.items():
    ks = sorted(fr)
    A = np.array([fr[k] for k in ks])
    cells = []
    for i in range(len(B)):
        q = A[:, 4 * i:4 * i + 4]
        q = q / np.linalg.norm(q, axis=1)[:, None]
        for k in range(1, len(q)):
            if np.dot(q[k], q[k - 1]) < 0:
                q[k] = -q[k]
        w = rotvec(qmul(q[1:], q[:-1] * np.array([-1, -1, -1, 1])))
        ang = np.degrees(np.linalg.norm(w, axis=1))
        d2 = np.degrees(np.linalg.norm(w[1:] - w[:-1], axis=1))
        rev = ((ang[1:] > 0.5) & ((w[1:] * w[:-1]).sum(1) < 0)).mean() * 100
        cells.append('rev %5.1f jit %6.2f' % (rev, d2.mean()))
    print('%-22s' % layer[:22] + ''.join('%22s' % c for c in cells))
