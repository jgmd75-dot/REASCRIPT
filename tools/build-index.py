#!/usr/bin/env python3
"""Build the GFX ReaPack repository from a GFX-II (Stable) checkout.

    python3 tools/build-index.py PATH/TO/GFX-II [--message "what changed"]

1. Copies the Stable range into this repo: Effects/ (every gfx-*.jsfx and the gfx-*.jsfx-inc system files),
   Scripts/ (the GFX ReaScripts), Data/gfx-drum-patterns/ (Pulse's patterns).
2. Compares each package's files with versions.json: a package whose files changed gets its patch version bumped
   (1.0.0 -> 1.0.1); new packages start at 1.0.0. Nothing changed = nothing to do.
3. Commits the files, then writes index.xml with every source pinned to that commit (so an old version always
   downloads exactly the files it was released with) and commits the index.
Push afterwards: git push origin HEAD:main.

ReaPack installs effects into <REAPER>/Effects/GFX/Stable/ (index name / category), so the plug-ins and the system
files they import share one folder. The system files are their own package ("GFX system files"): ReaPack has no
dependencies, so every user installs that package once (the description says so).
"""
import hashlib, json, os, re, shutil, subprocess, sys, datetime
from xml.sax.saxutils import escape, quoteattr
from urllib.parse import quote

REPO = 'jgmd75-dot/REASCRIPT'
INDEX_NAME = 'GFX'
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEBSITE = 'https://www.gardenfx.uk/'


