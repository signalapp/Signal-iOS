//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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

    public static var memoryUsageUInt64: UInt64? {
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

        return vmInfo.phys_footprint
    }

    @objc
    public static var memoryUsage: String {
        guard let memoryUsageUInt64 = self.memoryUsageUInt64 else {
            return "Unknown"
        }
        return "\(memoryUsageUInt64)"
    }
}
