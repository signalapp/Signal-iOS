//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public enum CloudBackup {}

extension CloudBackup {
    public enum Shims {
        public typealias BlockingManager = _CloudBackup_BlockingManagerShim
        public typealias ProfileManager = _CloudBackup_ProfileManagerShim
        public typealias SignalRecipientFetcher = _CloudBackup_SignalRecipientShim
        public typealias StoryFinder = _CloudBackup_StoryFinderShim
        public typealias TSInteractionFetcher = _CloudBackup_TSInteractionShim
        public typealias TSThreadFetcher = _CloudBackup_TSThreadShim
    }

    public enum Wrappers {
        public typealias BlockingManager = _CloudBackup_BlockingManagerWrapper
        public typealias ProfileManager = _CloudBackup_ProfileManagerWrapper
        public typealias SignalRecipientFetcher = _CloudBackup_SignalRecipientWrapper
        public typealias StoryFinder = _CloudBackup_StoryFinderWrapper
        public typealias TSInteractionFetcher = _CloudBackup_TSInteractionWrapper
        public typealias TSThreadFetcher = _CloudBackup_TSThreadWrapper
    }
}

// MARK: - BlockingManager

public protocol _CloudBackup_BlockingManagerShim {

    func blockedAddresses(tx: DBReadTransaction) -> Set<SignalServiceAddress>

    func addBlockedAddress(_ address: SignalServiceAddress, tx: DBWriteTransaction)
}

public class _CloudBackup_BlockingManagerWrapper: _CloudBackup_BlockingManagerShim {

    private let blockingManager: BlockingManager

    public init(_ blockingManager: BlockingManager) {
        self.blockingManager = blockingManager
    }

