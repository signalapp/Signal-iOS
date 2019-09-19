//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(SSKAppExpiry)
public class AppExpiry: NSObject {
    @objc
    public static var daysUntilBuildExpiry: Int {
        guard let buildAge = Calendar.current.dateComponents(
            [.day],
            from: CurrentAppContext().buildTime,
            to: Date()
        ).day else {
            owsFailDebug("Unexpectedly found nil buildAge, this should not be possible.")
            return 0
        }
        return 90 - buildAge
    }

    @objc
    public static var isExpiringSoon: Bool {
        guard !isEndOfLifeOSVersion else { return false }
        return daysUntilBuildExpiry <= 10
    }

    @objc
    public static var isExpired: Bool {
        guard !isEndOfLifeOSVersion else { return false }
        return daysUntilBuildExpiry <= 0
    }

    /// Indicates if this iOS version is no longer supported. If so,
    /// we don't ever expire the build as newer builds will not be
    /// installable on their device and show a special banner
    /// that indicates we will no longer support their device.
    ///
    /// Currently, only iOS 10 and greater are officially supported.
    @objc
    public static var isEndOfLifeOSVersion: Bool {
        if #available(iOS 10, *) {
            return false
        } else {
            return true
        }
    }
}
