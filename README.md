# OhMyWorm 🐛

A tiny desktop pet for macOS. A worm crawls freely over your desktop —
preferring the edges — driven by a miniature recurrent neural network. Feed
it, pet it, change its skin. No windows, no settings screens, no accounts.

## Features

- **Desktop pet** — lives on a transparent click-through overlay; your clicks
  pass through everywhere except the worm itself
- **Neural locomotion** — a hand-wired 11→6→2 recurrent network decides every
  turn and speed from sensory input (food, edges, walls, hunger). Deterministic:
  same inputs, same path
- **Edge lover** — steering gains bias it toward screen edges instead of the
  center
- **Mini pet system** — two stats (satiety, mood) and three interactions:
  - 🍎 **Feed** — drops food nearby; the worm seeks it out and munches it
  - ❤️ **Pet** — click or drag across the worm for hearts and a happy wiggle
  - 🎨 **Skins** — 4 presets (Classic, Berry, Honey, Ghost), remembered
    between launches
- **Lightweight** — ~5% CPU / ~30 MB RAM on an Apple M4 Pro (Release)

## Requirements

- macOS 14 or later (Apple Silicon recommended)
- Xcode 16+ with command line tools (to build)

## Build & Run

```sh
# Build
xcodebuild -project OhMyWorm.xcodeproj -scheme OhMyWorm -configuration Release build

# Run (or open the built app from Finder)
open ~/Library/Developer/Xcode/DerivedData/OhMyWorm-*/Build/Products/Release/OhMyWorm.app

# Tests
xcodebuild -project OhMyWorm.xcodeproj -scheme OhMyWorm -configuration Debug test
```

The app runs as a menu-bar agent: look for the 🐛 icon. There is no dock
icon and no main window by design.

## Usage

| Action | How |
| --- | --- |
| Feed | 🐛 menu → 밥주기, or right-click the worm → 밥주기 |
| Pet | Left-click the worm, or drag to carry it around |
| Change skin | 🐛 menu → 스킨 변경 |
| Pause / resume | 🐛 menu → 일시정지 |
| Quit | 🐛 menu → 종료 |

Right-clicking the worm opens the same menu as the status item. Stats are
shown at the top of the menu (`포만감` = satiety, `기분` = mood).

## Project layout

```text
App/
  OhMyWormApp.swift      agent entry point, status item
  Pet/
    PetController.swift  game loop, input, actions
    PetModel.swift       pure game state (UI-free, tested)
    MiniBrain.swift      miniature recurrent network
    DesktopPanel.swift   click-through tracking overlay
    WormView.swift       Canvas rendering
    PetMenu.swift        the one and only menu
Tests/OhMyWormTests/    16 unit tests (brain, model, controller)
docs/architecture.md    design notes
```

See [docs/architecture.md](docs/architecture.md) for details.

## Notes

- Single display (main screen) is supported; the worm refits if the screen
  geometry changes.
- UI strings are currently Korean; contributions for localization are welcome.
- This project previously hosted a C. elegans connectome inspector. That code
  was retired during the pivot to a desktop pet and is preserved at the
  `backup/pre-pet-pivot` tag — it is not part of this app.

## License

TBD — a license (MIT recommended) will be added before the first public
release.
