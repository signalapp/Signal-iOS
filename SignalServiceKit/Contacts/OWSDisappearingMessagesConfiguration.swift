//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A convenience wrapper around a disappearing message timer duration value that
/// 1) handles seconds/millis conversion
/// 2) deals internally with the fact that `0` means "not enabled".
///
/// See also ``VersionedDisappearingMessageToken``, which is the same thing but
/// with an attached version that, at time of writing, used by 1:1 conversations (TSContactThread)
/// which are subject to races in setting their DM timer config.
@objc
public final class DisappearingMessageToken: NSObject, NSCoding, NSCopying {
    public init?(coder: NSCoder) {
        self.durationSeconds = coder.decodeObject(of: NSNumber.self, forKey: "durationSeconds")?.uint32Value ?? 0
    }

    public func encode(with coder: NSCoder) {
        coder.encode(NSNumber(value: self.durationSeconds), forKey: "durationSeconds")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(durationSeconds)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard type(of: self) == type(of: object) else { return false }
        guard self.durationSeconds == object.durationSeconds else { return false }
        return true
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }

    @objc
    public var isEnabled: Bool {
        return durationSeconds > 0
    }

    public let durationSeconds: UInt32

    @objc
    public init(isEnabled: Bool, durationSeconds: UInt32) {
        // Consider disabled if duration is zero.
        // Use zero duration if not enabled.
        self.durationSeconds = isEnabled ? durationSeconds : 0

        super.init()
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
            version: timerVersion,
        )
    }
}
