import Foundation

/// Weathervane (klinotaxis) steering parameters. Tuned in closed-loop probe.
struct KlinotaxisParameters: Sendable {
    /// Head-swing sampling frequency.
    var frequencyHz = 0.5
    /// Correlation gain on dC/dt x head-velocity samples. Large: absorbs
    /// the ASE scale (~0.29) and the shallow lateral proximity gradient.
    var correlationGain = 3000.0
    /// Bias leak rate per tick while food is sensed (MODEL state dependence).
    var holdRate = 0.005
    /// Bias leak rate per tick without food: forgets quickly to straight runs.
    var forgetRate = 0.02
    /// Concentration below which the bias forgets.
    var forgetThreshold = 0.02
    /// Head-weave amplitude in turn units, added to the bias every tick.
    var weaveAmp = 0.15
    /// Injection scale into dorsal/ventral head-motor neurons.
    var motorGain = 1.0
    /// Dwelling gain: B-class forward-pool inhibition per unit ASE
    /// concentration. Slows the worm near food (orthokinesis) so it can
    /// arrive. Symmetric in D/V (measured bend <= +0.03); AVA was rejected
    /// (bends ventral, -0.08).
    var dwellGain = 1.0
    /// Dwelling cap: speed never drops to a stall outside capture range.
    var dwellCap = 0.15
    /// Lateral tropism gain on the instantaneous food signal. Carries
    /// reliable homing; klinotaxis modulates it with slow weathervane bias.
    /// MODEL: point food is a game artifact (lawns need no landing), and
    /// far-field correlation alone proved too weak to land on it.
    var tropismGain = 1.5
    /// Klinotaxis weight far from food (fades out over the handoff ramp).
    var klinoWeight = 0.5
    /// Proximity ramp over which tropism takes over from klinotaxis.
    var handoffLo = 0.15
    var handoffHi = 0.4
    /// Edge-preference drive on the lateral edge signal. Active only
    /// without food nearby; the network touch path steers inward, so
    /// edge preference is explicit (MODEL). 1.0 dwells at edges ~75%.
    var edgeGain = 1.0
    /// Pirouette kick strength (turn units) when food sits behind.
    var pirouetteTurn = 1.0
    /// Pirouette kick length in ticks.
    var pirouetteTicks = 15
    /// Ticks between pirouette kicks.
    var pirouetteCooldown = 40
}

/// Weathervane steering with lateral tropism and pirouettes.
///
/// A leaky bias integrates the correlation of the ASE concentration
/// derivative with head-swing velocity (klinotaxis); instantaneous lateral
/// tropism carries reliable homing. Tropism takes over with proximity
/// (no swing-cycle lag, tracks the fast-spinning close-in bearing) while
/// klinotaxis modulates far-field runs. Food directly behind (close, no
/// lateral signal, concentration falling) triggers an alternating-side
/// pirouette kick (klinokinesis-lite). All three write into dorsal/ventral
/// SMB+RMD head-motor neurons.
///
/// MODEL: the rate port cannot express temporal computation (nothing past
/// the sensory layer lateralizes), so correlation, handoff and pirouettes
/// live here while execution flows through real neurons, real NMJs and
/// real muscles. Klinotaxis uses single-point concentration only, like the
/// real animal; tropism and pirouettes read the spatial sensors.
/// Food appear/disappear steps exceed maxStep and skip the correlation.
struct KlinotaxisController: Sendable {
    /// Assumed brain tick rate. RealBrain already assumes 1/20 s ticks.
    static let ticksPerSecond = 20.0
    /// Steps above this skip the correlation (food appear/disappear).
    static let maxStep = 0.01
    /// Edge drive fades out over this proximity ramp (food wins).
    static let edgeGateLo = 0.05
    static let edgeGateHi = 0.12

    private(set) var phase = 0.0
    private(set) var bias = 0.0
    private var previousC = 0.0
    private var started = false
    private var warmupLeft = -1
    private var slowProx = 0.0
    private var kickTimer = 0
    private var cooldown = 0
    private var kickSide = 1.0

    /// Advance one tick. Returns dorsal/ventral head-motor drive.
    mutating func step(concentration: Double, proximity: Double, lateral: Double, edgeLateral: Double,
                      params: KlinotaxisParameters) -> (dorsal: Double, ventral: Double) {
        phase += 2 * .pi * params.frequencyHz / Self.ticksPerSecond
        if phase >= 2 * .pi { phase -= 2 * .pi }
        // First tick seeds the baselines (no food-at-start spike). The first
        // swing cycle skips updates: departure ramps contaminate it with a
        // side-independent term that helps left-food and breaks right-food.
        if warmupLeft < 0 {
            warmupLeft = Int((Self.ticksPerSecond / params.frequencyHz).rounded())
        }
        let rawDC = started ? concentration - previousC : 0
        if !started { slowProx = proximity }
        started = true
        previousC = concentration
        if warmupLeft > 0 {
            warmupLeft -= 1
        } else if abs(rawDC) <= Self.maxStep {
            // Correlation polarity verified in closed-loop probe: +1 homes,
            // -1 flees. (Phase analysis predicted -1; loop lags flip it.)
            let sample = params.correlationGain * rawDC * cos(phase)
            let rate = concentration > params.forgetThreshold ? params.holdRate : params.forgetRate
            bias += rate * (min(max(sample, -1), 1) - bias)
        }
        slowProx += 0.02 * (proximity - slowProx)
        if cooldown > 0 { cooldown -= 1 }
        var drive: Double
        if kickTimer > 0 {
            kickTimer -= 1
            drive = kickSide * params.pirouetteTurn
        } else {
            if cooldown == 0, proximity > 0.4, abs(lateral) < 0.1, proximity < slowProx - 0.03 {
                kickTimer = params.pirouetteTicks
                cooldown = params.pirouetteCooldown
                kickSide = -kickSide
                drive = kickSide * params.pirouetteTurn
            } else {
                let w = smoothstep(proximity, lo: params.handoffLo, hi: params.handoffHi)
                let edgeGate = 1 - smoothstep(proximity, lo: Self.edgeGateLo, hi: Self.edgeGateHi)
                drive = (1 - w) * params.klinoWeight * bias
                    + w * params.tropismGain * lateral
                    + edgeGate * params.edgeGain * edgeLateral
                    + params.weaveAmp * sin(phase)
            }
        }
        return (drive * params.motorGain, -drive * params.motorGain)
    }

    private func smoothstep(_ x: Double, lo: Double, hi: Double) -> Double {
        let t = min(max((x - lo) / (hi - lo), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
