//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// A convenience wrapper around a disappearing message timer duration value that
/// 1) handles seconds/millis conversion
/// 2) deals internally with the fact that `0` means "not enabled".
///
/// See also ``VersionedDisappearingMessageToken``, which is the same thing but
/// with an attached version that, at time of writing, used by 1:1 conversations (TSContactThread)
/// which are subject to races in setting their DM timer config.
@objc
public final class DisappearingMessageToken: NSObject, NSSecureCoding, NSCopying {
    public static var supportsSecureCoding: Bool { true }

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

public struct DisappearingMessagesConfigurationRecord: FetchableRecord, MutablePersistableRecord, Codable {
    public static let databaseTableName = "model_OWSDisappearingMessagesConfiguration"

    public private(set) var id: Int64?
    public let threadUniqueId: String
    public var durationSeconds: UInt32
    public var isEnabled: Bool
    public var timerVersion: UInt32

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case threadUniqueId = "uniqueId"
        case durationSeconds
        case isEnabled = "enabled"
        case timerVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.threadUniqueId = try container.decode(String.self, forKey: .threadUniqueId)
        self.durationSeconds = try container.decode(UInt32.self, forKey: .durationSeconds)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.timerVersion = try container.decode(UInt32.self, forKey: .timerVersion)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.id, forKey: .id)
        try container.encode(39, forKey: .recordType)
        try container.encode(self.threadUniqueId, forKey: .threadUniqueId)
        try container.encode(self.durationSeconds, forKey: .durationSeconds)
        try container.encode(self.isEnabled, forKey: .isEnabled)
        try container.encode(self.timerVersion, forKey: .timerVersion)
    }

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }

    init(
        id: Int64? = nil,
        threadUniqueId: String,
        isEnabled: Bool,
        durationSeconds: UInt32,
        timerVersion: UInt32,
    ) {
        owsAssertDebug(!threadUniqueId.isEmpty)
        self.id = id
        self.threadUniqueId = threadUniqueId
        self.isEnabled = isEnabled
        self.durationSeconds = durationSeconds
        self.timerVersion = timerVersion
    }

    public static func presetDurationsSeconds() -> [UInt32] {
        return [
            UInt32(30 * .second),
            UInt32(5 * .minute),
            UInt32(1 * .hour),
            UInt32(8 * .hour),
            UInt32(24 * .hour),
            UInt32(1 * .week),
            UInt32(4 * .week),
        ]
    }

    public func durationString() -> String {
        return String.formatDurationLossless(durationSeconds: self.durationSeconds)
    }

    public var asToken: DisappearingMessageToken {
        return DisappearingMessageToken(isEnabled: isEnabled, durationSeconds: durationSeconds)
    }

    public var asVersionedToken: VersionedDisappearingMessageToken {
        return VersionedDisappearingMessageToken(
            isEnabled: isEnabled,
            durationSeconds: durationSeconds,
            version: timerVersion,
        )
    }
}
