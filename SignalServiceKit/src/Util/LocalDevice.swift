//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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

        let mallocSize: UInt64
        let mallocAllocations: UInt64

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

            if DebugFlags.internalLogging, CurrentAppContext().isNSE {
                // Losing log messages is painful when trying to track down memory usage bugs
                OWSLogger.aggressiveFlushing = (vmInfo.limit_bytes_remaining < 1024 * 1024)
            }

            return MemoryStatus(
                fetchDate: Date(),
                footprint: vmInfo.phys_footprint,
                peakFootprint: vmInfo.ledger_phys_footprint_peak,
                bytesRemaining: vmInfo.limit_bytes_remaining,
                mallocSize: UInt64(statistics.size_in_use),
                mallocAllocations: UInt64(statistics.size_allocated)
            )
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

        switch (freeBytes, CurrentAppContext().isNSE) {
        case (..<criticalThreshold, true):
            return "\(currentFootprint) ⚠️⚠️⚠️ \(freeBytes) remaining — mallocUsage: \(mallocUsage) / \(mallocAllocations)"
        case (..<warnThreshold, _):
            return "\(currentFootprint) — \(freeBytes) remaining — mallocUsage: \(mallocUsage) / \(mallocAllocations)"
        default:
            return "\(currentFootprint)"
        }
    }
}
