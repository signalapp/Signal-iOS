//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

@objc
public class ThreadAssociatedData: NSObject, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "thread_associated_data"

    public private(set) var id: Int64?

    public let threadUniqueId: String

    @objc
    @DecodableDefault.False public private(set) var isArchived: Bool

    @objc
    @DecodableDefault.False public private(set) var isMarkedUnread: Bool

    @objc
    @DecodableDefault.Zero public private(set) var mutedUntilTimestamp: UInt64

    @objc
    @DecodableDefault.OneFloat public private(set) var audioPlaybackRate: Float

    @objc
    public var isMuted: Bool { mutedUntilTimestamp > Date.ows_millisecondTimestamp() }

    @objc
    public var mutedUntilDate: Date? {
        guard mutedUntilTimestamp > 0 else { return nil }
        return Date(millisecondsSince1970: mutedUntilTimestamp)
    }

    @objc
    public static var alwaysMutedTimestamp: UInt64 { UInt64(LLONG_MAX) }

    @objc(fetchOrDefaultForThread:transaction:)
    public static func fetchOrDefault(
        for thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) -> ThreadAssociatedData {
        fetchOrDefault(for: thread.uniqueId, ignoreMissing: false, transaction: transaction)
    }

    @objc(fetchOrDefaultForThreadUniqueId:transaction:)
    public static func fetchOrDefault(
        for threadUniqueId: String,
        transaction: SDSAnyReadTransaction
    ) -> ThreadAssociatedData {
        fetchOrDefault(for: threadUniqueId, ignoreMissing: false, transaction: transaction)
    }

    @objc(fetchOrDefaultForThread:ignoreMissing:transaction:)
    public static func fetchOrDefault(
        for thread: TSThread,
        ignoreMissing: Bool,
        transaction: SDSAnyReadTransaction
    ) -> ThreadAssociatedData {
        fetchOrDefault(for: thread.uniqueId, ignoreMissing: ignoreMissing, transaction: transaction)
    }

    @objc(fetchOrDefaultForThreadUniqueId:ignoreMissing:transaction:)
    public static func fetchOrDefault(
        for threadUniqueId: String,
        ignoreMissing: Bool,
        transaction: SDSAnyReadTransaction
    ) -> ThreadAssociatedData {
        guard let associatedData = fetch(for: threadUniqueId, transaction: transaction) else {
            if !ignoreMissing, !CurrentAppContext().isRunningTests, threadUniqueId != "MockThread" {
                owsFailDebug("Unexpectedly missing associated data for thread")
            }
            return .init(threadUniqueId: threadUniqueId)
        }

        return associatedData
    }

    @objc(fetchForThreadUniqueId:transaction:)
    public static func fetch(
        for threadUniqueId: String,
        transaction: SDSAnyReadTransaction
    ) -> ThreadAssociatedData? {
        do {
            return try Self.filter(Column("threadUniqueId") == threadUniqueId).fetchOne(transaction.unwrapGrdbRead.database)
        } catch {
            owsFailDebug("Failed to read associated data \(error)")
            return nil
        }
    }

    @objc(removeForThreadUniqueId:transaction:)
    public static func remove(for threadUniqueId: String, transaction: SDSAnyWriteTransaction) {
        do {
            try Self.filter(Column("threadUniqueId") == threadUniqueId).deleteAll(transaction.unwrapGrdbWrite.database)
        } catch {
            owsFailDebug("Failed to remove associated data \(error)")
        }
    }

    @objc(createIfMissingForThreadUniqueId:transaction:)
    public static func createIfMissing(for threadUniqueId: String, transaction: SDSAnyWriteTransaction) {
        guard fetch(for: threadUniqueId, transaction: transaction) == nil else {
            return Logger.warn("Unexpectedly tried to create for a thread that already exists.")
        }

        do {
            try ThreadAssociatedData(threadUniqueId: threadUniqueId).insert(transaction.unwrapGrdbWrite.database)
        } catch {
            owsFailDebug("Unexpectedly failed to insert \(error)")
        }
    }

    private init(threadUniqueId: String) {
        self.threadUniqueId = threadUniqueId
        super.init()
    }

    public func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }

    @objc
    public init(
        threadUniqueId: String,
        isArchived: Bool,
        isMarkedUnread: Bool,
        mutedUntilTimestamp: UInt64,
        audioPlaybackRate: Float
    ) {
        self.threadUniqueId = threadUniqueId
        self.isArchived = isArchived
        self.isMarkedUnread = isMarkedUnread
        self.mutedUntilTimestamp = mutedUntilTimestamp
        self.audioPlaybackRate = audioPlaybackRate
        super.init()
    }

    public func updateWith(
        isArchived: Bool? = nil,
        isMarkedUnread: Bool? = nil,
        mutedUntilTimestamp: UInt64? = nil,
        audioPlaybackRate: Float? = nil,
        updateStorageService: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        guard
            isArchived != nil
            || isMarkedUnread != nil
            || mutedUntilTimestamp != nil
            || audioPlaybackRate != nil
        else {
            return owsFailDebug("You must set one value")
        }

        var isMarkedUnread = isMarkedUnread

        // If we're archiving and we have an existing thread record,
        // also mark that thread record as read.
        if isArchived == true {
            // Also clear marked unread if we're not explicitly setting it.
            if isMarkedUnread == nil { isMarkedUnread = false }
            markThreadAsReadIfExists(transaction: transaction)
        }

        updateWith(updateStorageService: updateStorageService, transaction: transaction) { associatedData in
            if let isArchived = isArchived {
                associatedData.isArchived = isArchived
            }
            if let isMarkedUnread = isMarkedUnread {
                associatedData.isMarkedUnread = isMarkedUnread
            }
            if let mutedUntilTimestamp = mutedUntilTimestamp {
                associatedData.mutedUntilTimestamp = mutedUntilTimestamp
            }
            if let audioPlaybackRate = audioPlaybackRate {
                associatedData.audioPlaybackRate = audioPlaybackRate
            }
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func updateWith(isArchived: Bool, updateStorageService: Bool, transaction: SDSAnyWriteTransaction) {
        updateWith(isArchived: isArchived, updateStorageService: updateStorageService, transaction: transaction)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func updateWith(isMarkedUnread: Bool, updateStorageService: Bool, transaction: SDSAnyWriteTransaction) {
        updateWith(isMarkedUnread: isMarkedUnread, updateStorageService: updateStorageService, transaction: transaction)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func updateWith(mutedUntilTimestamp: UInt64, updateStorageService: Bool, transaction: SDSAnyWriteTransaction) {
        updateWith(updateStorageService: updateStorageService, transaction: transaction) { $0.mutedUntilTimestamp = mutedUntilTimestamp }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func updateWith(audioPlaybackRate: Float, updateStorageService: Bool, transaction: SDSAnyWriteTransaction) {
        updateWith(updateStorageService: updateStorageService, transaction: transaction) { $0.audioPlaybackRate = audioPlaybackRate }
    }

    @objc(clearIsArchived:clearIsMarkedUnread:updateStorageService:transaction:)
    public func clear(isArchived clearIsArchived: Bool = false, isMarkedUnread clearIsMarkedUnread: Bool = false, updateStorageService: Bool, transaction: SDSAnyWriteTransaction) {
        guard clearIsArchived || clearIsMarkedUnread else { return }
        updateWith(updateStorageService: updateStorageService, transaction: transaction) { associatedData in
            if clearIsArchived { associatedData.isArchived = false }
            if clearIsMarkedUnread { associatedData.isMarkedUnread = false }
        }
    }

    private func updateWith(updateStorageService: Bool, transaction: SDSAnyWriteTransaction, block: (ThreadAssociatedData) -> Void) {
        block(self)

        if let storedCopy = Self.fetch(for: threadUniqueId, transaction: transaction), storedCopy !== self {
            block(storedCopy)

            do {
                try storedCopy.update(transaction.unwrapGrdbWrite.database)
            } catch {
                owsFailDebug("Unexpectedly failed to update \(error)")
            }
        } else {
            do {
                owsFailDebug("Could not update missing record.")
                try insert(transaction.unwrapGrdbWrite.database)
            } catch {
                owsFailDebug("Unexpectedly failed to insert \(error)")
            }
        }

        // If the thread model exists, make sure the UI is notified that it has changed.
        if let thread = TSThread.anyFetch(uniqueId: threadUniqueId, transaction: transaction) {
            Self.databaseStorage.touch(thread: thread, shouldReindex: false, transaction: transaction)
        }

        if updateStorageService {
            guard let thread = TSThread.anyFetch(uniqueId: threadUniqueId, transaction: transaction) else {
                return owsFailDebug("Unexpectedly missing thread for storage service update.")
            }

            if let groupThread = thread as? TSGroupThread {
                storageServiceManager.recordPendingUpdates(groupModel: groupThread.groupModel)
            } else if let contactThread = thread as? TSContactThread {
                storageServiceManager.recordPendingUpdates(updatedAddresses: [contactThread.contactAddress])
            } else {
                owsFailDebug("Unexpected thread type")
            }
        }
    }

    fileprivate func markThreadAsReadIfExists(transaction: SDSAnyWriteTransaction) {
        guard let thread = TSThread.anyFetch(uniqueId: threadUniqueId, transaction: transaction) else { return }
        thread.markAllAsRead(transaction: transaction)
    }
}

public extension TSThread {
    @objc(markAllAsReadAndUpdateStorageService:transaction:)
    func markAllAsRead(updateStorageService: Bool, transaction: SDSAnyWriteTransaction) {
        markAllAsRead(transaction: transaction)

        let associatedData = ThreadAssociatedData.fetchOrDefault(for: self, transaction: transaction)
        associatedData.updateWith(isMarkedUnread: false, updateStorageService: updateStorageService, transaction: transaction)
    }

    fileprivate func markAllAsRead(transaction: SDSAnyWriteTransaction) {
        let hasPendingMessageRequest = hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead)
        let circumstance: OWSReceiptCircumstance = hasPendingMessageRequest
            ? .onThisDeviceWhilePendingMessageRequest
            : .onThisDevice

        let finder = InteractionFinder(threadUniqueId: uniqueId)
        var cursor = finder.fetchAllUnreadMessages(transaction: transaction.unwrapGrdbRead)
        do {
            while let message = try cursor.next() {
                message.markAsRead(
                    atTimestamp: Date.ows_millisecondTimestamp(),
                    thread: self,
                    circumstance: circumstance,
                    shouldClearNotifications: true,
                    transaction: transaction
                )
            }
        } catch {
            owsFailDebug("unexpected failure fetching unread messages: \(error)")
        }

        // Just to be defensive, we'll also check for unread messages.
        owsAssertDebug(finder.unreadCount(transaction: transaction.unwrapGrdbRead) == 0)
    }
}
