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
5. Press **Apply**. The plug-ins appear in the FX browser by name, ending in "(GFX)" (under Effects/GFX/Stable),
   and under Developer > GardenFX.
6. **Extensions > ReaPack > Manage repositories > Options**: tick **Install new packages when synchronizing**, so
   plug-ins added to GFX later arrive by themselves (otherwise ReaPack only updates the ones you already have).

From then on, **Extensions > ReaPack > Synchronize packages** (or ReaPack's automatic sync) brings in every fix.

## Earlier versions (optional): GFX V2 and GFX V1

The main GFX repository is the current range, **V3**. Earlier versions are separate repositories, so you only get them
if you want them (and a sync never brings back ones you removed). Add either with **Import repositories...**:

- **GFX V2** - the 2.0 units that changed or left the range in V3 (the earlier versions, named "(v2)", and the units
  V3 dropped), so projects made with them still open: `https://github.com/jgmd75-dot/REASCRIPT/raw/main/V2/index.xml`
- **GFX V1** - the legacy units: `https://github.com/jgmd75-dot/REASCRIPT/raw/main/V1/index.xml`

Both need **GFX system files** from the main GFX repository. To switch one off, untick it in
**Extensions > ReaPack > Manage repositories**.

## The Lab (optional)

The experimental GFX Lab plug-ins are a separate repository, so you can leave them out. To add them:
**Extensions > ReaPack > Import repositories...** and paste

`https://github.com/jgmd75-dot/REASCRIPT/raw/main/Lab/index.xml`

then install **GFX Lab system files** first, and any Lab plug-ins you like (they appear as "GFX Lab ...", under
Effects/GFX Lab/Lab). Lab plug-ins change often and may sound different between versions.

## What's here

- `Effects/` - the Stable range (`gfx-*.jsfx`) and the GFX system files (`gfx-*.jsfx-inc`)
- `Scripts/` - GFX ReaScripts (CC-80 chord calculator, MIDI exporters, tidy FX names)
- `Data/gfx-drum-patterns/` - pattern files for Pulse
- `index.xml` - the ReaPack index (generated - don't edit by hand)
- `V2/`, `V1/` - the GFX V2 and GFX V1 repositories (`V2/index.xml`, `V1/index.xml`)
- `Lab/` - the Lab repository: its plug-ins and system files (`Lab/Effects/`) and its own `Lab/index.xml`
- `tools/build-index.py` - rebuilds the Stable from a GFX-II checkout, or the Lab from a LAB checkout (`--lab`)

GFX is free donationware by JGWizrad: [gardenfx.uk](https://www.gardenfx.uk/) · [Ko-fi](https://ko-fi.com/jgwizrad).
© 2026 John Garden.
