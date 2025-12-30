//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public class DeviceBatteryLevelMonitorImpl: DeviceBatteryLevelMonitor {

    fileprivate let reason: String
    fileprivate var wasReleased: Bool = false

    fileprivate init(reason: String) {
        self.reason = reason
    }

    deinit {
        if !wasReleased {
            owsFailDebug("End battery monitoring before releasing ref!")
        }
    }

    public var batteryLevel: Float {
        // On simulators, the battery level always reports -1.0 (invalid).
        if Platform.isSimulator {
            return 1
        } else {
            return UIDevice.current.batteryLevel
        }
    }

    public var notification: Notification.Name { UIDevice.batteryLevelDidChangeNotification }
}

public class DeviceBatteryLevelManagerImpl: DeviceBatteryLevelManager {

    private var reasons = Set<String>()

    public init() {}

    public func beginMonitoring(reason: String) -> DeviceBatteryLevelMonitor {
        if reasons.isEmpty {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        let (duplicate, _) = reasons.insert(reason)
        if !duplicate {
            owsFailDebug("Duplicate monitoring reason!")
        }
        return DeviceBatteryLevelMonitorImpl(
            reason: reason,
        )
    }

    public func endMonitoring(_ monitor: DeviceBatteryLevelMonitor) {
        guard let monitor = monitor as? DeviceBatteryLevelMonitorImpl else {
            owsFailDebug("Invalid type combination")
            return
        }
        if monitor.wasReleased {
            owsFailDebug("Ending monitoring twice!")
        }
        reasons.remove(monitor.reason)
        monitor.wasReleased = true
        if reasons.isEmpty {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
    }

    public var isLowPowerModeEnabled: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    public var isLowPowerModeChangedNotification: Notification.Name { .NSProcessInfoPowerStateDidChange }
}
