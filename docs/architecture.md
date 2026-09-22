# Architecture

OhMyWorm is a desktop pet for macOS: a small worm crawls freely over the
desktop, driven by a miniature recurrent neural network. No dock icon, no main
window — just the worm, a `🐛` status item, and a right-click menu.

## Runtime structure

```text
Timer (20 Hz) -> PetController -> PetModel.update -> MiniBrain.step
                                              |-> trail / stats / particles
PetController -> DesktopPanel (small tracking overlay) -> WormView (Canvas)
Global mouse monitor -> pet / carry / right-click menu
Status item menu -> feed / skin / pause / quit
```

## Modules

| File | Role |
| --- | --- |
| `App/OhMyWormApp.swift` | Agent app entry (`LSUIElement`), status item, screen-change handling |
| `App/Pet/PetController.swift` | Game loop, screen bounds, food/pet/skin/pause actions, global mouse monitor |
| `App/Pet/PetModel.swift` | Pure game state: movement, trail, satiety/mood, food, particles |
| `App/Pet/MiniBrain.swift` | Hand-wired recurrent network (11 inputs, 6 hidden, 2 outputs) |
| `App/Pet/DesktopPanel.swift` | Click-through transparent `NSPanel` that follows the worm |
| `App/Pet/SystemVitals.swift` | CPU/battery sampling via Mach/IOKit, no permissions needed |
| `App/Pet/WormView.swift` | SwiftUI Canvas rendering: worm, food, hearts, hunger hint |
| `App/Pet/PetMenu.swift` | Single menu shared by the status item and right-click |

## The miniature network

`MiniBrain` is a game model, not biological data. Sensory inputs (food
direction/proximity, outward direction, wall direction/proximity, hunger, two
exploratory oscillators) feed six recurrent tanh units — food steering, edge
steering, wall avoidance, approach drive, and an oscillator pair — producing a
turn rate and a speed. Every locomotion decision flows through the network;
only game states (eating, being carried) and the hard wall constraint bypass
it. The model is fully deterministic: same inputs, same path.

## Pet system (minimal)

Two stats, `satiety` and `mood` (0–100), decay over ~10 and ~8 minutes.
Feeding restores satiety, petting restores mood. Low satiety slows the worm;
low mood dulls it slightly. Three interactions only: feed, pet, change skin
(4 presets, persisted in `UserDefaults`). No sleep, growth, or evolution.

System vitals (RunCat-style) modulate the network's output: CPU load scales
speed (0.6x–2.0x), running on battery multiplies 0.75x, and battery level
scales body size (0.7x–1.0x). Desktops without a battery read as full/AC.
Vitals resample every 2 seconds.

## Performance

The overlay is a fixed 760 pt panel that follows the worm instead of covering
the screen, and the loop runs at 20 Hz. Measured on an Apple M4 Pro:
~5% CPU, ~30 MB RAM in Release. The model itself is negligible; the cost is
SwiftUI/Canvas render and commit overhead per frame.

## History

This project previously contained a C. elegans connectome inspector and data
pipeline. That code was removed during the pivot to a desktop pet; it remains
available at the `backup/pre-pet-pivot` tag.
