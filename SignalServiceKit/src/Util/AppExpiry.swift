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
        return daysUntilBuildExpiry <= 10
    }

    @objc
    public static var isExpired: Bool {
        return daysUntilBuildExpiry <= 0
    }
}