def git(*a, cwd=HERE):
    return subprocess.run(['git', *a], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def sha(path):
    return hashlib.sha256(open(path, 'rb').read()).hexdigest()


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = os.path.abspath(sys.argv[1])
    msg = sys.argv[sys.argv.index('--message') + 1] if '--message' in sys.argv else 'Update from GFX-II'
    tracked = git('ls-files', cwd=src).split('\n')

    # ---------- 1. the packages, from the Stable checkout ----------
    pk = {}   # name -> dict(type, category, desc, files: [(src, dest, main)], about)
    incs = sorted(f for f in tracked if '/' not in f and f.endswith('.jsfx-inc'))
    for f in sorted(f for f in tracked if '/' not in f and f.endswith('.jsfx')):
        head = open(os.path.join(src, f), encoding='utf-8', errors='replace').read(4000)
        m = re.search(r'^desc:\s*(.+)$', head, re.M)
        desc = m.group(1).strip() if m else f
        m = re.search(r'^//\s*Requires (.+?)\(\.jsfx-inc\)', head, re.M)
        req = m.group(1).strip() if m else ''
        about = f'{desc}. Part of GFX (Garden FX) by JGWizrad: free donationware, gardenfx.uk.'
        if req:
            about += f' Needs the GFX system files package ({req.rstrip()}).'
        pk[f] = dict(type='effect', category='Stable', desc=desc, about=about,
                     files=[(f, f'Effects/{f}', False)])
    pk['GFX system files'] = dict(
        type='effect', category='Stable', desc='GFX system files (install this first: every GFX plug-in needs them)',
        about='The shared engine and panel files (.jsfx-inc) that every GFX plug-in imports. Install once.',
        files=[(f, f'Effects/{f}', False) for f in incs])
    for f in sorted(t for t in tracked if t.endswith('.lua')):
        base = os.path.basename(f)
        head = open(os.path.join(src, f), encoding='utf-8', errors='replace').read(3000)
        m = re.search(r'@description\s+(.+)$', head, re.M)
        desc = m.group(1).strip() if m else base[:-4]
        pk[base] = dict(type='script', category='Scripts', desc=desc,
                        about=f'{desc}. A GFX ReaScript (Actions list).', files=[(f, f'Scripts/{base}', True)])
    pats = sorted(t for t in tracked if t.startswith('Data/gfx-drum-patterns/'))
    if pats:
        pk['GFX Pulse patterns'] = dict(
            type='data', category='Data', desc='GFX Pulse drum patterns',
            about='Pattern files for the Pulse drum machine (installed into REAPER\'s Data/gfx-drum-patterns).',
            files=[(f, f, False) for f in pats])

    # ---------- 2. copy and version ----------
    for d in ('Effects', 'Scripts', 'Data'):
        shutil.rmtree(os.path.join(HERE, d), ignore_errors=True)
    for p in pk.values():
        for s, dst, _ in p['files']:
            os.makedirs(os.path.dirname(os.path.join(HERE, dst)), exist_ok=True)
            shutil.copy2(os.path.join(src, s), os.path.join(HERE, dst))
    vpath = os.path.join(HERE, 'versions.json')
    old = json.load(open(vpath)) if os.path.exists(vpath) else {}
    new, changed = {}, []
    for name, p in pk.items():
        h = hashlib.sha256(''.join(sha(os.path.join(HERE, d)) for _, d, _ in p['files']).encode()).hexdigest()
        o = old.get(name)
        if o and o['hash'] == h:
            new[name] = o
        else:
            if o:
                a, b, c = map(int, o['version'].split('.'))
                ver = f'{a}.{b}.{c + 1}'
            else:
                ver = '1.0.0'
            new[name] = dict(hash=h, version=ver, time=datetime.datetime.now(datetime.timezone.utc)
                             .strftime('%Y-%m-%dT%H:%M:%SZ'), note=msg if o else 'First release on ReaPack.')
            changed.append(f'{name} {ver}')
    gone = sorted(set(old) - set(new))
    if not changed and not gone and os.path.exists(os.path.join(HERE, 'index.xml')):
        print('Nothing changed.')
        return
    json.dump(new, open(vpath, 'w'), indent=1, sort_keys=True)
    git('add', '-A', 'Effects', 'Scripts', 'Data', 'versions.json')
    if git('status', '--porcelain'):
        git('commit', '-q', '-m', f'Files: {msg}')
    commit = git('rev-parse', 'HEAD')

    # ---------- 3. the index, pinned to that commit ----------
    cats = {}
    for name, p in pk.items():
        cats.setdefault(p['category'], []).append(name)
    out = ['<?xml version="1.0" encoding="utf-8"?>',
           f'<index version="1" name={quoteattr(INDEX_NAME)} commit="{commit}">']
    for cat in ('Stable', 'Scripts', 'Data'):
        if cat not in cats:
            continue
        out.append(f'  <category name={quoteattr(cat)}>')
        for name in sorted(cats[cat], key=lambda n: (n != 'GFX system files', n.lower())):
            p, v = pk[name], new[name]
            out.append(f'    <reapack name={quoteattr(name)} type="{p["type"]}" desc={quoteattr(p["desc"])}>')
            out.append(f'      <metadata><description><![CDATA[{p["about"]}]]></description>'
                       f'<link rel="website">{WEBSITE}</link></metadata>')
            out.append(f'      <version name="{v["version"]}" author="JGWizrad" time="{v["time"]}">')
            out.append(f'        <changelog><![CDATA[{v["note"]}]]></changelog>')
            for _, dst, is_main in p['files']:
                url = f'https://github.com/{REPO}/raw/{commit}/' + quote(dst)
                file_attr = dst.split('/', 1)[1]            # path inside the package's install folder
                main = ' main="main"' if is_main else ''
                out.append(f'        <source file={quoteattr(file_attr)}{main}>{escape(url)}</source>')
            out.append('      </version>')
            out.append('    </reapack>')
        out.append('  </category>')
    out.append('  <metadata>')
    out.append('    <description><![CDATA[GFX (Garden FX): free JSFX plug-ins and ReaScripts for REAPER by JGWizrad. '
               'Install "GFX system files" first, then any plug-ins you like. gardenfx.uk]]></description>')
    out.append(f'    <link rel="website">{WEBSITE}</link>')
    out.append('    <link rel="donation">https://ko-fi.com/jgwizrad</link>')
    out.append('  </metadata>')
    out.append('</index>')
    open(os.path.join(HERE, 'index.xml'), 'w').write('\n'.join(out) + '\n')
    git('add', 'index.xml')
    git('commit', '-q', '-m', f'Index: {msg}')
    print(f'{len(changed)} package(s) new or updated' + (f', {len(gone)} removed' if gone else '') + f'; files at {commit[:7]}')
    for c in changed[:20]:
        print('  ', c)


if __name__ == '__main__':
    main()
