//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public class ExperienceUpgrade: Codable, FetchableRecord, PersistableRecord {
    public typealias IDType = Int64

    public static let databaseTableName = "model_ExperienceUpgrade"
    private static var recordType: SDSRecordType { .experienceUpgrade }

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case recordType
        case uniqueId

        case firstViewedTimestamp
        case lastSnoozedTimestamp
        case snoozeCount
        case isComplete
        case manifest
    }

    public var id: IDType?

    public var uniqueId: String {
        manifest.uniqueId
    }

    /// Timestamp when this upgrade was first viewed.
    public var firstViewedTimestamp: TimeInterval

    /// Timestamp when this upgrade was last snoozed.
    public var lastSnoozedTimestamp: TimeInterval

    /// Number of times this upgrade has been snoozed.
    public var snoozeCount: UInt

    /// Whether this upgrade should be considered fully complete.
    public var isComplete: Bool

    /// Identifies and holds metadata about this ``ExperienceUpgrade``.
    public var manifest: ExperienceUpgradeManifest

    private init(manifest: ExperienceUpgradeManifest) {
        self.firstViewedTimestamp = 0
        self.lastSnoozedTimestamp = 0
        self.snoozeCount = 0
        self.isComplete = false

        self.manifest = manifest
    }

    public static func makeNew(withManifest manifest: ExperienceUpgradeManifest) -> ExperienceUpgrade {
        ExperienceUpgrade(manifest: manifest)
    }

    // MARK: - PersistableRecord

    public func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }

    public static let persistenceConflictPolicy: PersistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace,
    )

    public func upsert(tx: DBWriteTransaction) throws {
        try self.insert(tx.database)
    }

    // MARK: - Codable

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(Int64.self, forKey: .recordType)
        owsAssertDebug(decodedRecordType == Self.recordType.rawValue, "Unexpectedly decoded record with wrong type.")

        id = try container.decodeIfPresent(IDType.self, forKey: .id)

        firstViewedTimestamp = try container.decode(TimeInterval.self, forKey: .firstViewedTimestamp)
        lastSnoozedTimestamp = try container.decode(TimeInterval.self, forKey: .lastSnoozedTimestamp)
        snoozeCount = try container.decode(UInt.self, forKey: .snoozeCount)
        isComplete = try container.decode(Bool.self, forKey: .isComplete)

        let persistedUniqueId = try container.decode(String.self, forKey: .uniqueId)

        manifest = try {
            if let manifest = try container.decodeIfPresent(ExperienceUpgradeManifest.self, forKey: .manifest) {
                return manifest
            }

            return ExperienceUpgradeManifest.makeLegacy(fromPersistedExperienceUpgradeUniqueId: persistedUniqueId)
        }()

        owsAssertDebug(uniqueId == persistedUniqueId, "Persisted unique ID does not match deserialized model!")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try id.map { try container.encode($0, forKey: .id) }
        try container.encode(Self.recordType.rawValue, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)

        try container.encode(firstViewedTimestamp, forKey: .firstViewedTimestamp)
        try container.encode(lastSnoozedTimestamp, forKey: .lastSnoozedTimestamp)
        try container.encode(snoozeCount, forKey: .snoozeCount)
        try container.encode(isComplete, forKey: .isComplete)

        try container.encode(manifest, forKey: .manifest)
    }

    // MARK: -

    public func isSnoozed(now: Date) -> Bool {
        guard
            lastSnoozedTimestamp > 0,
            snoozeCount > 0
        else {
            return false
        }

        // Check if enough time has passed since the last snooze date.
        let timeSinceLastSnooze = now.timeIntervalSince(Date(timeIntervalSince1970: lastSnoozedTimestamp))
        return timeSinceLastSnooze <= manifest.snoozeDuration(forSnoozeCount: snoozeCount)
    }

    public func hasPassedNumberOfDaysToShow(now: Date) -> Bool {
        guard firstViewedTimestamp > 0 else {
            return false
        }

        guard
            let daysSinceFirstView = Calendar.current.dateComponents(
                [.day],
                from: Date(timeIntervalSince1970: firstViewedTimestamp),
                to: now,
            ).day
        else {
            owsFailDebug("Failed to get day component?")
            return false
        }

        return Int(clamping: daysSinceFirstView) > manifest.numberOfDaysToShowFor
    }
}
