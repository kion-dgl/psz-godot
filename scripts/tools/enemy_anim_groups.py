#!/usr/bin/env python3
"""Group enemy models by animation-name sets (exact + prefix-stripped tokens).

Usage:
    python3 scripts/tools/enemy_anim_groups.py

Source for the "Rig groups & behavior archetypes" table in
spec /mechanics/enemy-attacks: models sharing an EXACT clip-name set share
one rig (define behavior once), and prefix-stripped token vocabularies are
the behavior archetypes. Re-run after new rigs land and reconcile the spec.
"""
import json, os, re, struct, sys
from collections import defaultdict

REPO = os.path.join(os.path.dirname(__file__), '..', '..')

def glb_anim_names(path):
    with open(path, 'rb') as f:
        data = f.read()
    if data[:4] != b'glTF':
        return None
    # header: magic, version, length; then chunks: len, type, data
    off = 12
    ln, ty = struct.unpack_from('<I4s', data, off)
    if ty != b'JSON':
        return None
    j = json.loads(data[off+8:off+8+ln])
    return [a.get('name', '') for a in j.get('animations', [])]

# model -> own anims
models = {}
enemies_dir = os.path.join(REPO, 'assets/enemies')
for mid in sorted(os.listdir(enemies_dir)):
    glb = os.path.join(enemies_dir, mid, f'{mid}.glb')
    if not os.path.isfile(glb):
        continue
    try:
        models[mid] = glb_anim_names(glb) or []
    except Exception as e:
        models[mid] = []
        print(f'WARN {mid}: {e}', file=sys.stderr)

# roster: id -> (name, model_id, animation_model_id)
roster = {}
tres_dir = os.path.join(REPO, 'data/enemies')
for fn in sorted(os.listdir(tres_dir)):
    if not fn.endswith('.tres'):
        continue
    text = open(os.path.join(tres_dir, fn)).read()
    def g(k):
        m = re.search(rf'^{k}\s*=\s*"?([^"\n]*)"?$', text, re.M)
        return m.group(1) if m else ''
    roster[g('id')] = (g('name'), g('model_id'), g('animation_model_id'))

# effective clip set per model: own, else animation_model_id (from any roster
# entry using this model), else _rare-strip fallback
anim_source = {}
for _, (nm, mid, amid) in roster.items():
    if mid and amid:
        anim_source[mid] = amid
def effective(mid):
    if models.get(mid):
        return mid
    src = anim_source.get(mid)
    if src and models.get(src):
        return src
    if mid.endswith('_rare'):
        base = mid[:-5]
        if models.get(base):
            return base
    return None

# model -> roster display names
users = defaultdict(list)
for rid, (nm, mid, _) in roster.items():
    users[mid].append(f'{nm or rid}')

PREFIX = re.compile(r'^[a-z]{1,2}_?\d{3}_')
def token(n):
    return PREFIX.sub('', n)

exact = defaultdict(list)   # frozenset(full names) -> models
tokens = defaultdict(list)  # frozenset(tokens) -> models
unresolved = []
for mid in models:
    src = effective(mid)
    if src is None:
        unresolved.append(mid)
        continue
    names = frozenset(models[src])
    exact[names].append(mid)
    tokens[frozenset(token(n) for n in names)].append(mid)

def label(mid):
    u = users.get(mid, [])
    return f"{mid}" + (f" ({', '.join(sorted(set(u)))})" if u else "")

print('════ A. EXACT animation-name sharing (same clip names ⇒ shared rig/anims) ════')
for names, mids in sorted(exact.items(), key=lambda kv: (-len(kv[1]), sorted(kv[1])[0])):
    if len(mids) < 2:
        continue
    print(f"\n▪ {', '.join(sorted(mids))}")
    print(f"  clips: {', '.join(sorted(names))}")

print('\n════ B. TOKEN-vocabulary groups (prefix stripped ⇒ the behavior archetypes) ════')
for toks, mids in sorted(tokens.items(), key=lambda kv: (-len(kv[1]), sorted(kv[1])[0])):
    print(f"\n▪ [{len(mids)} model(s)] {', '.join(sorted(mids))}")
    for m in sorted(mids):
        if users.get(m):
            print(f"    {m} → {', '.join(sorted(set(users[m])))}")
    print(f"  vocab: {', '.join(sorted(toks))}")

if unresolved:
    print(f"\n(unresolved / no animations found: {', '.join(sorted(unresolved))})")
