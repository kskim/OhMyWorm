import Foundation
import IOKit.ps

/// System state that modulates the worm, RunCat-style.
/// Sampled with Mach/IOKit APIs that need no permissions or entitlements.
struct SystemVitals: Sendable {
    /// Overall CPU load, 0...1.
    var cpuLoad: Double = 0
    /// Battery level, 0...1. Nil on Macs without a battery.
    var batteryLevel: Double? = nil
    /// True when running on battery power (not charging).
    var onBatteryPower = false
}

final class VitalsSampler {
    private var previousIdle: UInt64 = 0
    private var previousTotal: UInt64 = 0
    private var hasPrevious = false

    func sample() -> SystemVitals {
        let battery = sampleBattery()
        return SystemVitals(cpuLoad: sampleCPU(), batteryLevel: battery.level, onBatteryPower: battery.onBattery)
    }

    /// Overall CPU usage from per-CPU tick deltas. First call returns 0.
    func sampleCPU() -> Double {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &cpuInfo, &cpuInfoCount)
        guard result == KERN_SUCCESS, let info = cpuInfo else { return 0 }
        defer {
            let bytes = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, unsafeBitCast(info, to: vm_address_t.self), bytes)
        }
        var idle: UInt64 = 0
        var total: UInt64 = 0
        let loads = info.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(cpuCount)) {
            Array(UnsafeBufferPointer(start: $0, count: Int(cpuCount)))
        }
        for load in loads {
            idle += UInt64(load.cpu_ticks.2)
            total += UInt64(load.cpu_ticks.0) + UInt64(load.cpu_ticks.1) + UInt64(load.cpu_ticks.2) + UInt64(load.cpu_ticks.3)
        }
        defer {
            previousIdle = idle
            previousTotal = total
            hasPrevious = true
        }
        guard hasPrevious, total > previousTotal else { return 0 }
        let usage = 1 - Double(idle - previousIdle) / Double(total - previousTotal)
        return min(max(usage, 0), 1)
    }

    /// Battery level plus power source. Desktops without a battery
    /// report (nil, false), i.e. full size at full speed.
    func sampleBattery() -> (level: Double?, onBattery: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return (nil, false)
        }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            return (nil, false)
        }
        guard let description = IOPSGetPowerSourceDescription(snapshot, sources[0])?.takeUnretainedValue() as? [String: Any] else {
            return (nil, false)
        }
        let state = description[kIOPSPowerSourceStateKey as String] as? String
        let onBattery = state == (kIOPSBatteryPowerValue as String)
        guard let current = description[kIOPSCurrentCapacityKey as String] as? Int,
              let maximum = description[kIOPSMaxCapacityKey as String] as? Int,
              maximum > 0 else {
            return (nil, onBattery)
        }
        return (min(max(Double(current) / Double(maximum), 0), 1), onBattery)
    }
}
