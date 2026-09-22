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

The Light brain is a hand-wired 11→6→2 network that senses food, walls,
and hunger and decides where to crawl next. The Real brain goes all the
way: the actual 302-neuron connectome, a 95-muscle layer, and weathervane
steering executed through real motor neurons.

## Features

- **Desktop pet** — lives on a transparent overlay that ignores your clicks,
  so everything passes through to your apps except touches on the worm itself
- **Neural locomotion** — a neural network turns sensory input into steering,
  with a bias toward screen edges. Fully deterministic: same inputs, same
  path, every time
- **Three brains** — Light (hand-wired mini net), Medium (connectome-scaled
  weights), Real (302 neurons + muscles + klinotaxis steering). Switch from the menu
- **Just enough pet** — two stats (satiety, mood) and three things to do:
  - 🍎 **Feed** — food drops nearby and the worm goes to find it
  - ❤️ **Pet** — click the worm, or drag to carry it around
  - 🎨 **Skins** — 4 looks (Classic, Berry, Honey, Ghost) that stick around
    between launches
- **System-aware** — speeds up with CPU load, shrinks as the battery drains,
  lazier off-charger
- **Lightweight** — about 3–5% CPU and 100 MB RAM on an Apple M4 Pro
  (Release, Real engine; lighter on Light/Medium)

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
| Feed | 🐛 menu → 밥주기, or right-click the worm → 밥주기 |
| Pet | Left-click the worm, or drag it somewhere |
| Change skin | 🐛 menu → 스킨 변경 |
| Switch engine | 🐛 menu → 엔진 변경 |
| Pause / resume | 🐛 menu → 일시정지 |
| Quit | 🐛 menu → 종료 |

Right-clicking the worm opens the same menu as the status item, with its
current stats (포만감 = satiety, 기분 = mood) at the top.

## Project layout

```text
App/
  OhMyWormApp.swift      agent entry point, status item
  Pet/
    PetController.swift  game loop, input, actions
    PetModel.swift         pure game state (no UI, fully tested)
    MiniBrain.swift        Light: hand-wired 11→6→2 network
    MediumBrain.swift      Medium: connectome-scaled weights
    Real/                  Real: 302-neuron engine + NMJ muscles + steering
    LocomotionEngine.swift engine protocol + selector
    DesktopPanel.swift   click-through overlay that follows the worm
    WormView.swift       Canvas rendering
    PetMenu.swift        the one and only menu
  Resources/connectome.json bundled wiring data (see docs)
  Assets.xcassets       app icon set
Tests/OhMyWormTests/    41 unit tests (brains, model, controller, vitals)
Tools/GenerateIcon.swift regenerates the icon set
docs/architecture.md    design notes
```

[docs/architecture.md](docs/architecture.md) has the details if you're curious.

## Notes

- Only the main display is supported for now; the worm moves over cleanly if
  your screen setup changes.
- The UI speaks Korean at the moment. Localization help welcome.

## How it was made

Vibe-coded with the `muse-spark-1.3` AI model. A human directed and reviewed
the whole way.

## License

No LICENSE file yet (planned: MIT). The code is public but not under an
open license until one lands. The bundled connectome data follows its
upstream terms — see docs/architecture.md.
