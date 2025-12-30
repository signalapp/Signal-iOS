//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc
class MessageReceiptSet: NSObject, Codable {
    @objc
    private(set) var timestamps: Set<UInt64>
    @objc
    private(set) var uniqueIds: Set<String>

    override convenience init() {
        self.init(timestamps: Set(), uniqueIds: Set())
    }

    fileprivate init(timestamps: Set<UInt64>, uniqueIds: Set<String>) {
        self.timestamps = timestamps
        self.uniqueIds = uniqueIds
    }

    func insert(timestamp: UInt64, messageUniqueId: String? = nil) {
        timestamps.insert(timestamp)
        if let uniqueId = messageUniqueId {
            uniqueIds.insert(uniqueId)
        }
    }

    func union(_ other: MessageReceiptSet) {
        timestamps.formUnion(other.timestamps)
        uniqueIds.formUnion(other.uniqueIds)
    }

    func subtract(_ other: MessageReceiptSet) {
        timestamps.subtract(other.timestamps)
        uniqueIds.subtract(other.uniqueIds)
    }

    fileprivate func union(timestampSet: some Sequence<UInt64>) {
        timestamps.formUnion(timestampSet)
    }
}

// MARK: - ReceiptSender

@objc
public class ReceiptSender: NSObject {
    private let recipientDatabaseTable: RecipientDatabaseTable

    private let deliveryReceiptStore: KeyValueStore
    private let readReceiptStore: KeyValueStore
    private let viewedReceiptStore: KeyValueStore

    private var observers = [NSObjectProtocol]()
    private let pendingTasks = PendingTasks()
    private let sendingState: AtomicValue<SendingState>

