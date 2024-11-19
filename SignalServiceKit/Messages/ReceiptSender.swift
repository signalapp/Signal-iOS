//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc
class MessageReceiptSet: NSObject, Codable {
    @objc
    public private(set) var timestamps: Set<UInt64> = Set()
    @objc
    public private(set) var uniqueIds: Set<String> = Set()

    @objc
    func insert(timestamp: UInt64, messageUniqueId: String? = nil) {
        timestamps.insert(timestamp)
        if let uniqueId = messageUniqueId {
            uniqueIds.insert(uniqueId)
        }
    }

    @objc
    func union(_ other: MessageReceiptSet) {
        timestamps.formUnion(other.timestamps)
        uniqueIds.formUnion(other.uniqueIds)
    }

    @objc
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
    private let recipientDatabaseTable: any RecipientDatabaseTable

    private let appReadiness: AppReadiness
    private let deliveryReceiptStore: KeyValueStore
    private let readReceiptStore: KeyValueStore
    private let viewedReceiptStore: KeyValueStore

    private var observers = [NSObjectProtocol]()
    private let pendingTasks = PendingTasks(label: #fileID)
    private let sendingState: AtomicValue<SendingState>

    public init(appReadiness: AppReadiness, recipientDatabaseTable: any RecipientDatabaseTable) {
        self.appReadiness = appReadiness
        self.recipientDatabaseTable = recipientDatabaseTable
        self.deliveryReceiptStore = KeyValueStore(collection: "kOutgoingDeliveryReceiptManagerCollection")
        self.readReceiptStore = KeyValueStore(collection: "kOutgoingReadReceiptManagerCollection")
        self.viewedReceiptStore = KeyValueStore(collection: "kOutgoingViewedReceiptManagerCollection")

        self.sendingState = AtomicValue(SendingState(), lock: .init())

        super.init()
        SwiftSingletons.register(self)

        observers.append(NotificationCenter.default.addObserver(
            forName: .identityStateDidChange,
            object: self,
            queue: nil,
            using: { [weak self] _ in self?.sendPendingReceiptsIfNeeded(pendingTask: nil) }
        ))

        observers.append(NotificationCenter.default.addObserver(
            forName: SSKReachability.owsReachabilityDidChange,
            object: self,
            queue: nil,
            using: { [weak self] _ in self?.sendPendingReceiptsIfNeeded(pendingTask: nil) }
        ))

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.sendPendingReceiptsIfNeeded(pendingTask: nil)
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Enqueuing

    func enqueueDeliveryReceipt(
        for decryptedEnvelope: DecryptedIncomingEnvelope,
        messageUniqueId: String?,
        tx: SDSAnyWriteTransaction
    ) {
        enqueueReceipt(
            for: decryptedEnvelope.sourceAci,
            timestamp: decryptedEnvelope.timestamp,
            messageUniqueId: messageUniqueId,
            receiptType: .delivery,
            tx: tx
        )
    }

    @objc
    public func enqueueReadReceipt(
        for address: SignalServiceAddress,
        timestamp: UInt64,
        messageUniqueId: String?,
        tx: SDSAnyWriteTransaction
    ) {
        guard let aci = address.aci else {
            Logger.warn("Dropping receipt for message without ACI.")
            return
        }
        enqueueReceipt(
            for: aci,
            timestamp: timestamp,
            messageUniqueId: messageUniqueId,
            receiptType: .read,
            tx: tx
        )
    }

    @objc
    public func enqueueViewedReceipt(
        for address: SignalServiceAddress,
        timestamp: UInt64,
        messageUniqueId: String?,
        tx: SDSAnyWriteTransaction
    ) {
        guard let aci = address.aci else {
            Logger.warn("Dropping receipt for message without ACI.")
            return
        }
        enqueueReceipt(
            for: aci,
            timestamp: timestamp,
            messageUniqueId: messageUniqueId,
            receiptType: .viewed,
            tx: tx
        )
    }

    private func enqueueReceipt(
        for aci: Aci,
        timestamp: UInt64,
        messageUniqueId: String?,
        receiptType: ReceiptType,
        tx: SDSAnyWriteTransaction
    ) {
        guard timestamp >= 1 else {
            owsFailDebug("Invalid timestamp.")
            return
        }
        let pendingTask = pendingTasks.buildPendingTask(label: "Receipt Send")
        let persistedSet = fetchReceiptSet(receiptType: receiptType, aci: aci, tx: tx.asV2Read)
        persistedSet.insert(timestamp: timestamp, messageUniqueId: messageUniqueId)
        storeReceiptSet(persistedSet, receiptType: receiptType, aci: aci, tx: tx.asV2Write)
        tx.addAsyncCompletionOffMain {
            self.sendingState.update { $0.mightHavePendingReceipts = true }
            self.sendPendingReceiptsIfNeeded(pendingTask: pendingTask)
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
    func sendPendingReceiptsIfNeeded(pendingTask: PendingTask?) {
        Task { await self._sendPendingReceiptsIfNeeded(pendingTask: pendingTask) }
    }

    private func _sendPendingReceiptsIfNeeded(pendingTask: PendingTask?) async {
        do {
            defer { pendingTask?.complete() }

            guard appReadiness.isAppReady, SSKEnvironment.shared.reachabilityManagerRef.isReachable else {
                return
            }
            guard sendingState.update(block: { $0.startIfPossible() }) else {
                return
            }
            try? await sendPendingReceipts()
        }

        // Wait N seconds before conducting another pass. This allows time for a
        // batch to accumulate.
        //
        // We want a value high enough to allow us to effectively de-duplicate
        // receipts without being so high that the user notices.
        try? await Task.sleep(nanoseconds: 3 * NSEC_PER_SEC)
        sendingState.update(block: { $0.inProgress = false })
        await _sendPendingReceiptsIfNeeded(pendingTask: nil)
    }

    private func sendPendingReceipts() async throws {
        return try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for receiptType in ReceiptType.allCases {
                taskGroup.addTask { try await self.sendReceipts(receiptType: receiptType) }
            }
            try await taskGroup.waitForAll()
        }
    }

    private func sendReceipts(receiptType: ReceiptType) async throws {
        let pendingReceipts = SSKEnvironment.shared.databaseStorageRef.read { tx in fetchAllReceiptSets(receiptType: receiptType, tx: tx.asV2Read) }
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for (aci, receiptBatches) in pendingReceipts {
                taskGroup.addTask {
                    try await self.sendReceipts(receiptType: receiptType, to: aci, receiptBatches: receiptBatches)
                }
            }
            try await taskGroup.waitForAll()
        }
    }

    private func sendReceipts(
        receiptType: ReceiptType,
        to aci: Aci?,
        receiptBatches: [ReceiptBatch]
    ) async throws {
        let sendPromise = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx -> Promise<Void>? in
            guard let aci else {
                Logger.warn("Dropping receipts without an ACI")
                return .value(())
            }

            let receiptSet = receiptBatches.reduce(into: MessageReceiptSet(), { $0.union($1.receiptSet) })
            if receiptSet.timestamps.isEmpty {
                Logger.warn("Dropping receipts without any timestamps")
                return .value(())
            }

            if SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(SignalServiceAddress(aci), transaction: tx) {
                Logger.warn("Dropping receipts for blocked \(aci)")
                return .value(())
            }

            let recipientHidingManager = DependenciesBridge.shared.recipientHidingManager
            if recipientHidingManager.isHiddenAddress(SignalServiceAddress(aci), tx: tx.asV2Read) {
                Logger.warn("Dropping receipts for hidden \(aci)")
                return .value(())
            }

            // We skip any sends to untrusted identities since we know they'll fail
            // anyway. If an identity state changes we should recheck our
            // pendingReceipts to re-attempt a send to formerly untrusted recipients.
            let identityManager = DependenciesBridge.shared.identityManager
            guard identityManager.untrustedIdentityForSending(to: SignalServiceAddress(aci), untrustedThreshold: nil, tx: tx.asV2Read) == nil else {
                Logger.warn("Skipping receipts for untrusted \(aci)")
                return nil
            }

            let thread = TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(aci), transaction: tx)
            let message: OWSReceiptsForSenderMessage
            switch receiptType {
            case .delivery:
                message = .deliveryReceiptsForSenderMessage(with: thread, receiptSet: receiptSet, transaction: tx)
            case .read:
                message = .read(with: thread, receiptSet: receiptSet, transaction: tx)
            case .viewed:
                message = .viewedReceiptsForSenderMessage(with: thread, receiptSet: receiptSet, transaction: tx)
            }

            let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueueRef
            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: message
            )
            return messageSenderJobQueue.add(
                .promise,
                message: preparedMessage,
                limitToCurrentProcessLifetime: true,
                transaction: tx
            )
        }

