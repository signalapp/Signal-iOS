//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// MARK: - Protocol

protocol UpgradableDevice {
    var iosMajorVersion: Int { get }

    func canUpgrade(to iosMajorVersion: Int) -> Bool
}

// MARK: - Implementation

extension UIDevice: UpgradableDevice {
    public var iosMajorVersion: Int { ProcessInfo().operatingSystemVersion.majorVersion }

    /// Can this device upgrade to this iOS version?
    ///
    /// This method is meant to be low-maintenance for Signal developers. Therefore, if we aren't
    /// sure whether a device can upgrade, we return `true`. In other words, this method may return
    /// false positives.
    public func canUpgrade(to iosMajorVersion: Int) -> Bool {
        let isOsSupportedByThisFunction = (
            systemName.contains("iOS") ||
            systemName.contains("iPhone") ||
            systemName.contains("iPad")
        )
        guard isOsSupportedByThisFunction else {
            owsFailBeta("\(systemName) is not a supported OS")
            return true
        }

        // If we're already past that version, no need to consult the list below.
        if self.iosMajorVersion >= iosMajorVersion { return true }

        // This list, lifted from [iOS Ref][0], is incomplete in two ways:
        //
        // 1. This list only contains devices with an explicit maximum version. As of this writing,
        //    the iPhone 14 has no maximum iOS version, so we omit it.
        // 2. This was last updated when iOS 13 was Signal's minimum supported version. Therefore,
        //    there's no point including devices like the iPhone 6, as they can't even run this
        //    code.
        //
        // If a device is missing from this list, we assume it can upgrade.
        //
        // [0]: https://iosref.com/ios
        let maxMajorVersion: Int
        switch String(sysctlKey: "hw.machine") {
        case
            // iPhone 7 (plus)
            "iPhone9,1",
            "iPhone9,2",
            "iPhone9,3",
            "iPhone9,4",
            // iPhone SE (gen 1)
            "iPhone8,4",
            // iPhone 6S (plus)
            "iPhone8,1",
            "iPhone8,2",
            // iPad Mini 4
            "iPad5,1",
            "iPad5,2",
            // iPad Air 2
            "iPad5,3",
            "iPad5,4",
            // iPod Touch (gen 7)
            "iPod9,1":
            maxMajorVersion = 15
        default:
            return true
        }

        return maxMajorVersion >= iosMajorVersion
    }
}
