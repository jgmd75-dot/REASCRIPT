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
- Effects install into `<REAPER>/Effects/GFX/Stable/`, so the plug-ins and the system files share one folder (the
  imports need that). Keep every effect package in the one category.
- Stable only: the Lab is not offered here.
- The repo must stay public (ReaPack downloads without logging in).