    public init(appReadiness: AppReadiness, recipientDatabaseTable: RecipientDatabaseTable) {
        self.recipientDatabaseTable = recipientDatabaseTable
        self.deliveryReceiptStore = KeyValueStore(collection: "kOutgoingDeliveryReceiptManagerCollection")
        self.readReceiptStore = KeyValueStore(collection: "kOutgoingReadReceiptManagerCollection")
        self.viewedReceiptStore = KeyValueStore(collection: "kOutgoingViewedReceiptManagerCollection")

        self.sendingState = AtomicValue(SendingState(), lock: .init())

        super.init()
        SwiftSingletons.register(self)

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.sendPendingReceiptsIfNeeded()

            self.observers.append(NotificationCenter.default.addObserver(
                forName: .identityStateDidChange,
                object: self,
                queue: nil,
                using: { [weak self] _ in self?.sendPendingReceiptsIfNeeded() },
            ))
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Enqueuing

    func enqueueDeliveryReceipt(
        for decryptedEnvelope: DecryptedIncomingEnvelope,
        messageUniqueId: String?,
        tx: DBWriteTransaction,
    ) {
        enqueueReceipt(
            for: decryptedEnvelope.sourceAci,
            timestamp: decryptedEnvelope.timestamp,
            messageUniqueId: messageUniqueId,
            receiptType: .delivery,
            tx: tx,
        )
    }

    func enqueueReadReceipt(
        for aci: Aci,
        timestamp: UInt64,
        messageUniqueId: String?,
        tx: DBWriteTransaction,
    ) {
        enqueueReceipt(
            for: aci,
            timestamp: timestamp,
            messageUniqueId: messageUniqueId,
            receiptType: .read,
            tx: tx,
        )
    }

    func enqueueViewedReceipt(
        for aci: Aci,
        timestamp: UInt64,
        messageUniqueId: String?,
        tx: DBWriteTransaction,
    ) {
        enqueueReceipt(
            for: aci,
            timestamp: timestamp,
            messageUniqueId: messageUniqueId,
            receiptType: .viewed,
            tx: tx,
        )
    }

    private func enqueueReceipt(
        for aci: Aci,
        timestamp: UInt64,
        messageUniqueId: String?,
        receiptType: ReceiptType,
        tx: DBWriteTransaction,
    ) {
        guard timestamp >= 1 else {
            owsFailDebug("Invalid timestamp.")
            return
        }
        let pendingTask = pendingTasks.buildPendingTask()
        let persistedSet = fetchReceiptSet(receiptType: receiptType, aci: aci, tx: tx)
        persistedSet.insert(timestamp: timestamp, messageUniqueId: messageUniqueId)
        storeReceiptSet(persistedSet, receiptType: receiptType, aci: aci, tx: tx)
        tx.addSyncCompletion {
            self.sendingState.update {
                $0.mightHavePendingReceipts = true
                $0.pendingTasks.append(pendingTask)
            }
            self.sendPendingReceiptsIfNeeded()
        }
    }

    // MARK: - Processing

    struct SendingState {
        /// Whether or not we're currently sending some receipts.
        var inProgress = false

        /// Whether or not there might be more receipts that need to be sent. The
        /// default value is true because there might be receipts that need to be
        /// sent when the app launches.
        var mightHavePendingReceipts = true

        var pendingTasks = [PendingTask]()

        mutating func startIfPossible() -> Bool {
            guard mightHavePendingReceipts, !inProgress else {
                return false
            }
            mightHavePendingReceipts = false
            inProgress = true
            return true
        }
    }

    /// Schedules a processing pass, unless one is already scheduled.
    func sendPendingReceiptsIfNeeded() {
        Task { await self._sendPendingReceiptsIfNeeded() }
    }

    private func _sendPendingReceiptsIfNeeded() async {
        do {
            guard sendingState.update(block: { $0.startIfPossible() }) else {
                return
            }
            let pendingTasks = sendingState.update(block: {
                let result = $0.pendingTasks
                $0.pendingTasks = []
                return result
            })
            defer {
                pendingTasks.forEach { $0.complete() }
            }
            await sendPendingReceipts()
        }

        // Wait N seconds before conducting another pass. This allows time for a
        // batch to accumulate.
        //
        // We want a value high enough to allow us to effectively de-duplicate
        // receipts without being so high that the user notices.
        try? await Task.sleep(nanoseconds: 3 * NSEC_PER_SEC)
        sendingState.update(block: { $0.inProgress = false })
        await _sendPendingReceiptsIfNeeded()
    }

    private func sendPendingReceipts() async {
        return await withTaskGroup(of: Void.self) { taskGroup in
            for receiptType in ReceiptType.allCases {
                taskGroup.addTask { await self.sendReceipts(receiptType: receiptType) }
            }
            await taskGroup.waitForAll()
        }
    }

    private func sendReceipts(receiptType: ReceiptType) async {
        let pendingReceipts = SSKEnvironment.shared.databaseStorageRef.read { tx in fetchAllReceiptSets(receiptType: receiptType, tx: tx) }
        await withTaskGroup(of: Void.self) { taskGroup in
            for (aci, receiptBatches) in pendingReceipts {
                for receiptBatch in receiptBatches {
                    taskGroup.addTask {
                        try? await self.sendReceipts(receiptType: receiptType, to: aci, receiptBatch: receiptBatch)
                    }
                }
            }
            await taskGroup.waitForAll()
        }
    }

    private func sendReceipts(
        receiptType: ReceiptType,
        to aci: Aci?,
        receiptBatch: ReceiptBatch,
    ) async throws {
        var remainingTimestamps = receiptBatch.receiptSet.timestamps.sorted()[...]
        repeat {
            let sendResult = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx -> (sendPromise: Promise<Void>, batchEndIndex: Int)? in
                // If any of the following checks fail, we throw away ALL of the pending
                // receipts, so there's no reason to batch them. (It's actually more costly
                // if we batch the removals.) A "sendPromise" that always succeeds and
                // covers all of the "remainingTimestamps" simulates a successful send,
                // causing them to be dequeued.

                if remainingTimestamps.isEmpty {
                    Logger.warn("Dropping receipts without any timestamps")
                    return (.value(()), remainingTimestamps.endIndex)
                }

                guard let aci else {
                    Logger.warn("Dropping receipts without an ACI")
                    return (.value(()), remainingTimestamps.endIndex)
                }

                if SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(SignalServiceAddress(aci), transaction: tx) {
                    Logger.warn("Dropping receipts for blocked \(aci)")
                    return (.value(()), remainingTimestamps.endIndex)
                }

                let recipientHidingManager = DependenciesBridge.shared.recipientHidingManager
                if recipientHidingManager.isHiddenAddress(SignalServiceAddress(aci), tx: tx) {
                    Logger.warn("Dropping receipts for hidden \(aci)")
                    return (.value(()), remainingTimestamps.endIndex)
                }

                // We skip any sends to untrusted identities since we know they'll fail
                // anyway. If an identity state changes we should recheck our
                // pendingReceipts to re-attempt a send to formerly untrusted recipients.
                let identityManager = DependenciesBridge.shared.identityManager
                guard identityManager.untrustedIdentityForSending(to: SignalServiceAddress(aci), untrustedThreshold: nil, tx: tx) == nil else {
                    Logger.warn("Deferring receipts for untrusted \(aci)")
                    return nil
                }

                let batchLimit = 4096
                let batchTimestamps = remainingTimestamps.prefix(batchLimit)
                let batchEndIndex = batchTimestamps.endIndex

                // Even if we're sending a partial batch, we still include all of the
                // uniqueIds. We don't know which ones correspond to the timestamps in this
                // receipt message, so we include all of them to err on the safe side.
                let batchToSend = MessageReceiptSet(
                    timestamps: Set(batchTimestamps),
                    uniqueIds: receiptBatch.receiptSet.uniqueIds,
                )

                let thread = TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(aci), transaction: tx)
                let message: OWSReceiptsForSenderMessage
                switch receiptType {
                case .delivery:
                    message = .deliveryReceiptsForSenderMessage(with: thread, receiptSet: batchToSend, transaction: tx)
                case .read:
                    message = .readReceiptsForSenderMessage(with: thread, receiptSet: batchToSend, transaction: tx)
                case .viewed:
                    message = .viewedReceiptsForSenderMessage(with: thread, receiptSet: batchToSend, transaction: tx)
                }

                let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueueRef
                let preparedMessage = PreparedOutgoingMessage.preprepared(
                    transientMessageWithoutAttachments: message,
                )
                let sendPromise = messageSenderJobQueue.add(
                    .promise,
                    message: preparedMessage,
                    limitToCurrentProcessLifetime: true,
                    transaction: tx,
                )
                return (sendPromise, batchEndIndex)
            }

            guard let sendResult else {
                // We deferred sending the receipts, so exit the batching loop.
                return
            }

            let sentTimestamps = remainingTimestamps[..<sendResult.batchEndIndex]
            remainingTimestamps = remainingTimestamps[sendResult.batchEndIndex...]

            do {
                try await sendResult.sendPromise.awaitable()

                let uniqueIdsToDequeue: Set<String>
                if remainingTimestamps.isEmpty {
                    uniqueIdsToDequeue = receiptBatch.receiptSet.uniqueIds
                } else {
                    // If we only sent a partial batch, we don't know which timestamps
                    // correspond to which uniqueIds. So we just err on the safe side and keep
                    // around all of the uniqueIds.
                    uniqueIdsToDequeue = []
                }

                let batchToDequeue = ReceiptBatch(
                    receiptSet: MessageReceiptSet(timestamps: Set(sentTimestamps), uniqueIds: uniqueIdsToDequeue),
                    identifier: receiptBatch.identifier,
                )
                await self.dequeueReceipts(for: batchToDequeue, receiptType: receiptType)
            } catch let error as MessageSenderNoSuchSignalRecipientError {
                // If we try to send a subset of the receipts and the recipient doesn't
                // exist, the remaining receipts will also fail. Dequeue all of them to
                // avoid pointless retries.
                await self.dequeueReceipts(for: receiptBatch, receiptType: receiptType)
                throw error
            }
        } while !remainingTimestamps.isEmpty
    }

    // MARK: - Fetching & Saving

    enum ReceiptType: CaseIterable {
        case delivery
        case read
        case viewed
    }

    private func dequeueReceipts(for receiptBatch: ReceiptBatch, receiptType: ReceiptType) async {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            let persistedSet = self._fetchReceiptSet(receiptType: receiptType, identifier: receiptBatch.identifier, tx: tx)
            persistedSet.subtract(receiptBatch.receiptSet)
            self._storeReceiptSet(persistedSet, receiptType: receiptType, identifier: receiptBatch.identifier, tx: tx)
        }
    }

    struct ReceiptBatch {
        var receiptSet: MessageReceiptSet
        var identifier: String
    }

    func fetchAllReceiptSets(receiptType: ReceiptType, tx: DBReadTransaction) -> [Aci?: [ReceiptBatch]] {
        // If we find identifiers in the database that are malformed, we stuff them
        // into the `nil` ACI case. The sendReceipts method will turn this into a
        // no-op an then prune those identifiers from the database.
        var results = [Aci?: [ReceiptBatch]]()
        for identifier in keyValueStore(for: receiptType).allKeys(transaction: tx) {
            let recipientAci = fetchRecipientAci(for: identifier, tx: tx)
            let receiptSet = _fetchReceiptSet(receiptType: receiptType, identifier: identifier, tx: tx)
            results[recipientAci, default: []].append(ReceiptBatch(receiptSet: receiptSet, identifier: identifier))
        }
        return results
    }

    private func fetchRecipientAci(for identifier: String, tx: DBReadTransaction) -> Aci? {
        if let aci = Aci.parseFrom(aciString: identifier) {
            return aci
        }
        if let phoneNumber = E164(identifier) {
            return recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: tx)?.aci
        }
        return nil
    }

    private func fetchReceiptSet(receiptType: ReceiptType, aci: Aci, tx: DBReadTransaction) -> MessageReceiptSet {
        return _fetchReceiptSet(receiptType: receiptType, identifier: aci.serviceIdUppercaseString, tx: tx)
    }

    private func _fetchReceiptSet(
        receiptType: ReceiptType,
        identifier: String,
        tx: DBReadTransaction,
    ) -> MessageReceiptSet {
        let store = keyValueStore(for: receiptType)
        let result = MessageReceiptSet()
        if let receiptSet: MessageReceiptSet = try? store.getCodableValue(forKey: identifier, transaction: tx) {
            result.union(receiptSet)
        } else if let numberSet = store.getSet(identifier, ofClass: NSNumber.self, transaction: tx)?.map({ $0.uint64Value }) {
            result.union(timestampSet: numberSet)
        }
        return result
    }

    func storeReceiptSet(_ receiptSet: MessageReceiptSet, receiptType: ReceiptType, aci: Aci, tx: DBWriteTransaction) {
        _storeReceiptSet(receiptSet, receiptType: receiptType, identifier: aci.serviceIdUppercaseString, tx: tx)
    }

    func _storeReceiptSet(_ receiptSet: MessageReceiptSet, receiptType: ReceiptType, identifier: String, tx: DBWriteTransaction) {
        let store = keyValueStore(for: receiptType)
        if receiptSet.timestamps.count > 0 {
            do {
                try store.setCodable(receiptSet, key: identifier, transaction: tx)
            } catch {
                owsFailDebug("\(error)")
            }
        } else {
            store.removeValue(forKey: identifier, transaction: tx)
        }
    }

    private func keyValueStore(for receiptType: ReceiptType) -> KeyValueStore {
        switch receiptType {
        case .delivery: return deliveryReceiptStore
        case .read: return readReceiptStore
        case .viewed: return viewedReceiptStore
        }
    }

    public func waitForPendingReceipts() async throws {
        try await pendingTasks.waitForPendingTasks()
    }
}
