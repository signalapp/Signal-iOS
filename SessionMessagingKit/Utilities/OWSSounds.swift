// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SignalCoreKit

extension OWSSound {
    
    public func notificationSound(isQuiet: Bool) -> UNNotificationSound {
        guard let filename = OWSSounds.filename(for: self, quiet: isQuiet) else {
            owsFailDebug("filename was unexpectedly nil")
            return UNNotificationSound.default
        }
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: filename))
    }
}
