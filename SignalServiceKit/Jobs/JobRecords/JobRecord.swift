//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// ``JobRecord`` was migrated from a previous model that used SDS codegen, and
/// additionally used inheritance. Consequently, it uses factory initialization
/// via ``NeedsFactoryInitializationFromRecordType``. See that type for
/// more details.
extension JobRecord: NeedsFactoryInitializationFromRecordType {
    /// Identifies a specific ``JobRecord`` subclass.
    ///
    /// The raw value of this type represents the value to use for the
    /// `recordType` database column required for SDS types.
    ///
    /// Old job records, migrated from the SDS codegen, will have raw values
    /// derived from ``SDSRecordType``. Job records introduced after migration
    /// of ``JobRecord`` to ``SDSCodableModel`` must provide their own unique
    /// values here for factory initialization.
    enum JobRecordType: UInt, CaseIterable {

        // MARK: Values originally from SDSRecordType

        case incomingContactSync = 61
        case legacyMessageDecrypt = 53
        case localUserLeaveGroup = 74
        case messageSender = 35
        case donationReceiptCredentialRedemption = 71
        case sendGiftBadge = 73
        case sessionReset = 52

        // MARK: Created after migration to SDSCodableModel

        case callRecordDeleteAll = 100
        case bulkDeleteInteractionJobRecord = 101
        case backupReceiptsCredentialRedemption = 102
    }

    static var recordTypeCodingKey: JobRecordColumns {
        .recordType
    }

    static func classToInitialize(forRecordType recordType: UInt) -> (FactoryInitializableFromRecordType.Type)? {
        guard let jobRecordType = JobRecordType(rawValue: recordType) else {
            return nil
        }

        switch jobRecordType {
        case .incomingContactSync: return IncomingContactSyncJobRecord.self
        case .legacyMessageDecrypt: return LegacyMessageDecryptJobRecord.self
        case .localUserLeaveGroup: return LocalUserLeaveGroupJobRecord.self
        case .messageSender: return MessageSenderJobRecord.self
        case .donationReceiptCredentialRedemption: return DonationReceiptCredentialRedemptionJobRecord.self
        case .sendGiftBadge: return SendGiftBadgeJobRecord.self
        case .sessionReset: return SessionResetJobRecord.self
        case .callRecordDeleteAll: return CallRecordDeleteAllJobRecord.self
        case .bulkDeleteInteractionJobRecord: return BulkDeleteInteractionJobRecord.self
        case .backupReceiptsCredentialRedemption: return BackupReceiptCredentialRedemptionJobRecord.self
        }
    }
}

extension JobRecord.JobRecordType {
    var jobRecordLabel: String {
        // These values are persisted and must not change, even if they're misspelled.
        switch self {
        case .incomingContactSync:
            return "IncomingContactSync"
        case .legacyMessageDecrypt:
            return "SSKMessageDecrypt"
        case .localUserLeaveGroup:
            return "LocalUserLeaveGroup"
        case .messageSender:
            return "MessageSender"
        case .donationReceiptCredentialRedemption:
            return "SubscriptionReceiptCredentailRedemption"
        case .sendGiftBadge:
            return "SendGiftBadge"
        case .sessionReset:
            return "SessionReset"
        case .callRecordDeleteAll:
            return "CallRecordDeleteAll"
        case .bulkDeleteInteractionJobRecord:
            return "BulkDeleteInteraction"
        case .backupReceiptsCredentialRedemption:
            return "BackupReceiptCredentialRedemption"
        }
    }
}

public class JobRecord: SDSCodableModel {
    public enum Status: Int {
        case unknown = 0
        case ready
        case running
        case permanentlyFailed
        case obsolete
    }

    public static let databaseTableName: String = "model_SSKJobRecord"

    class var jobRecordType: JobRecordType { owsFail("Must be provided by subclasses!") }
    public static var recordType: UInt { jobRecordType.rawValue }

    public var id: RowId?
    public let uniqueId: String

    let label: String
    #if TESTABLE_BUILD
    var exclusiveProcessIdentifier: String?
    #else
    let exclusiveProcessIdentifier: String?
    #endif
    public private(set) var failureCount: UInt
    private(set) var status: Status

    init(
        failureCount: UInt,
        status: Status
    ) {
        uniqueId = UUID().uuidString

        self.label = Self.jobRecordType.jobRecordLabel
        self.exclusiveProcessIdentifier = nil
        self.failureCount = failureCount
        self.status = status
    }

    public func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }

    // MARK: Codable and inheritance-related hacks

    public typealias CodingKeys = JobRecordColumns

    init(baseClassDuringFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(SDSCodableModel.RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)

        label = try container.decode(String.self, forKey: .label)
        failureCount = try container.decode(UInt.self, forKey: .failureCount)
        status = Status(rawValue: try container.decode(Int.self, forKey: .status)) ?? .unknown
        exclusiveProcessIdentifier = try container.decodeIfPresent(String.self, forKey: .exclusiveProcessIdentifier)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try id.map { try container.encode($0, forKey: .id) }
        try container.encode(Self.recordType, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)

        try container.encode(label, forKey: .label)
        try container.encode(failureCount, forKey: .failureCount)
        try container.encode(status.rawValue, forKey: .status)
        try container.encodeIfPresent(exclusiveProcessIdentifier, forKey: .exclusiveProcessIdentifier)
    }
}

// MARK: - Failures

extension JobRecord {
    public func addFailure(tx: SDSAnyWriteTransaction) {
        anyUpdate(transaction: tx) { record in record.failureCount += 1 }
    }
}
