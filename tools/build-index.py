#!/usr/bin/env python3
"""Build the GFX ReaPack repositories: the Stable (from a GFX-II checkout) or the Lab (from a LAB checkout).

    python3 tools/build-index.py PATH/TO/GFX-II [--message "what changed"]          -> index.xml
    python3 tools/build-index.py PATH/TO/LAB --lab [--message "what changed"]       -> Lab/index.xml

The Lab is a separate ReaPack repository (index "GFX Lab", category "Lab"): its plug-ins and the Lab system files
install into <REAPER>/Effects/GFX Lab/Lab/, apart from the Stable. Lab files live under Lab/ here, with their own
versions (Lab/versions.json).

1. Copies the Stable range into this repo: Effects/ (every gfx-*.jsfx and the gfx-*.jsfx-inc system files),
   Scripts/ (the GFX ReaScripts), Data/gfx-drum-patterns/ (Pulse's patterns).
2. Compares each package's files with versions.json: a package whose files changed gets its patch version bumped
   (1.0.0 -> 1.0.1); new packages start at 1.0.0. Nothing changed = nothing to do.
3. Commits the files, then writes index.xml with every source pinned to that commit (so an old version always
   downloads exactly the files it was released with) and commits the index.
Push afterwards: git push origin HEAD:main.

ReaPack installs effects into <REAPER>/Effects/GFX/Stable/ (index name / category), each plug-in in its website
category's folder and the system files in "System files - do not delete" (REAPER finds imports in any folder under
Effects; JG tested that an old project still finds a plug-in moved into a subfolder, 28 Oct 2026). The folders come
from the website checkout (--site PATH, default ../website). The system files are their own package ("GFX system
files"): ReaPack has no dependencies, so every user installs that package once (the description says so).
"""
import hashlib, json, os, re, shutil, subprocess, sys, datetime
from xml.sax.saxutils import escape, quoteattr
from urllib.parse import quote

REPO = 'jgmd75-dot/REASCRIPT'
TOP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAB = '--lab' in sys.argv
WEBSITE = 'https://www.gardenfx.uk/'


