# GFX for ReaPack

The GFX (Garden FX) range of free JSFX plug-ins and ReaScripts for REAPER, as a ReaPack repository: add it once and
REAPER keeps the range up to date.

## Add GFX to REAPER

1. Install [ReaPack](https://reapack.com) if you haven't already (it's free).
2. In REAPER: **Extensions > ReaPack > Import repositories...**
3. Paste this address and press OK:

   `https://github.com/jgmd75-dot/REASCRIPT/raw/main/index.xml`

4. **Extensions > ReaPack > Browse packages**, search for **GFX**:
   - install **GFX system files** first - every GFX plug-in needs them;
   - then install the plug-ins you want (or right-click > Install all), plus any of the scripts.
5. Press **Apply**. The plug-ins appear in the FX browser as "GFX ..." (under Effects/GFX/Stable).

From then on, **Extensions > ReaPack > Synchronize packages** (or ReaPack's automatic sync) brings in every fix.

## What's here

- `Effects/` - the Stable range (`gfx-*.jsfx`) and the GFX system files (`gfx-*.jsfx-inc`)
- `Scripts/` - GFX ReaScripts (CC-80 chord calculator, MIDI exporters, tidy FX names)
- `Data/gfx-drum-patterns/` - pattern files for Pulse
- `index.xml` - the ReaPack index (generated - don't edit by hand)
- `tools/build-index.py` - rebuilds everything from a GFX-II checkout

GFX is free donationware by JGWizrad: [gardenfx.uk](https://www.gardenfx.uk/) · [Ko-fi](https://ko-fi.com/jgwizrad).
© 2026 John Garden.
