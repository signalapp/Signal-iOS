//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Notification.Name {
    static let IncomingContactSyncDidComplete = Notification.Name("IncomingContactSyncDidComplete")
}

@objc(OWSIncomingContactSyncJobQueue)
public class IncomingContactSyncJobQueue: NSObject, JobQueue {

    public typealias DurableOperationType = IncomingContactSyncOperation
    public let requiresInternet: Bool = true
    public let isEnabled: Bool = true
    public static let maxRetries: UInt = 4
    @objc
    public static let jobRecordLabel: String = OWSIncomingContactSyncJobRecord.defaultLabel
    public var jobRecordLabel: String {
        return type(of: self).jobRecordLabel
    }

    public var runningOperations = AtomicArray<IncomingContactSyncOperation>()
    public var isSetup = AtomicBool(false)

    @objc
    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.setup()
        }
    }

    public func setup() {
        defaultSetup()
    }

    public func didMarkAsReady(oldJobRecord: OWSIncomingContactSyncJobRecord, transaction: SDSAnyWriteTransaction) {
        // no special handling
    }

    let defaultQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "IncomingContactSyncJobQueue"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    public func operationQueue(jobRecord: OWSIncomingContactSyncJobRecord) -> OperationQueue {
        return defaultQueue
    }

    public func buildOperation(jobRecord: OWSIncomingContactSyncJobRecord, transaction: SDSAnyReadTransaction) throws -> IncomingContactSyncOperation {
        return IncomingContactSyncOperation(jobRecord: jobRecord)
    }

    @objc
    public func add(attachmentId: String, isComplete: Bool, transaction: SDSAnyWriteTransaction) {
        let jobRecord = OWSIncomingContactSyncJobRecord(
            attachmentId: attachmentId,
            isComplete: isComplete,
            label: self.jobRecordLabel
        )
        self.add(jobRecord: jobRecord, transaction: transaction)
    }
}

public class IncomingContactSyncOperation: OWSOperation, DurableOperation {
    public typealias JobRecordType = OWSIncomingContactSyncJobRecord
    public typealias DurableOperationDelegateType = IncomingContactSyncJobQueue
    public weak var durableOperationDelegate: IncomingContactSyncJobQueue?
    public var jobRecord: OWSIncomingContactSyncJobRecord
    public var operation: OWSOperation {
        return self
    }

    public var newThreads: [(threadId: String, sortOrder: UInt32)] = []

    // MARK: -

    init(jobRecord: OWSIncomingContactSyncJobRecord) {
        self.jobRecord = jobRecord
    }

    // MARK: - Durable Operation Overrides

    enum IncomingContactSyncError: Error {
        case malformed(_ description: String)
    }

    public override func run() {
        firstly { () -> Promise<TSAttachmentStream> in
            try self.getAttachmentStream()
        }.done(on: DispatchQueue.global()) { attachmentStream in
            self.newThreads = []
            try Bench(title: "processing incoming contact sync file") {
                try self.process(attachmentStream: attachmentStream)
            }
            self.databaseStorage.write { transaction in
                guard let attachmentStream = TSAttachmentStream.anyFetch(uniqueId: self.jobRecord.attachmentId, transaction: transaction) else {
                    owsFailDebug("attachmentStream was unexpectedly nil")
                    return
                }
                attachmentStream.anyRemove(transaction: transaction)
            }
            self.reportSuccess()
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    public override func didSucceed() {
        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: transaction)
        }
        // add user info for thread ordering
        NotificationCenter.default.post(name: .IncomingContactSyncDidComplete, object: self)
    }

