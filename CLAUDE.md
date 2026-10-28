# CLAUDE.md - REASCRIPT (GFX on ReaPack)

This repo is the public ReaPack repository for the GFX Stable range. John adds
`https://github.com/jgmd75-dot/REASCRIPT/raw/main/index.xml` in REAPER (Extensions > ReaPack > Import repositories).

- **Never edit the files here by hand.** Everything is generated from GFX-II (the Stable) by
  `python3 tools/build-index.py PATH/TO/GFX-II --message "what changed"`, then `git push origin HEAD:main`.
  Run it after every Stable push (bug fixes), so ReaPack users get them.
- The script copies the range, bumps the patch version (1.0.0 -> 1.0.1) of every package whose files changed
  (`versions.json` keeps the hashes), commits the files, then writes `index.xml` with every download pinned to that
  commit, and commits the index.
- Packages: one per plug-in (type effect, category "Stable"), one "GFX system files" package with all the
  `.jsfx-inc` files (ReaPack has no dependencies: users install it once), one per ReaScript (category "Scripts",
  registered as actions), and "GFX Pulse patterns" (type data, into REAPER's Data/gfx-drum-patterns).
- Effects install into `<REAPER>/Effects/GFX/Stable/`, sorted into the website's category folders (`Amps and drive/`,
  `Dynamics/` ...; units off the site in `Legacy/`) with the system files in `System files - do not delete/` - the
  same layout as the download ZIPs (JG, 28 Oct 2026, for screen-reader users). REAPER finds imports in any folder
  under Effects, and an old project finds a plug-in that moved (JG tested both). The folders come from the website
  checkout: pass `--site PATH/TO/WEBSITE` (default `../website`). Keep every effect package in the one ReaPack
  category: the folder is in each file's path, so a move is an ordinary update (ReaPack removes the old file).
- **The Lab** is a second, separate ReaPack repository in the same git repo: `Lab/index.xml` (index "GFX Lab",
  category "Lab"), files under `Lab/Effects/`, versions in `Lab/versions.json`. Rebuild it with
  `python3 tools/build-index.py PATH/TO/LAB --lab --message "what changed"` after a Lab plug-in arrives, changes or
  leaves. Its plug-ins and the "GFX Lab system files" package install into `<REAPER>/Effects/GFX Lab/Lab/`, apart
  from the Stable, in the Lab page's group folders. John adds it with `https://github.com/jgmd75-dot/REASCRIPT/raw/main/Lab/index.xml`.
- The repo must stay public (ReaPack downloads without logging in).
