//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Mantle

/// A convenience wrapper around a disappearing message timer duration value that
/// 1) handles seconds/millis conversion
/// 2) deals internally with the fact that `0` means "not enabled".
///
/// See also ``VersionedDisappearingMessageToken``, which is the same thing but
/// with an attached version that, at time of writing, used by 1:1 conversations (TSContactThread)
/// which are subject to races in setting their DM timer config.
@objc
public class DisappearingMessageToken: MTLModel {
    @objc
    public var isEnabled: Bool {
        return durationSeconds > 0
    }

    @objc
    public var durationSeconds: UInt32 = 0

    @objc
    public init(isEnabled: Bool, durationSeconds: UInt32) {
        // Consider disabled if duration is zero.
        // Use zero duration if not enabled.
        self.durationSeconds = isEnabled ? durationSeconds : 0

        super.init()
    }

    // MARK: - MTLModel

    @objc
    public override init() {
        super.init()
    }

    @objc
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    // MARK: -

    public static var disabledToken: DisappearingMessageToken {
        return DisappearingMessageToken(isEnabled: false, durationSeconds: 0)
    }

    public class func token(forProtoExpireTimerSeconds expireTimerSeconds: UInt32?) -> DisappearingMessageToken {
        if let expireTimerSeconds, expireTimerSeconds > 0 {
            return DisappearingMessageToken(isEnabled: true, durationSeconds: expireTimerSeconds)
        } else {
            return .disabledToken
        }
    }
}

// MARK: -

public extension OWSDisappearingMessagesConfiguration {
    @objc
    var asToken: DisappearingMessageToken {
        return DisappearingMessageToken(isEnabled: isEnabled, durationSeconds: durationSeconds)
    }

    var asVersionedToken: VersionedDisappearingMessageToken {
        return VersionedDisappearingMessageToken(
            isEnabled: isEnabled,
            durationSeconds: durationSeconds,
            version: timerVersion
        )
    }
}
