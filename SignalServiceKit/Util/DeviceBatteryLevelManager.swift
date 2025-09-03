//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Notification.Name {
    public static let batteryLevelChanged: Notification.Name = UIDevice.batteryLevelDidChangeNotification
    public static let batteryLowPowerModeChanged: Notification.Name = .NSProcessInfoPowerStateDidChange
}

@MainActor
public protocol DeviceBatteryLevelMonitor {
    /// A value from 0 to 1
    var batteryLevel: Float { get }
}

@MainActor
public protocol DeviceBatteryLevelManager {

    /// Setting `UIDevice.isBatteryMonitoringEnabled` incurs a cost and Apple would like we
    /// only do it as strictly needed. To manage this app wide, use a unique reason string. As long
    /// as some monitor is active, battery monitoring will be enabled (thus allowing checking the
    /// current battery level and getting battery level change notifications).
    func beginMonitoring(reason: String) -> DeviceBatteryLevelMonitor

    /// MUST call this before releasing the reference to the DeviceBatteryLevelMonitor from `beginMonitoring`.
    func endMonitoring(_ monitor: DeviceBatteryLevelMonitor)

    var isLowPowerModeEnabled: Bool { get }
}
