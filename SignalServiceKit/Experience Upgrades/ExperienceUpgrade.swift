//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class ExperienceUpgrade: SDSCodableModel {
    public static let databaseTableName = "model_ExperienceUpgrade"
    public static var recordType: UInt { SDSRecordType.experienceUpgrade.rawValue }

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId

        case firstViewedTimestamp
        case lastSnoozedTimestamp
        case isComplete
        case manifest
    }

    public var id: RowId?
    public var uniqueId: String {
        manifest.uniqueId
    }

    public private(set) var firstViewedTimestamp: TimeInterval
    public private(set) var lastSnoozedTimestamp: TimeInterval
    public private(set) var isComplete: Bool

    /// Identifies and holds metadata about this ``ExperienceUpgrade``.
    public let manifest: ExperienceUpgradeManifest

    private init(manifest: ExperienceUpgradeManifest) {
        self.firstViewedTimestamp = 0
        self.lastSnoozedTimestamp = 0
        self.isComplete = false

        self.manifest = manifest
    }

    static func makeNew(withManifest manifest: ExperienceUpgradeManifest) -> ExperienceUpgrade {
        ExperienceUpgrade(manifest: manifest)
    }

    // MARK: - Codable

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(Int.self, forKey: .recordType)
        owsAssertDebug(decodedRecordType == Self.recordType, "Unexpectedly decoded record with wrong type.")

        id = try container.decodeIfPresent(RowId.self, forKey: .id)

        firstViewedTimestamp = try container.decode(TimeInterval.self, forKey: .firstViewedTimestamp)
        lastSnoozedTimestamp = try container.decode(TimeInterval.self, forKey: .lastSnoozedTimestamp)
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
        try container.encode(recordType, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)

        try container.encode(firstViewedTimestamp, forKey: .firstViewedTimestamp)
        try container.encode(lastSnoozedTimestamp, forKey: .lastSnoozedTimestamp)
        try container.encode(isComplete, forKey: .isComplete)

        try container.encode(manifest, forKey: .manifest)
    }
}

// MARK: - Mark as <state>

extension ExperienceUpgrade {
    public func markAsSnoozed(transaction: SDSAnyWriteTransaction) {
        upsert(withTransaction: transaction) { $0.lastSnoozedTimestamp = Date().timeIntervalSince1970 }
    }

    public func markAsComplete(transaction: SDSAnyWriteTransaction) {
        upsert(withTransaction: transaction) { $0.isComplete = true }
    }

    public func markAsViewed(transaction: SDSAnyWriteTransaction) {
        upsert(withTransaction: transaction) { upgrade in
            guard upgrade.firstViewedTimestamp == 0 else { return }
            upgrade.firstViewedTimestamp = Date().timeIntervalSince1970
        }
    }

    /// If an upgrade is already persisted with our `uniqueId`, performs `block`
    /// on it and updates. Otherwise, performs `block` on ourself and inserts
    /// ourself. Skips calling `block` if this upgrade should not be saved.
    private func upsert(withTransaction transaction: SDSAnyWriteTransaction, inBlock block: (ExperienceUpgrade) -> Void) {
        guard manifest.shouldSave else {
            Logger.debug("Skipping save for experience upgrade: \(String(describing: id))")
            return
        }

        let experienceToUpgrade = ExperienceUpgrade.anyFetch(uniqueId: uniqueId, transaction: transaction) ?? self
        block(experienceToUpgrade)
        experienceToUpgrade.anyUpsert(transaction: transaction)
    }
}
