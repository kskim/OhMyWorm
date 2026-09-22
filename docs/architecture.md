# Architecture

OhMyWorm is a desktop pet for macOS: a small worm crawls freely over the
desktop, driven by a miniature recurrent neural network. No dock icon, no main
window — just the worm, a `🐛` status item, and a right-click menu.

## Runtime structure

```text
Timer (20 Hz) -> PetController -> PetModel.update -> Brain.step (light/medium/real)
                                              |-> trail / stats / particles
PetController -> DesktopPanel (small tracking overlay) -> WormView (Canvas)
Global mouse monitor -> pet / carry / right-click menu
Status item menu -> feed / skin / engine / pause / quit
```

## Modules

| File | Role |
| --- | --- |
| `App/OhMyWormApp.swift` | Agent app entry (`LSUIElement`), status item, screen-change handling |
| `App/Pet/PetController.swift` | Game loop, screen bounds, food/pet/skin/pause actions, global mouse monitor |
| `App/Pet/PetModel.swift` | Pure game state: movement, trail, satiety/mood, food, particles |
| `App/Pet/MiniBrain.swift` | Light: hand-wired recurrent network (11 inputs, 6 hidden, 2 outputs) |
| `App/Pet/MediumBrain.swift` | Medium: same structure, connectome-scaled weights (baked constants) |
| `App/Pet/Real/` | Real: real 302-neuron engine + NMJ muscles + steering controller + bundled data |
| `App/Pet/LocomotionEngine.swift` | Engine protocol, `Brain` selector, `EngineID` |
| `App/Pet/DesktopPanel.swift` | Click-through transparent `NSPanel` that follows the worm |
| `App/Pet/SystemVitals.swift` | CPU/battery sampling via Mach/IOKit, no permissions needed |
| `App/Pet/WormView.swift` | SwiftUI Canvas rendering: worm, food, hearts |
| `App/Pet/PetMenu.swift` | Single menu shared by the status item and right-click |

## The three engines

Every locomotion decision flows through the selected engine; only game
states (eating, being carried) and the hard wall constraint bypass it.
All engines are fully deterministic: same inputs, same path. Switching
engines resets neural state; position and stats are kept. Selection is
persisted in `UserDefaults`.

- **Light** (`MiniBrain`) is a game model, not biological data. Sensory
  inputs (food direction/proximity, outward direction, wall
  direction/proximity, hunger, two exploratory oscillators) feed six
  recurrent tanh units — food steering, edge steering, wall avoidance,
  approach drive, and an oscillator pair — producing a turn rate and speed.
- **Medium** (`MediumBrain`) reuses that structure with weights scaled by
  aggregate statistics of the real connectome (sensory divergence 1.148,
  motor convergence 0.846, gap fraction 0.216), baked in as constants.
  It does not simulate the real network.
- **Real** (`RealBrain`) runs the real 302-neuron recurrent engine plus a
  95-muscle NMJ layer over the real edges. Steering is explicit circuit
  models executed through real anatomy: a klinotaxis (weathervane) bias
  correlates the ASE concentration derivative with head-swing velocity,
  food/edge tropisms steer off instantaneous lateral signals, pirouettes
  kick away from food-behind, and dwelling inhibits B-class forward pools
  near food. All drives write into dorsal/ventral SMB+RMD head-motor
  neurons; turn reads the muscle head-bend (anterior D/V minus body D/V),
  speed reads B-minus-A motor pools. MODEL choices: food/wall channels
  stimulate ASE/AWC/ALM/PLM neurons (edge channels bypass the network),
  hunger scales sensory gain, CPG channels are dropped. Measured: L/R NMJ
  projections are crossed so the readout uses the D/V bend axis; the SMD
  seed is zeroed (the port default veers +0.18); one-sided input leaves
  motor output near-symmetric, so spatial steering cannot come from the
  rate port itself. Result: finds food in seconds near, ~1 min far/behind,
  dwells at edges ~75% without food. The bundled `connectome.json` is
  local-use only until data licensing is resolved.

## Pet system (minimal)

Two stats, `satiety` and `mood` (0–100), decay over ~10 and ~8 minutes.
Feeding restores satiety, petting restores mood. Low satiety slows the worm;
low mood dulls it slightly. Three interactions only: feed, pet, change skin
(4 presets, persisted in `UserDefaults`). No sleep, growth, or evolution.

System vitals modulate the network's output: CPU load scales
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