    public override func didReportError(_ error: Error) {
        Logger.debug("remainingRetries: \(self.remainingRetries)")

        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didReportError: error, transaction: transaction)
        }
    }

    public override func didFail(error: Error) {
        Logger.error("failed with error: \(error)")

        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction)
        }
    }

    // MARK: - Private

    private func getAttachmentStream() throws -> Promise<TSAttachmentStream> {
        Logger.debug("attachmentId: \(jobRecord.attachmentId)")

        guard let attachment = (databaseStorage.read { transaction in
            return TSAttachment.anyFetch(uniqueId: self.jobRecord.attachmentId, transaction: transaction)
        }) else {
            throw OWSAssertionError("missing attachment")
        }

        switch attachment {
        case let attachmentPointer as TSAttachmentPointer:
            return self.attachmentDownloads.enqueueHeadlessDownloadPromise(attachmentPointer: attachmentPointer)
        case let attachmentStream as TSAttachmentStream:
            return Promise.value(attachmentStream)
        default:
            throw OWSAssertionError("unexpected attachment type: \(attachment)")
        }
    }

    private func process(attachmentStream: TSAttachmentStream) throws {
        guard let fileUrl = attachmentStream.originalMediaURL else {
            throw OWSAssertionError("fileUrl was unexpectedly nil")
        }
        try Data(contentsOf: fileUrl, options: .mappedIfSafe).withUnsafeBytes { bufferPtr in
            if let baseAddress = bufferPtr.baseAddress, bufferPtr.count > 0 {
                let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                let inputStream = ChunkedInputStream(forReadingFrom: pointer, count: bufferPtr.count)
                let contactStream = ContactsInputStream(inputStream: inputStream)

                // We use batching to avoid long-running write transactions
                // and to place an upper bound on memory usage.
                var allSignalServiceAddresses = [SignalServiceAddress]()
                while try processBatch(contactStream: contactStream, processedAddresses: &allSignalServiceAddresses) {}

                if jobRecord.isCompleteContactSync {
                    pruneContacts(exceptThoseReceivedFromCompleteSync: allSignalServiceAddresses)
                }

                databaseStorage.write { transaction in
                    // Always fire just one identity change notification, rather than potentially
                    // once per contact. It's possible that *no* identities actually changed,
                    // but we have no convenient way to track that.
                    self.identityManager.fireIdentityStateChangeNotification(after: transaction)
                }
            }
        }
    }

    // Returns false when there are no more contacts to process.
    private func processBatch(contactStream: ContactsInputStream, processedAddresses: inout [SignalServiceAddress]) throws -> Bool {
        try autoreleasepool {
            // We use batching to avoid long-running write transactions.
            guard let contacts = try Self.buildBatch(contactStream: contactStream) else {
                return false
            }
            guard !contacts.isEmpty else {
                owsFailDebug("Empty batch.")
                return false
            }
            try databaseStorage.write { transaction in
                for contact in contacts {
                    try self.process(contactDetails: contact, transaction: transaction)
                    processedAddresses.append(contact.address)
                }
            }
            return true
        }
    }

    private static func buildBatch(contactStream: ContactsInputStream) throws -> [ContactDetails]? {
        let batchSize = 8
        var contacts = [ContactDetails]()
        while contacts.count < batchSize,
              let contact = try contactStream.decodeContact() {
            contacts.append(contact)
        }
        guard !contacts.isEmpty else {
            return nil
        }
        return contacts
    }

    private func process(contactDetails: ContactDetails, transaction: SDSAnyWriteTransaction) throws {
        Logger.debug("contactDetails: \(contactDetails)")

        let recipient = SignalRecipient.fetchOrCreate(for: contactDetails.address, trustLevel: .high, transaction: transaction)

        // Mark as registered as long as we have a UUID. If we don't have a UUID,
        // contacts can't be registered.
        if recipient.recipientUUID != nil {
            recipient.markAsRegistered(transaction: transaction)
        }

        let contactThread: TSContactThread
        let isNewThread: Bool
        if let existingThread = TSContactThread.getWithContactAddress(contactDetails.address, transaction: transaction) {
            contactThread = existingThread
            isNewThread = false
        } else {
            let newThread = TSContactThread(contactAddress: contactDetails.address)
            newThread.shouldThreadBeVisible = true

            contactThread = newThread
            isNewThread = true
        }

        if isNewThread {
            contactThread.anyInsert(transaction: transaction)
            let inboxSortOrder = contactDetails.inboxSortOrder ?? UInt32.max
            newThreads.append((threadId: contactThread.uniqueId, sortOrder: inboxSortOrder))
            if let isArchived = contactDetails.isArchived, isArchived == true {
                let associatedData = ThreadAssociatedData.fetchOrDefault(for: contactThread, transaction: transaction)
                associatedData.updateWith(isArchived: true, updateStorageService: false, transaction: transaction)
            }
        }

        let disappearingMessageToken = DisappearingMessageToken.token(forProtoExpireTimer: contactDetails.expireTimer)
        GroupManager.remoteUpdateDisappearingMessages(withContactOrV1GroupThread: contactThread,
                                                      disappearingMessageToken: disappearingMessageToken,
                                                      groupUpdateSourceAddress: nil,
                                                      transaction: transaction)

        if let verifiedProto = contactDetails.verifiedProto {
            try self.identityManager.processIncomingVerifiedProto(verifiedProto,
                                                                  transaction: transaction)
        }

        if let profileKey = contactDetails.profileKey {
            self.profileManager.setProfileKeyData(profileKey,
                                                  for: contactDetails.address,
                                                  userProfileWriter: .syncMessage,
                                                  transaction: transaction)
        }

        if contactDetails.isBlocked {
            if !self.blockingManager.isAddressBlocked(contactDetails.address, transaction: transaction) {
                self.blockingManager.addBlockedAddress(contactDetails.address,
                                                       blockMode: .remote,
                                                       transaction: transaction)
            }
        } else {
            if self.blockingManager.isAddressBlocked(contactDetails.address, transaction: transaction) {
                self.blockingManager.removeBlockedAddress(contactDetails.address,
                                                          wasLocallyInitiated: false,
                                                          transaction: transaction)
            }
        }
    }

    /// Clear ``SignalAccount``s that weren't part of a complete sync.
    ///
    /// Although "system contact" details (represented by a ``SignalAccount``)
    /// are synced via StorageService rather than contact sync messages, any
    /// contacts not included in a complete contact sync are not present on the
    /// primary device and should there be removed from this linked device.
    ///
    /// In theory, StorageService updates should handle removing these contacts.
    /// However, there's no periodic sync check our state against
    /// StorageService, so this job continues to fulfill that role. In the
    /// future, if you're removing this method, you should first ensure that
    /// periodic full syncs of contact details happen with StorageService.
    private func pruneContacts(exceptThoseReceivedFromCompleteSync addresses: [SignalServiceAddress]) {
        // Every contact sync includes your own address. However, we shouldn't
        // create a SignalAccount for your own address. (If you're a primary, this
        // is handled by ContactsMaps.phoneNumbers(…).)
        let addressesToIgnore = [TSAccountManager.localAddress].compacted()

        let setOfAddresses = Set(addresses).subtracting(addressesToIgnore)
        self.databaseStorage.write { transaction in
            // Rather than collecting SignalAccount objects, collect their unique IDs.
            // This operation can run in the memory-constrainted NSE, so trade off a
            // bit of speed to save memory.
            var uniqueIdsToRemove = [String]()
            SignalAccount.anyEnumerate(transaction: transaction, batchSize: 8) { signalAccount, _ in
                guard !setOfAddresses.contains(signalAccount.recipientAddress) else {
                    // This contact was received in this batch, so don't remove it.
                    return
                }
                uniqueIdsToRemove.append(signalAccount.uniqueId)
            }
            Logger.info("Removing \(uniqueIdsToRemove.count) contacts during contact sync")
            for uniqueId in uniqueIdsToRemove {
                autoreleasepool {
                    guard let signalAccount = SignalAccount.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
                        return
                    }
                    signalAccount.anyRemove(transaction: transaction)
                }
            }
            if !uniqueIdsToRemove.isEmpty {
                contactsManagerImpl.didUpdateSignalAccounts(transaction: transaction)
            }
        }
    }
}
