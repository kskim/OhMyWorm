# Architecture

OhMyWorm is a desktop pet for macOS: a small worm crawls freely over the
desktop, driven by a miniature recurrent neural network. No dock icon, no main
window — just the worm and a `🐛` status item holding the only menu.

## Runtime structure

```text
Timer (20 Hz) -> PetController -> PetModel.update -> Brain.step (light/real)
                                              |-> trail / stats / particles
PetController -> DesktopPanel (fullscreen static overlay) -> WormView (Canvas)
Global mouse monitor -> pet / carry (left button only)
Status item menu -> feed / skin / engine / pause / quit
```

## Modules

| File | Role |
| --- | --- |
| `App/OhMyWormApp.swift` | Agent app entry (`LSUIElement`), status item, screen-change handling |
| `App/Pet/PetController.swift` | Game loop, screen bounds, food/pet/skin/pause actions, global mouse monitor |
| `App/Pet/PetModel.swift` | Pure game state: movement, trail, satiety/mood, food, particles |
| `App/Pet/MiniBrain.swift` | Light: hand-wired recurrent network (13 inputs, 6 hidden, 2 outputs) |
| `App/Pet/Real/` | Real: real 302-neuron engine + NMJ muscles + steering controller + bundled data |
| `App/Pet/LocomotionEngine.swift` | Engine protocol, `Brain` selector, `EngineID` |
| `App/Pet/DesktopPanel.swift` | Fullscreen click-through transparent `NSPanel`; never moves |
| `App/Pet/SystemVitals.swift` | CPU/battery sampling via Mach/IOKit, no permissions needed |
| `App/Pet/WormView.swift` | SwiftUI Canvas rendering: worm, food, hearts |
| `App/Pet/PetMenu.swift` | The one and only menu, hosted by the status item |

## The two engines

Every locomotion decision flows through the selected engine; only game
states (eating, being carried) and the hard wall constraint bypass it.
Walls are avoided by steering, not bouncing: wall sensors look ahead
140 pt and steer only by approach (parallel cruising is unpenalized),
and the last-resort constraint slides along the wall instead of
reflecting. Bounds are the full screen frame minus the Dock (the menu bar
strip stays open); Dock moves re-resolve through screen-change refits.
All engines are fully deterministic: same inputs, same path. Switching
engines resets neural state; position and stats are kept. Selection is
persisted in `UserDefaults`.

- **Light** (`MiniBrain`) is a game model, not biological data. Sensory
  inputs (food direction/proximity, outward direction, wall
  direction/proximity, cursor direction/proximity, hunger, two exploratory
  oscillators) feed six recurrent tanh units — food steering, edge steering,
  wall/cursor avoidance, approach drive, and an oscillator pair — producing
  a turn rate and speed.
- **Real** (`RealBrain`) runs the real 302-neuron recurrent engine plus a
  95-muscle NMJ layer over the real edges. Steering is explicit circuit
  models executed through real anatomy: a klinotaxis (weathervane) bias
  correlates the ASE concentration derivative with head-swing velocity,
  food/edge tropisms steer off instantaneous lateral signals, pirouettes
  kick away from food-behind, an aversive drive flees the cursor (the
  touch path alone moves the bend only +/-0.03), and dwelling inhibits
  B-class forward pools near food. All drives write into dorsal/ventral
  SMB+RMD head-motor
  neurons; turn reads the muscle head-bend (anterior D/V minus body D/V),
  speed reads B-minus-A motor pools. MODEL choices: food/wall/cursor channels
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
low mood dulls it slightly. Food is one of 5 random fruits, and a starving
worm (satiety 0) gets one dropped automatically. Three interactions only:
feed, pet, change skin (3 presets with distinct body shapes, persisted in
`UserDefaults`). No sleep, growth, or evolution. The menu is bilingual:
`L10n` picks Korean when the system prefers it, English otherwise.

System vitals modulate the network's output: CPU load scales
speed (0.6x–2.0x), running on battery shortens the tail (×5/8 segments),
and battery level scales body size (0.7x–1.0x). Desktops without a battery
read as full/AC.
Vitals resample every 2 seconds.

## Performance

The overlay covers the whole screen and never moves (a following panel
steps at the 20 Hz tick rate, which reads as trembling on static objects),
and the loop runs at 20 Hz. Measured on an Apple M4 Pro: ~8% CPU, ~30 MB
RAM in Release. The model itself is negligible; the cost is SwiftUI/Canvas
render and commit overhead per frame.

## History

This project previously contained a C. elegans connectome inspector and data
pipeline. That code was removed during the pivot to a desktop pet; it remains
available at the `backup/pre-pet-pivot` tag.