def git(*a, cwd=TOP):
    return subprocess.run(['git', *a], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def sha(path):
    return hashlib.sha256(open(path, 'rb').read()).hexdigest()


def load_site(n):
    """A module from the website checkout's tools/ (--site PATH, default ../website next to this repo)."""
    import importlib.util
    site = SITE
    spec = importlib.util.spec_from_file_location(n.replace('-', '_'), os.path.join(site, 'tools', n + '.py'))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod


SITE = sys.argv[sys.argv.index('--site') + 1] if '--site' in sys.argv else os.path.join(os.path.dirname(TOP), 'website')


def head_of(path):
    return open(path, encoding='utf-8', errors='replace').read(4000)


def effect_pkg(path, f, dest, cat, sysname, lab=False):
    """One plug-in's package: its desc and about text from the file's header."""
    head = head_of(path)
    m = re.search(r'^desc:\s*(.+)$', head, re.M)
    desc = m.group(1).strip() if m else f
    m = re.search(r'^//\s*Requires (.+?)\(\.jsfx-inc\)', head, re.M)
    req = m.group(1).strip() if m else ''
    about = f'{desc}. Part of GFX (Garden FX) by JGWizrad: free donationware, gardenfx.uk.'
    if lab:
        about += ' A Lab plug-in: experimental, may change between versions.'
    if req:
        about += f' Needs the {sysname} package ({req.rstrip()}).'
    return dict(type='effect', category=cat, desc=desc, about=about, files=[(path, dest, False)])


def parts(src, tracked):
    """The ReaPack repositories to build: [(sub, index name, category, packages, sysname, description)].
    Stable (JG, 30 Oct 2026: "Split: GFX V3 / V2 extras / V1"): three repositories, ticked on or off in Manage
    repositories, so a sync never brings back a version you removed:
      GFX     (index.xml)    - the V3 range (stable.js), the system files, the scripts and Pulse's patterns
      GFX V2  (V2/index.xml) - the V2 units that aren't in V3 as they are: the earlier versions kept as -v2 files
                               and the units that left the range (stable-v2.js); the rest of V2 is the same file in V3
      GFX V1  (V1/index.xml) - the legacy units (the site's legacy/files)
    V2 and V1 plug-ins import the GFX system files (install them from the GFX repository)."""
    if not os.path.isdir(os.path.join(SITE, 'tools')):
        sys.exit(f'No website checkout at {SITE} (pass --site PATH): the install folders come from it.')
    incs = sorted(f for f in tracked if '/' not in f and f.endswith('.jsfx-inc'))
    units = sorted(f for f in tracked if '/' not in f and f.endswith('.jsfx'))
    if LAB:
        m = load_site('build-lab-zip')
        fold = {f: g for g, items in m.groups() for _, _, f in items}
        sysname = 'GFX Lab system files'
        pk = {f: effect_pkg(os.path.join(src, f), f, f'Effects/{fold.get(f, "Other")}/{f}', 'Lab', sysname, True)
              for f in units}
        pk[sysname] = dict(
            type='effect', category='Lab', desc=f'{sysname} (install this first: every GFX Lab plug-in needs them)',
            about='The shared engine and panel files (.jsfx-inc) that every GFX Lab plug-in imports. Install once.',
            files=[(os.path.join(src, f), f'Effects/{m.SYS_DIR}/{f}', False) for f in incs])
        add_scripts(pk, src, tracked)
        return [('Lab/', 'GFX Lab', 'Lab', pk, sysname,
                 'GFX Lab: the experimental GFX plug-ins for REAPER by JGWizrad - new ideas built in the open; they '
                 'change often. Install "GFX Lab system files" first, then any Lab plug-ins you like. gardenfx.uk/lab')]

    m = load_site('sync-plugins')
    cats, plugs = m.site_data()
    cats2, plugs2 = m.site_data(v2=True)
    sysname = 'GFX system files'
    v3, v2, v1 = {}, {}, {}
    for f in units:
        n = f[:-5]
        if n in plugs:
            v3[f] = effect_pkg(os.path.join(src, f), f, f'Effects/{cats[plugs[n][1]]}/{f}', 'Stable', sysname)
        elif n.endswith('-v2') and n[:-3] in plugs2:
            v2[f] = effect_pkg(os.path.join(src, f), f, f'Effects/{cats2[plugs2[n[:-3]][1]]}/{f}', 'V2', sysname)
        elif n in plugs2:
            v2[f] = effect_pkg(os.path.join(src, f), f, f'Effects/{cats2[plugs2[n][1]]}/{f}', 'V2', sysname)
        else:
            v1[f] = None                       # a legacy unit kept in the Stable (Optimiser): from legacy/files below
    leg = os.path.join(SITE, 'legacy', 'files')
    for f in sorted(os.listdir(leg)):
        if f.endswith('.jsfx'):
            v1[f] = effect_pkg(os.path.join(leg, f), f, f'Effects/{f}', 'V1', sysname)
    missing = [f for f, p in v1.items() if p is None]
    if missing:
        sys.exit(f'Not in the V3 or V2 range and not in the site\'s legacy/files: {", ".join(missing)}')
    v3[sysname] = dict(
        type='effect', category='Stable', desc=f'{sysname} (install this first: every GFX plug-in needs them)',
        about='The shared engine and panel files (.jsfx-inc) that every GFX plug-in imports - the V2 and V1 '
              'repositories\' plug-ins too. Install once.',
        files=[(os.path.join(src, f), f'Effects/{m.SYS_DIR}/{f}', False) for f in incs])
    add_scripts(v3, src, tracked)
    pats = sorted(t for t in tracked if t.startswith('Data/gfx-drum-patterns/'))
    if pats:
        v3['GFX Pulse patterns'] = dict(
            type='data', category='Data', desc='GFX Pulse drum patterns',
            about='Pattern files for the Pulse drum machine (installed into REAPER\'s Data/gfx-drum-patterns).',
            files=[(os.path.join(src, f), f, False) for f in pats])
    need = ' They need the "GFX system files" package from the GFX repository (index.xml): add that repository too.'
    return [('', 'GFX', 'Stable', v3, sysname,
             'GFX (Garden FX) V3: free JSFX plug-ins and ReaScripts for REAPER by JGWizrad - the current range. '
             'Install "GFX system files" first, then any plug-ins you like. Earlier versions are in the separate '
             'GFX V2 and GFX V1 repositories. gardenfx.uk'),
            ('V2/', 'GFX V2', 'V2', v2, sysname,
             'GFX V2: the GFX 2.0 units that changed or left the range in V3 - the earlier versions (-v2 files) and '
             'the units V3 dropped - so projects made with them still open. Everything else in V2 is the same file '
             'as in V3.' + need + ' gardenfx.uk'),
            ('V1/', 'GFX V1', 'V1', v1, sysname,
             'GFX V1: the legacy GFX units (the site\'s V1 page), so projects made with them still open.' + need +
             ' gardenfx.uk')]


def add_scripts(pk, src, tracked):
    for f in sorted(t for t in tracked if t.endswith('.lua') and not t.startswith('dev/')):
        base = os.path.basename(f)
        head = open(os.path.join(src, f), encoding='utf-8', errors='replace').read(3000)
        m = re.search(r'@description\s+(.+)$', head, re.M)
        desc = m.group(1).strip() if m else base[:-4]
        pk[base] = dict(type='script', category='Scripts', desc=desc,
                        about=f'{desc}. A GFX ReaScript (Actions list).', files=[(os.path.join(src, f), f'Scripts/{base}', True)])


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = os.path.abspath(sys.argv[1])
    msg = sys.argv[sys.argv.index('--message') + 1] if '--message' in sys.argv else 'Update from GFX-II'
    tracked = git('ls-files', cwd=src).split('\n')
    plan = parts(src, tracked)

    # ---------- copy and version, each repository in its own folder ----------
    news, report = [], []
    for sub, iname, cat, pk, sysname, about in plan:
        here = os.path.join(TOP, sub)
        for d in ('Effects', 'Scripts', 'Data'):
            shutil.rmtree(os.path.join(here, d), ignore_errors=True)
        for p in pk.values():
            for s, dst, _ in p['files']:
                os.makedirs(os.path.dirname(os.path.join(here, dst)), exist_ok=True)
                shutil.copy2(s, os.path.join(here, dst))
        vpath = os.path.join(here, 'versions.json')
        old = json.load(open(vpath)) if os.path.exists(vpath) else {}
        new, changed = {}, []
        for name, p in pk.items():
            # an effect's install path counts too: a plug-in moved to another folder is a new version (ReaPack moves it)
            h = hashlib.sha256(''.join((d if p['type'] == 'effect' else '') + sha(os.path.join(here, d))
                                       for _, d, _ in p['files']).encode()).hexdigest()
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
        fresh = changed or gone or not os.path.exists(os.path.join(here, 'index.xml'))
        news.append((new, fresh))
        if fresh:
            json.dump(new, open(vpath, 'w'), indent=1, sort_keys=True)
        report.append(f'{iname}: {len(changed)} package(s) new or updated' + (f', {len(gone)} removed' if gone else ''))
        report += ['   ' + c for c in changed[:20]]
        git('add', '-A', *(sub + d for d in ('Effects', 'Scripts', 'Data', 'versions.json') if os.path.exists(os.path.join(here, d))))
    if not any(f for _, f in news):
        print('Nothing changed.')
        return
    if git('status', '--porcelain'):
        git('commit', '-q', '-m', f'Files: {msg}')
    commit = git('rev-parse', 'HEAD')

    # ---------- the indexes, pinned to that commit ----------
    for (sub, iname, cat0, pk, sysname, about), (new, fresh) in zip(plan, news):
        if not fresh:
            continue
        cats = {}
        for name, p in pk.items():
            cats.setdefault(p['category'], []).append(name)
        out = ['<?xml version="1.0" encoding="utf-8"?>',
               f'<index version="1" name={quoteattr(iname)} commit="{commit}">']
        for cat in (cat0, 'Scripts', 'Data'):
            if cat not in cats:
                continue
            out.append(f'  <category name={quoteattr(cat)}>')
            for name in sorted(cats[cat], key=lambda n: (n != sysname, n.lower())):
                p, v = pk[name], new[name]
                out.append(f'    <reapack name={quoteattr(name)} type="{p["type"]}" desc={quoteattr(p["desc"])}>')
                out.append(f'      <metadata><description><![CDATA[{p["about"]}]]></description>'
                           f'<link rel="website">{WEBSITE}</link></metadata>')
                out.append(f'      <version name="{v["version"]}" author="GardenFX" time="{v["time"]}">')
                out.append(f'        <changelog><![CDATA[{v["note"]}]]></changelog>')
                for _, dst, is_main in p['files']:
                    url = f'https://github.com/{REPO}/raw/{commit}/' + quote(sub + dst)
                    file_attr = dst.split('/', 1)[1]            # path inside the package's install folder
                    main = ' main="main"' if is_main else ''
                    out.append(f'        <source file={quoteattr(file_attr)}{main}>{escape(url)}</source>')
                out.append('      </version>')
                out.append('    </reapack>')
            out.append('  </category>')
        out.append('  <metadata>')
        out.append(f'    <description><![CDATA[{about}]]></description>')
        out.append(f'    <link rel="website">{WEBSITE}</link>')
        out.append('    <link rel="donation">https://ko-fi.com/jgwizrad</link>')
        out.append('  </metadata>')
        out.append('</index>')
        open(os.path.join(TOP, sub, 'index.xml'), 'w').write('\n'.join(out) + '\n')
        git('add', sub + 'index.xml')
    git('commit', '-q', '-m', f'Index: {msg}')
    print(f'Files at {commit[:7]}')
    print('\n'.join(report))


if __name__ == '__main__':
    main()
