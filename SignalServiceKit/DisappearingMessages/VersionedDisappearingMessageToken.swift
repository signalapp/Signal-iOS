//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A ``DisappearingMessageToken`` with a version number that can be used to compare
/// two tokens and know which was set first.
///
/// At time of writing, used by 1:1 conversations (TSContactThread) which are subject to races in
/// setting their DM timer config. Group conversations don't have the same races, as they use shared
/// and version-controlled group state, so they use unversioned ``DisappearingMessageToken``s.
public struct VersionedDisappearingMessageToken {

    /// Consider disabled if duration is zero.
    public var isEnabled: Bool {
        return durationSeconds > 0
    }

    public let durationSeconds: UInt32
    public let version: UInt32

    public init(durationSeconds: UInt32, version: UInt32?) {
        self.durationSeconds = durationSeconds
        // 0 and nil version are equivalent.
        self.version = version ?? 0
    }

    public init(
        isEnabled: Bool,
        durationSeconds: UInt32,
        version: UInt32?
    ) {
        // Consider disabled if duration is zero.
        // Use zero duration if not enabled.
        let durationSeconds = isEnabled ? durationSeconds : 0
        self.init(durationSeconds: durationSeconds, version: version)
    }

    // MARK: -

    public static func forGroupThread(
        isEnabled: Bool,
        durationSeconds: UInt32
    ) -> Self {
        // Version is unused for group threads
        return .init(isEnabled: isEnabled, durationSeconds: durationSeconds, version: nil)
    }

    public static func forUniversalTimer(
        isEnabled: Bool,
        durationSeconds: UInt32
    ) -> Self {
        // Version is unused for the universal timer
        return .init(isEnabled: isEnabled, durationSeconds: durationSeconds, version: nil)
    }

    public static func token(
        forProtoExpireTimerSeconds expireTimerSeconds: UInt32?,
        version: UInt32?
    ) -> Self {
        return .init(durationSeconds: expireTimerSeconds ?? 0, version: version)
    }
}

extension VersionedDisappearingMessageToken {

    public var unversioned: DisappearingMessageToken {
        return .init(isEnabled: isEnabled, durationSeconds: durationSeconds)
    }
}
