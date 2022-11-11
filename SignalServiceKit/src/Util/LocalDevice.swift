//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
public class LocalDevice: NSObject {
    @objc
    public static var allCoreCount: Int {
        ProcessInfo.processInfo.processorCount
    }

    @objc
    public static var activeCoreCount: Int {
        // iOS can shut down cores, so we consult activeProcessorCount,
        // not processorCount.
        ProcessInfo.processInfo.activeProcessorCount
    }

    public struct MemoryStatus {
        public let fetchDate: Date
        public let footprint: UInt64
        public let peakFootprint: Int64
        public let bytesRemaining: UInt64
        public let mallocSize: Int64
        public let mallocAllocations: Int64

        fileprivate static func fetchCurrentStatus() -> MemoryStatus? {
            let vmInfoExpectedSize = MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
            var vmInfo = task_vm_info_data_t()
            var vmInfoSize = mach_msg_type_number_t(vmInfoExpectedSize)

            let kern: kern_return_t = withUnsafeMutablePointer(to: &vmInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(mach_task_self_,
                              task_flavor_t(TASK_VM_INFO),
                              $0,
                              &vmInfoSize)
                }
            }

            guard kern == KERN_SUCCESS else {
                let errorString = String(cString: mach_error_string(kern), encoding: .ascii) ?? "Unknown error"
                owsFailDebug(errorString)
                return nil
            }

            let mallocZone = malloc_default_zone()
            var statistics = malloc_statistics_t()
            malloc_zone_statistics(mallocZone, &statistics)

            let result = MemoryStatus(
                fetchDate: Date(),
                footprint: vmInfo.phys_footprint,
                peakFootprint: vmInfo.ledger_phys_footprint_peak,
                bytesRemaining: vmInfo.limit_bytes_remaining,
                mallocSize: Int64(statistics.size_in_use),
                mallocAllocations: Int64(statistics.size_allocated)
            )

#if !DEBUG
            if CurrentAppContext().isNSE {
                if result.bytesRemaining > 0 {
                    // If we're running out of free memory, let's start aggressively flushing
                    // our log messages. This way, we don't lose any logs when we're suddenly terminated.
                    // There's a perf cost here, but we're going to be killed soon anyway so it's not a big deal.
                    OWSLogger.aggressiveFlushing = result.bytesRemaining < (4 * 1024 * 1024)
                } else {
                    // The source of the remaining bits is fairly under documented. In my testing, things
                    // seem to be working as expected. Just to be safe, let's interpret 0 free bytes as invalid
                    // and fall back to a different heuristic.
                    OWSLogger.aggressiveFlushing = result.footprint > (20 * 1024 * 1024)
                }
            }
#endif

            return result
        }
    }

    private static var _memoryStatus = AtomicOptional<MemoryStatus>(nil)
    public static func currentMemoryStatus(forceUpdate: Bool = false) -> MemoryStatus? {
        // If we don't have a cached status, we must fetch
        guard let currentStatus = _memoryStatus.get() else {
            return _memoryStatus.map { _ in MemoryStatus.fetchCurrentStatus() }
        }

        let cacheValidityPeriod: TimeInterval = 1.0
        if forceUpdate || currentStatus.fetchDate.addingTimeInterval(cacheValidityPeriod).isBeforeNow {
            return _memoryStatus.map { _ in MemoryStatus.fetchCurrentStatus() }
        } else {
            return currentStatus
        }
    }

    @objc
    public static var memoryUsageString: String {
        // Since this string is intended to be logged, we should fetch a fresh status
        guard let currentMemoryStatus = currentMemoryStatus(forceUpdate: true) else {
            return "Unknown"
        }

        let currentFootprint = currentMemoryStatus.footprint
        let freeBytes = currentMemoryStatus.bytesRemaining
        let mallocUsage = currentMemoryStatus.mallocSize
        let mallocAllocations = currentMemoryStatus.mallocAllocations

        let warnThreshold: UInt64 = 5 * 1024 * 1024
        let criticalThreshold = UInt64(1.5 * 1024 * 1024)

        switch freeBytes {
        case ..<criticalThreshold:
            return "\(currentFootprint) - CRITICAL - \(freeBytes) remaining — mallocUsage: \(mallocUsage) / \(mallocAllocations)"
        case ..<warnThreshold:
            return "\(currentFootprint) — WARNING  - \(freeBytes) remaining — mallocUsage: \(mallocUsage) / \(mallocAllocations)"
        default:
            return "\(currentFootprint)"
        }
    }
}