    public func blockedAddresses(tx: DBReadTransaction) -> Set<SignalServiceAddress> {
        return blockingManager.blockedAddresses(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func addBlockedAddress(_ address: SignalServiceAddress, tx: DBWriteTransaction) {
        blockingManager.addBlockedAddress(address, blockMode: .localShouldNotLeaveGroups, transaction: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: - ProfileManager

public protocol _CloudBackup_ProfileManagerShim {

    func getUserProfile(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSUserProfile?

    func allWhitelistedRegisteredAddresses(tx: DBReadTransaction) -> [SignalServiceAddress]

    func isThread(inProfileWhitelist thread: TSThread, tx: DBReadTransaction) -> Bool

    func addToWhitelist(_ address: SignalServiceAddress, tx: DBWriteTransaction)

    func addToWhitelist(_ thread: TSGroupThread, tx: DBWriteTransaction)

    func setProfileGivenName(
        givenName: String?,
        familyName: String?,
        profileKey: Data?,
        address: SignalServiceAddress,
        tx: DBWriteTransaction
    )
}

public class _CloudBackup_ProfileManagerWrapper: _CloudBackup_ProfileManagerShim {

    private let profileManager: ProfileManagerProtocol

    public init(_ profileManager: ProfileManagerProtocol) {
        self.profileManager = profileManager
    }

    public func getUserProfile(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSUserProfile? {
        profileManager.getUserProfile(for: address, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func allWhitelistedRegisteredAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] {
        profileManager.allWhitelistedRegisteredAddresses(tx: SDSDB.shimOnlyBridge(tx))
    }

    public func isThread(inProfileWhitelist thread: TSThread, tx: DBReadTransaction) -> Bool {
        profileManager.isThread(inProfileWhitelist: thread, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func addToWhitelist(_ address: SignalServiceAddress, tx: DBWriteTransaction) {
        profileManager.addUser(
            toProfileWhitelist: address,
            userProfileWriter: .storageService, /* TODO */
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func addToWhitelist(_ thread: TSGroupThread, tx: DBWriteTransaction) {
        profileManager.addThread(toProfileWhitelist: thread, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func setProfileGivenName(
        givenName: String?,
        familyName: String?,
        profileKey: Data?,
        address: SignalServiceAddress,
        tx: DBWriteTransaction
    ) {
        profileManager.setProfileGivenName(
            givenName,
            familyName: familyName,
            for: address,
            userProfileWriter: .storageService /* TODO */,
            authedAccount: .implicit(),
            transaction: SDSDB.shimOnlyBridge(tx)
        )
        if let profileKey {
            profileManager.setProfileKeyData(
                profileKey,
                for: address,
                userProfileWriter: .storageService, /* TODO */
                authedAccount: .implicit(),
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        }
    }
}

// MARK: - SignalRecipient

public protocol _CloudBackup_SignalRecipientShim {

    func enumerateAll(tx: DBReadTransaction, block: @escaping (SignalRecipient) -> Void)

    func recipient(for address: SignalServiceAddress, tx: DBReadTransaction) -> SignalRecipient?

    func insert(_ recipient: SignalRecipient, tx: DBWriteTransaction) throws

    func markAsRegisteredAndSave(_ recipient: SignalRecipient, tx: DBWriteTransaction)

    func markAsUnregisteredAndSave(_ recipient: SignalRecipient, at timestamp: UInt64, tx: DBWriteTransaction)
}

public class _CloudBackup_SignalRecipientWrapper: _CloudBackup_SignalRecipientShim {

    public init() {}

    public func enumerateAll(tx: DBReadTransaction, block: @escaping (SignalRecipient) -> Void) {
        SignalRecipient.anyEnumerate(
            transaction: SDSDB.shimOnlyBridge(tx),
            block: { recipient, _ in
                block(recipient)
            }
        )
    }

    public func recipient(for address: SignalServiceAddress, tx: DBReadTransaction) -> SignalRecipient? {
        return SignalRecipientFinder().signalRecipient(for: address, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func insert(_ recipient: SignalRecipient, tx: DBWriteTransaction) throws {
        recipient.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func markAsRegisteredAndSave(_ recipient: SignalRecipient, tx: DBWriteTransaction) {
        recipient.markAsRegisteredAndSave(tx: SDSDB.shimOnlyBridge(tx))
    }

    public func markAsUnregisteredAndSave(_ recipient: SignalRecipient, at timestamp: UInt64, tx: DBWriteTransaction) {
        recipient.markAsUnregisteredAndSave(at: timestamp, tx: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: - StoryFinder

public protocol _CloudBackup_StoryFinderShim {

    func isStoryHidden(forAci aci: Aci, tx: DBReadTransaction) -> Bool?

    func isStoryHidden(forGroupThread groupThread: TSGroupThread, tx: DBReadTransaction) -> Bool?

    func getOrCreateStoryContextAssociatedData(for aci: Aci, tx: DBReadTransaction) -> StoryContextAssociatedData

    func getOrCreateStoryContextAssociatedData(
        forGroupThread groupThread: TSGroupThread,
        tx: DBReadTransaction
    ) -> StoryContextAssociatedData

    func setStoryContextHidden(_ storyContext: StoryContextAssociatedData, tx: DBWriteTransaction)
}

public class _CloudBackup_StoryFinderWrapper: _CloudBackup_StoryFinderShim {

    public init() {}

    public func isStoryHidden(forAci aci: Aci, tx: DBReadTransaction) -> Bool? {
        return StoryFinder.getAssociatedData(forAci: aci, tx: SDSDB.shimOnlyBridge(tx))?.isHidden
    }

    public func isStoryHidden(forGroupThread groupThread: TSGroupThread, tx: DBReadTransaction) -> Bool? {
        return StoryFinder.getAssociatedData(
            forContext: .group(groupId: groupThread.groupId),
            transaction: SDSDB.shimOnlyBridge(tx)
        )?.isHidden
    }

    public func getOrCreateStoryContextAssociatedData(for aci: Aci, tx: DBReadTransaction) -> StoryContextAssociatedData {
        return StoryContextAssociatedData.fetchOrDefault(
            sourceContext: .contact(contactAci: aci),
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func getOrCreateStoryContextAssociatedData(
        forGroupThread groupThread: TSGroupThread,
        tx: DBReadTransaction
    ) -> StoryContextAssociatedData {
        return StoryContextAssociatedData.fetchOrDefault(
            sourceContext: .group(groupId: groupThread.groupId),
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func setStoryContextHidden(_ storyContext: StoryContextAssociatedData, tx: DBWriteTransaction) {
        storyContext.update(
            updateStorageService: false,
            isHidden: true,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}

// MARK: - TSInteraction

public protocol _CloudBackup_TSInteractionShim {

    func enumerateAllInteractions(
        tx: DBReadTransaction,
        block: @escaping (TSInteraction, _ stop: inout Bool) -> Void
    ) throws

    func insert(_ message: TSIncomingMessage, tx: DBWriteTransaction)

    func insertMessageWithBuilder(_ builder: TSOutgoingMessageBuilder, tx: DBWriteTransaction) -> TSOutgoingMessage

    func update(
        _ message: TSOutgoingMessage,
        withRecipient recipient: SignalServiceAddress,
        status: BackupProtoSendStatusStatus,
        timestamp: UInt64,
        wasSentByUD: Bool,
        tx: DBWriteTransaction
    )
}

public class _CloudBackup_TSInteractionWrapper: _CloudBackup_TSInteractionShim {

    public init() {}

    public func enumerateAllInteractions(
        tx: DBReadTransaction,
        block: @escaping (TSInteraction, _ stop: inout Bool) -> Void
    ) throws {
        let cursor = TSInteraction.grdbFetchCursor(
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )

        var stop = false
        while let interaction = try cursor.next() {
            block(interaction, &stop)
            if stop {
                break
            }
        }
    }

    public func insert(_ message: TSIncomingMessage, tx: DBWriteTransaction) {
        message.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func insertMessageWithBuilder(_ builder: TSOutgoingMessageBuilder, tx: DBWriteTransaction) -> TSOutgoingMessage {
        let message = TSOutgoingMessage.init(outgoingMessageWithBuilder: builder, transaction: SDSDB.shimOnlyBridge(tx))
        message.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
        return message
    }

    public func update(
        _ message: TSOutgoingMessage,
        withRecipient address: SignalServiceAddress,
        status: BackupProtoSendStatusStatus,
        timestamp: UInt64,
        wasSentByUD: Bool,
        tx: DBWriteTransaction
    ) {
        let tx = SDSDB.shimOnlyBridge(tx)
        switch status {
        case .failed:
            message.update(
                withFailedRecipient: address,
                // TODO: better errors.
                error: OWSUnretryableMessageSenderError(),
                transaction: tx
            )
        case .pending:
            // Default state
            return
        case .sent:
            message.update(
                withSentRecipientAddress: address,
                wasSentByUD: wasSentByUD,
                transaction: tx
            )
        case .delivered:
            message.update(
                withDeliveredRecipient: address,
                // TODO
                deviceId: 1,
                deliveryTimestamp: timestamp,
                context: PassthroughDeliveryReceiptContext(),
                tx: tx
            )
        case .read:
            message.update(
                withReadRecipient: address,
                // TODO
                deviceId: 1,
                readTimestamp: timestamp,
                tx: tx
            )
        case .viewed:
            message.update(
                withViewedRecipient: address,
                // TODO
                deviceId: 1,
                viewedTimestamp: timestamp,
                tx: tx
            )
        case .skipped:
            message.update(withSkippedRecipient: address, transaction: tx)
        case .unknown:
            return
        }
    }
}

// MARK: - TSThread

public protocol _CloudBackup_TSThreadShim {

    func enumerateAllGroupThreads(tx: DBReadTransaction, block: @escaping (TSGroupThread) -> Void) throws

    func enumerateAll(
        tx: DBReadTransaction,
        block: @escaping (TSThread, UnsafeMutablePointer<ObjCBool>) -> Void
    )

    func fetch(threadUniqueId: String, tx: DBReadTransaction) -> TSThread?

    func fetch(groupId: Data, tx: DBReadTransaction) -> TSGroupThread?

    func fetchOrDefaultThreadAssociatedData(for thread: TSThread, tx: DBReadTransaction) -> ThreadAssociatedData

    func isThreadPinned(_ thread: TSThread) -> Bool

    func updateWithStorySendEnabled(_ storySendEnabled: Bool, groupThread: TSGroupThread, tx: DBWriteTransaction)

    func getOrCreateContactThread(with address: SignalServiceAddress, tx: DBWriteTransaction) -> TSContactThread

    func updateAssociatedData(
        _ threadAssociatedData: ThreadAssociatedData,
        isArchived: Bool?,
        isMarkedUnread: Bool?,
        mutedUntilTimestamp: UInt64?,
        tx: DBWriteTransaction
    )

    func pinThread(_ thread: TSThread, tx: DBWriteTransaction) throws
}

public class _CloudBackup_TSThreadWrapper: _CloudBackup_TSThreadShim {

    public init() {}

    public func enumerateAllGroupThreads(tx: DBReadTransaction, block: @escaping (TSGroupThread) -> Void) throws {
        try ThreadFinder().enumerateGroupThreads(transaction: SDSDB.shimOnlyBridge(tx), block: block)
    }

    public func enumerateAll(
        tx: DBReadTransaction,
        block: @escaping (TSThread, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        TSThread.anyEnumerate(
            transaction: SDSDB.shimOnlyBridge(tx),
            block: { thread, stop in
                block(thread, stop)
            }
        )
    }

    public func fetch(threadUniqueId: String, tx: DBReadTransaction) -> TSThread? {
        return TSThread.anyFetch(uniqueId: threadUniqueId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func fetch(groupId: Data, tx: DBReadTransaction) -> TSGroupThread? {
        return TSGroupThread.fetch(groupId: groupId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func fetchOrDefaultThreadAssociatedData(for thread: TSThread, tx: DBReadTransaction) -> ThreadAssociatedData {
        ThreadAssociatedData.fetchOrDefault(for: thread, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func isThreadPinned(_ thread: TSThread) -> Bool {
        return PinnedThreadManager.isThreadPinned(thread)
    }

    public func updateWithStorySendEnabled(_ storySendEnabled: Bool, groupThread: TSGroupThread, tx: DBWriteTransaction) {
        groupThread.updateWithStorySendEnabled(storySendEnabled, transaction: SDSDB.shimOnlyBridge(tx), updateStorageService: false)
    }

    public func getOrCreateContactThread(with address: SignalServiceAddress, tx: DBWriteTransaction) -> TSContactThread {
        return TSContactThread.getOrCreateThread(withContactAddress: address, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func updateAssociatedData(
        _ threadAssociatedData: ThreadAssociatedData,
        isArchived: Bool?,
        isMarkedUnread: Bool?,
        mutedUntilTimestamp: UInt64?,
        tx: DBWriteTransaction
    ) {
        threadAssociatedData.updateWith(
            isArchived: isArchived,
            isMarkedUnread: isMarkedUnread,
            mutedUntilTimestamp: mutedUntilTimestamp,
            updateStorageService: false,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func pinThread(_ thread: TSThread, tx: DBWriteTransaction) throws {
        try PinnedThreadManager.pinThread(thread, updateStorageService: false, transaction: SDSDB.shimOnlyBridge(tx))
    }
}