        guard let sendPromise else {
            return
        }

        do {
            try await sendPromise.awaitable()
            await self.dequeueReceipts(for: receiptBatches, receiptType: receiptType)
        } catch let error as MessageSenderNoSuchSignalRecipientError {
            await self.dequeueReceipts(for: receiptBatches, receiptType: receiptType)
            throw error
        }
    }

    // MARK: - Fetching & Saving

    enum ReceiptType: CaseIterable {
        case delivery
        case read
        case viewed
    }

    private func dequeueReceipts(for receiptBatches: [ReceiptBatch], receiptType: ReceiptType) async {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            for receiptBatch in receiptBatches {
                let persistedSet = self._fetchReceiptSet(receiptType: receiptType, identifier: receiptBatch.identifier, tx: tx.asV2Write)
                persistedSet.subtract(receiptBatch.receiptSet)
                self._storeReceiptSet(persistedSet, receiptType: receiptType, identifier: receiptBatch.identifier, tx: tx.asV2Write)
            }
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
        tx: DBReadTransaction
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

    public func pendingSendsPromise() -> Promise<Void> {
        // This promise blocks on all operations already in the queue but will not
        // block on new operations added after this promise is created. That's
        // intentional to ensure that NotificationService instances complete in a
        // timely way.
        pendingTasks.pendingTasksPromise()
    }
}
