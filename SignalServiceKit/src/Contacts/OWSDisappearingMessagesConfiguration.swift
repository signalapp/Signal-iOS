//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public struct DisappearingMessageToken: Equatable {
    public let isEnabled: Bool
    public let durationSeconds: UInt32

    public init(isEnabled: Bool, durationSeconds: UInt32) {
        self.isEnabled = isEnabled
        // Use zero duration if not enabled.
        self.durationSeconds = isEnabled ? durationSeconds : 0
    }

    public static var disabledToken: DisappearingMessageToken {
        return DisappearingMessageToken(isEnabled: false, durationSeconds: 0)
    }

    // MARK: Equatable

    public static func == (lhs: DisappearingMessageToken, rhs: DisappearingMessageToken) -> Bool {
        if lhs.isEnabled != rhs.isEnabled {
            return false
        }
        if !lhs.isEnabled {
            // Don't bother comparing duration if not enabled.
            return true
        }
        return lhs.durationSeconds == rhs.durationSeconds
    }
}

// MARK: -

public extension OWSDisappearingMessagesConfiguration {
    var asToken: DisappearingMessageToken {
        return DisappearingMessageToken(isEnabled: isEnabled, durationSeconds: durationSeconds)
    }
}
