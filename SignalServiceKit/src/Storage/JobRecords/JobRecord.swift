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
        /// Value originally from ``SDSRecordType``.
        case broadcastMediaMessage = 58
        /// Value originally from ``SDSRecordType``.
        case incomingContactSync = 61
        /// Value originally from ``SDSRecordType``.
        ///
        /// This job record type is deprecated, but left around in case any are
        /// currently-persisted and need to be cleaned up.
        case deprecated_incomingGroupSync = 60
        /// Value originally from ``SDSRecordType``.
        case legacyMessageDecrypt = 53
        /// Value originally from ``SDSRecordType``.
        case localUserLeaveGroup = 74
        /// Value originally from ``SDSRecordType``.
        case messageSender = 35
        /// Value originally from ``SDSRecordType``.
        case receiptCredentialRedemption = 71
        /// Value originally from ``SDSRecordType``.
        case sendGiftBadge = 73
        /// Value originally from ``SDSRecordType``.
        case sessionReset = 52
    }

    static var recordTypeCodingKey: JobRecordColumns {
        .recordType
    }

    static func classToInitialize(forRecordType recordType: UInt) -> (FactoryInitializableFromRecordType.Type)? {
        guard let jobRecordType = JobRecordType(rawValue: recordType) else {
            return nil
        }

        switch jobRecordType {
        case .broadcastMediaMessage: return BroadcastMediaMessageJobRecord.self
        case .incomingContactSync: return IncomingContactSyncJobRecord.self
        case .deprecated_incomingGroupSync: return IncomingGroupSyncJobRecord.self
        case .legacyMessageDecrypt: return LegacyMessageDecryptJobRecord.self
        case .localUserLeaveGroup: return LocalUserLeaveGroupJobRecord.self
        case .messageSender: return MessageSenderJobRecord.self
        case .receiptCredentialRedemption: return ReceiptCredentialRedemptionJobRecord.self
        case .sendGiftBadge: return SendGiftBadgeJobRecord.self
        case .sessionReset: return SessionResetJobRecord.self
        }
    }
}

extension JobRecord.JobRecordType {
    var jobRecordLabel: String {
        // These values are persisted and must not change, even if they're misspelled.
        switch self {
        case .broadcastMediaMessage:
            return "BroadcastMediaMessage"
        case .incomingContactSync:
            return "IncomingContactSync"
        case .deprecated_incomingGroupSync:
            return "IncomingGroupSync"
        case .legacyMessageDecrypt:
            return "SSKMessageDecrypt"
        case .localUserLeaveGroup:
            return "LocalUserLeaveGroup"
        case .messageSender:
            return "MessageSender"
        case .receiptCredentialRedemption:
            return "SubscriptionReceiptCredentailRedemption"
        case .sendGiftBadge:
            return "SendGiftBadge"
        case .sessionReset:
            return "SessionReset"
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
    private(set) var exclusiveProcessIdentifier: String?
    public private(set) var failureCount: UInt
    private(set) var status: Status

    init(
        exclusiveProcessIdentifier: String?,
        failureCount: UInt,
        status: Status
    ) {
        uniqueId = UUID().uuidString

        self.label = Self.jobRecordType.jobRecordLabel
        self.exclusiveProcessIdentifier = exclusiveProcessIdentifier
        self.failureCount = failureCount
        self.status = status
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

// MARK: - Process exclusivity

private let _currentProcessIdentifier: String = UUID().uuidString

extension JobRecord {
    /// An identifier for the current process.
    ///
    /// If a persisted job has a process identifier that does not match the
    /// current one, it will be cleaned up by ``JobQueue.pruneStaleJobs()``,
    /// which finds and removes "stale" records.
    static var currentProcessIdentifier: String { _currentProcessIdentifier }

    func flagAsExclusiveForCurrentProcessIdentifier() {
        self.exclusiveProcessIdentifier = _currentProcessIdentifier
    }
}

// MARK: - JobRecordError

enum JobRecordError: Error {
    case illegalStateTransition
    case assertionError(message: String)
}

// MARK: - Setting status

extension JobRecord {
    func saveRunningAsReady(transaction: SDSAnyWriteTransaction) throws {
        switch status {
        case .running:
            updateStatus(to: .ready, withTransaction: transaction)
        case
                .ready,
                .permanentlyFailed,
                .obsolete,
                .unknown:
            throw JobRecordError.illegalStateTransition
        }
    }

    func saveReadyAsRunning(transaction: SDSAnyWriteTransaction) throws {
        switch status {
        case .ready:
            updateStatus(to: .running, withTransaction: transaction)
        case
                .running,
                .permanentlyFailed,
                .obsolete,
                .unknown:
            throw JobRecordError.illegalStateTransition
        }
    }

    func saveAsPermanentlyFailed(transaction: SDSAnyWriteTransaction) {
        updateStatus(to: .permanentlyFailed, withTransaction: transaction)
    }

    func saveAsObsolete(transaction: SDSAnyWriteTransaction) {
        updateStatus(to: .obsolete, withTransaction: transaction)
    }

    private func updateStatus(to newStatus: Status, withTransaction transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { record in
            record.status = newStatus
        }
    }
}

// MARK: - Failures

extension JobRecord {
    func addFailure(transaction: SDSAnyWriteTransaction) throws {
        switch status {
        case .running:
            anyUpdate(transaction: transaction) { record in
                record.failureCount = min(record.failureCount + 1, UInt.max)
            }
        case
                .ready,
                .permanentlyFailed,
                .obsolete,
                .unknown:
            throw JobRecordError.illegalStateTransition
        }
    }

    public func addFailure(tx: SDSAnyWriteTransaction) {
        anyUpdate(transaction: tx) { record in record.failureCount += 1 }
    }
}
