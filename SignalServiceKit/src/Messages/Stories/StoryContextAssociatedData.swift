//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient
import UIKit

/// Contains thread-level information about _incoming_ story messages, grouped
/// by either the contact who sent them (if sent outside a group) or the group id
/// sent to (if sent to a group).
/// Outgoing story threads are not represented, but this table could be extended to include
/// them in the future.
@objc
public final class StoryContextAssociatedData: NSObject, SDSCodableModel {
    public static let databaseTableName = "model_StoryContextAssociatedData"

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case contactUuid
        case groupId
        case isHidden
        case latestUnexpiredTimestamp
        case lastReceivedTimestamp
        case lastReadTimestamp
        case lastViewedTimestamp
    }

    public var id: Int64?
    @objc
    public let uniqueId: String

    public enum SourceContext: Hashable {
        case group(groupId: Data)
        case contact(contactUuid: UUID)
    }

    public var sourceContext: SourceContext {
        if let contactUuid = self.contactUuid {
            return .contact(contactUuid: contactUuid)
        } else if let groupId = self.groupId {
            return .group(groupId: groupId)
        } else {
            owsFail("Invalid StoryContextAssociatedData")
        }
    }

    private let contactUuid: UUID?
    private let groupId: Data?

    public private(set) var isHidden: Bool

    /// Set only for active undeleted incoming stories. If stories expire or are deleted, resets to nil.
    public private(set) var latestUnexpiredTimestamp: UInt64?
    /// Set for all known incoming stories, including those since expired or deleted.
    public private(set) var lastReceivedTimestamp: UInt64? {
        didSet {
            if let oldValue = oldValue, let newValue = lastReceivedTimestamp, newValue > oldValue {
                updateLatestUnexpiredTimestampIfNeeded()
            }
        }
    }

    private func updateLatestUnexpiredTimestampIfNeeded() {
        // We only ever move lastReceivedTimestamp forward for undeleted story messages, so its safe
        // to copy this over to latestUnexpiredTimestamp.
        if
            let lastReceivedTimestamp = lastReceivedTimestamp,
            lastReceivedTimestamp > Date().ows_millisecondsSince1970 - StoryManager.storyLifetimeMillis
        {
            latestUnexpiredTimestamp = lastReceivedTimestamp
        }
    }

    public private(set) var lastReadTimestamp: UInt64?
    public private(set) var lastViewedTimestamp: UInt64? {
        didSet {
            updateLastReadTimestampIfNeeded()
        }
    }

    private func updateLastReadTimestampIfNeeded() {
        guard let newValue = lastViewedTimestamp else {
            return
        }
        guard newValue >= (lastReadTimestamp ??  0) else {
            return
        }
        lastReadTimestamp = newValue
    }

    public var hasUnexpiredStories: Bool {
        return latestUnexpiredTimestamp != nil
    }

    public var hasUnviewedStories: Bool {
        guard let latestUnexpiredTimestamp = latestUnexpiredTimestamp else {
            return false
        }
        guard let lastViewedTimestamp = lastViewedTimestamp else {
            return true
        }
        return lastViewedTimestamp < latestUnexpiredTimestamp
    }

    public init(
        sourceContext: SourceContext,
        isHidden: Bool = false,
        lastReceivedTimestamp: UInt64? = nil,
        lastReadTimestamp: UInt64? = nil,
        lastViewedTimestamp: UInt64? = nil
    ) {
        self.uniqueId = UUID().uuidString
        switch sourceContext {
        case .group(let groupId):
            self.groupId = groupId
            self.contactUuid = nil
        case .contact(let contactUuid):
            self.contactUuid = contactUuid
            self.groupId = nil
        }
        self.isHidden = isHidden
        self.lastReceivedTimestamp = lastReceivedTimestamp
        self.lastReadTimestamp = lastReadTimestamp
        self.lastViewedTimestamp = lastViewedTimestamp

        super.init()

        updateLatestUnexpiredTimestampIfNeeded()
        updateLastReadTimestampIfNeeded()
    }

    /**
     * Creates a new `StoryContextAssociatedData` with the provided parameters or defaults if none exists.
     *
     * If one already exists with the given sourceContext, updates the existing row with any provided fields,
     * leaving them untouched if nil is provided.
     */
    @discardableResult
    public static func createOrUpdate(
        sourceContext: SourceContext,
        isHidden: Bool? = nil,
        lastReceivedTimestamp: UInt64? = nil,
        lastReadTimestamp: UInt64? = nil,
        lastViewedTimestamp: UInt64? = nil,
        transaction: SDSAnyWriteTransaction
    ) -> StoryContextAssociatedData {
        if let existing = StoryFinder.getAssociatedData(forContext: sourceContext, transaction: transaction) {
            // Update the existing entry.
            existing.update(
                isHidden: isHidden,
                lastReceivedTimestamp: lastReceivedTimestamp,
                lastReadTimestamp: lastReadTimestamp,
                lastViewedTimestamp: lastViewedTimestamp,
                transaction: transaction
            )
            return existing
        } else {
            let new = StoryContextAssociatedData(
                sourceContext: sourceContext,
                isHidden: isHidden ?? false,
                lastReceivedTimestamp: lastReceivedTimestamp,
                lastReadTimestamp: lastReadTimestamp,
                lastViewedTimestamp: lastViewedTimestamp
            )
            new.anyInsert(transaction: transaction)
            return new
        }
    }

    public func update(
        updateStorageService: Bool = true,
        isHidden: Bool? = nil,
        lastReceivedTimestamp: UInt64? = nil,
        lastReadTimestamp: UInt64? = nil,
        lastViewedTimestamp: UInt64? = nil,
        transaction: SDSAnyWriteTransaction
    ) {
        let block = { (record: StoryContextAssociatedData) in
            if let isHidden = isHidden {
                record.isHidden = isHidden
            }
            if let lastReceivedTimestamp = lastReceivedTimestamp {
                record.lastReceivedTimestamp = lastReceivedTimestamp
            }
            if let lastReadTimestamp = lastReadTimestamp, lastReadTimestamp > (record.lastReadTimestamp ?? 0) {
                record.lastReadTimestamp = lastReadTimestamp
            }
            if let lastViewedTimestamp = lastViewedTimestamp, lastViewedTimestamp > (record.lastViewedTimestamp ?? 0) {
                record.lastViewedTimestamp = lastViewedTimestamp
            }
        }

        if
            let storedCopy = StoryFinder.getAssociatedData(forContext: sourceContext, transaction: transaction),
            storedCopy != self
        {
            // Update the existing record.
            block(storedCopy)
            do {
                try storedCopy.update(transaction.unwrapGrdbWrite.database)
            } catch {
                owsFailDebug("Unexpectedly failed to update \(error)")
            }
            storedCopy.anyUpdate(transaction: transaction, block: block)
        } else {
            // Insert this new record.
            block(self)
            do {
                try self.insert(transaction.unwrapGrdbWrite.database)
            } catch {
                owsFailDebug("Unexpectedly failed to insert \(error)")
            }
        }

        if updateStorageService {
            switch sourceContext {
            case .group(let groupId):
                guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                    return owsFailDebug("Unexpectedly missing thread for storage service update.")
                }
                storageServiceManager.recordPendingUpdates(groupModel: thread.groupModel)
            case .contact(let contactUuid):
                storageServiceManager.recordPendingUpdates(updatedAddresses: [.init(uuid: contactUuid)])
            }
        }

        if !self.isHidden, isHidden == true, let groupId = self.groupId {
            // When hiding a group, disable sends for the group as well.
            if
                let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction),
                groupThread.storyViewMode != .disabled
            {
                groupThread.updateWithStorySendEnabled(false, transaction: transaction, updateStorageService: updateStorageService)
            }
        }
    }

    public func recomputeLatestUnexpiredTimestamp(transaction: SDSAnyWriteTransaction) {
        var latestUnexpiredTimestamp: UInt64?
        StoryFinder.enumerateStoriesForContext(
            self.sourceContext.asStoryContext,
            transaction: transaction,
            block: { message, _ in
                if message.direction == .incoming, message.timestamp > latestUnexpiredTimestamp ?? 0 {
                    latestUnexpiredTimestamp = message.timestamp
                }
            }
        )

        let block = { (record: StoryContextAssociatedData) in
            record.latestUnexpiredTimestamp = latestUnexpiredTimestamp
        }

        if
            let storedCopy = StoryFinder.getAssociatedData(forContext: sourceContext, transaction: transaction),
            storedCopy != self
        {
            // Update the existing record.
            block(storedCopy)
            do {
                try storedCopy.update(transaction.unwrapGrdbWrite.database)
            } catch {
                owsFailDebug("Unexpectedly failed to update \(error)")
            }
            storedCopy.anyUpdate(transaction: transaction, block: block)
        } else {
            // Insert this new record.
            block(self)
            do {
                try self.insert(transaction.unwrapGrdbWrite.database)
            } catch {
                owsFailDebug("Unexpectedly failed to insert \(error)")
            }
        }

        // NOTE: no need to update storage service for this value, it is used locally only.
    }

    public static func fetchOrDefault(
        sourceContext: SourceContext,
        transaction: SDSAnyReadTransaction
    ) -> StoryContextAssociatedData {
        if let existing = StoryFinder.getAssociatedData(forContext: sourceContext, transaction: transaction) {
            return existing
        }
        return .init(sourceContext: sourceContext)
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(Int.self, forKey: .recordType)
        owsAssertDebug(decodedRecordType == Self.recordType, "Unexpectedly decoded record with wrong type.")

        id = try container.decodeIfPresent(RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)
        contactUuid = try container.decodeIfPresent(UUID.self, forKey: .contactUuid)
        groupId = try container.decodeIfPresent(Data.self, forKey: .groupId)
        isHidden = try container.decode(Bool.self, forKey: .isHidden)
        latestUnexpiredTimestamp = try container.decodeIfPresent(UInt64.self, forKey: .latestUnexpiredTimestamp)
        lastReceivedTimestamp = try container.decodeIfPresent(UInt64.self, forKey: .lastReceivedTimestamp)
        lastReadTimestamp = try container.decodeIfPresent(UInt64.self, forKey: .lastReadTimestamp)
        lastViewedTimestamp = try container.decodeIfPresent(UInt64.self, forKey: .lastViewedTimestamp)

        super.init()

        updateLastReadTimestampIfNeeded()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if let id = id { try container.encode(id, forKey: .id) }
        try container.encode(recordType, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)
        try container.encode(contactUuid, forKey: .contactUuid)
        if let groupId = groupId { try container.encode(groupId, forKey: .groupId) }
        try container.encode(isHidden, forKey: .isHidden)
        try container.encode(latestUnexpiredTimestamp, forKey: .latestUnexpiredTimestamp)
        try container.encode(lastReceivedTimestamp, forKey: .lastReceivedTimestamp)
        try container.encode(lastReadTimestamp, forKey: .lastReadTimestamp)
        try container.encode(lastViewedTimestamp, forKey: .lastViewedTimestamp)
    }
}
