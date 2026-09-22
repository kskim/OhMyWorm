# OhMyWorm 🐛

[한국어 버전](README.ko.md)

A tiny desktop pet for macOS. A little worm roams around your screen — it
has a thing for edges — and every move it makes comes out of a neural
network. Pick from three brains, from a tiny hand-wired net up to the full
302-neuron engine. Feed it, pet it, give it a new skin. That's the whole
app: no windows, no settings pages, no accounts.

## Where this came from

Inspired by the *C. elegans* connectome (예쁜꼬마선충, "the beautiful
little worm").

The Light brain is a hand-wired 13→6→2 network that senses food, walls,
your cursor, and hunger and decides where to crawl next. The Real brain goes all the
way: the actual 302-neuron connectome, a 95-muscle layer, and weathervane
steering executed through real motor neurons.

## Features

- **Desktop pet** — lives on a transparent overlay that ignores your clicks,
  so everything passes through to your apps except touches on the worm itself
- **Neural locomotion** — a neural network turns sensory input into steering,
  with a bias toward screen edges. It also shies away from your cursor.
  Fully deterministic: same inputs, same path, every time
- **Two brains** — Light (hand-wired mini net) and Real (302 neurons +
  muscles + klinotaxis steering). Switch from the menu
- **Just enough pet** — two stats (satiety, mood) and three things to do:
  - 🍎 **Feed** — a random fruit drops nearby and the worm goes to find it.
    Starve it to zero and one appears on its own
  - ❤️ **Pet** — click the worm, or drag to carry it around
  - 🎨 **Skins** — 3 looks (C. elegans, Dragon, Rattlesnake), each with
    its own body shape, pattern, and face. Your pick sticks around between
    launches
- **System-aware** — speeds up with CPU load, shrinks as the battery drains,
  shorter tail off-charger
- **Lightweight** — about 5–8% CPU and 100 MB RAM on an Apple M4 Pro
  (Release, Real engine; lighter on Light)

## Requirements

- macOS 14 or later (Universal binary: Apple Silicon and Intel)
- Xcode 16+ with command line tools, if you want to build it yourself

## Install

Grab the `.dmg` from the [releases page](https://github.com/kskim/OhMyWorm/releases),
open it, and drag `OhMyWorm` to `Applications`.

The build is unsigned, so the first launch needs a right-click → Open
(or run `xattr -dr com.apple.quarantine /Applications/OhMyWorm.app`).

## Build & Run

```sh
# Build
xcodebuild -project OhMyWorm.xcodeproj -scheme OhMyWorm -configuration Release build

# Run (or just double-click the built app in Finder)
open ~/Library/Developer/Xcode/DerivedData/OhMyWorm-*/Build/Products/Release/OhMyWorm.app

# Tests
xcodebuild -project OhMyWorm.xcodeproj -scheme OhMyWorm -configuration Debug test
```

The app lives in your menu bar. Look for the 🐛. You won't find it in the
dock, and it never opens a window. That's on purpose.

## Usage

| Action | How |
| --- | --- |
| Feed | 🐛 menu → Feed |
| Pet | Left-click the worm, or drag it somewhere |
| Change skin | 🐛 menu → Change Skin |
| Switch engine | 🐛 menu → Change Engine |
| Pause / resume | 🐛 menu → Pause |
| Quit | 🐛 menu → Quit |

The 🐛 menu shows the worm's current stats (satiety, mood) at the top. The
menu follows your system language: Korean on Korean systems, English
everywhere else.

## Project layout

```text
App/
  OhMyWormApp.swift      agent entry point, status item
  Pet/
    PetController.swift  game loop, input, actions
    PetModel.swift         pure game state (no UI, fully tested)
    MiniBrain.swift        Light: hand-wired 13→6→2 network
    Real/                  Real: 302-neuron engine + NMJ muscles + steering
    LocomotionEngine.swift engine protocol + selector
    DesktopPanel.swift   click-through overlay that follows the worm
    WormView.swift       Canvas rendering
    PetMenu.swift        the one and only menu
    L10n.swift           Korean/English strings from system language
  Resources/connectome.json bundled wiring data (see docs)
  Assets.xcassets       app icon set
Tests/OhMyWormTests/    50 unit tests (brains, model, controller, vitals)
Tools/GenerateIcon.swift regenerates the icon set
docs/architecture.md    design notes
```

[docs/architecture.md](docs/architecture.md) has the details if you're curious.

## Notes

- Only the main display is supported for now; the worm moves over cleanly if
  your screen setup changes.
- The menu is bilingual (Korean/English) and follows the system language.

## How it was made

Vibe-coded with the `muse-spark-1.3` AI model. A human directed and reviewed
the whole way.

## License

MIT — see [LICENSE](LICENSE). That covers the code and docs. The bundled
`App/Resources/connectome.json` is third-party scientific data, not MIT
code: see [docs/data-notice.md](docs/data-notice.md) for its provenance,
citation, and terms.
