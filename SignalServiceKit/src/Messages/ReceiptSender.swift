//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

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

    fileprivate func union(timestampSet: Set<UInt64>) {
        timestamps.formUnion(timestampSet)
    }
}

// MARK: - ReceiptSender

@objc
public class ReceiptSender: NSObject {
    private let signalServiceAddressCacheRef: SignalServiceAddressCache

    private let deliveryReceiptStore: KeyValueStore
    private let readReceiptStore: KeyValueStore
    private let viewedReceiptStore: KeyValueStore

    private var observers = [NSObjectProtocol]()
    private let pendingTasks = PendingTasks(label: #fileID)
    private let sendingState: AtomicValue<SendingState>

    public init(kvStoreFactory: KeyValueStoreFactory, signalServiceAddressCache: SignalServiceAddressCache) {
        self.signalServiceAddressCacheRef = signalServiceAddressCache
        self.deliveryReceiptStore = kvStoreFactory.keyValueStore(collection: "kOutgoingDeliveryReceiptManagerCollection")
        self.readReceiptStore = kvStoreFactory.keyValueStore(collection: "kOutgoingReadReceiptManagerCollection")
        self.viewedReceiptStore = kvStoreFactory.keyValueStore(collection: "kOutgoingViewedReceiptManagerCollection")

        self.sendingState = AtomicValue(SendingState(), lock: AtomicLock())

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

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
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
            for: SignalServiceAddress(
                serviceId: decryptedEnvelope.sourceAci,
                phoneNumber: nil,
                cache: signalServiceAddressCacheRef,
                cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
            ),
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
        enqueueReceipt(
            for: address,
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
        enqueueReceipt(
            for: address,
            timestamp: timestamp,
            messageUniqueId: messageUniqueId,
            receiptType: .viewed,
            tx: tx
        )
    }

    private func enqueueReceipt(
        for address: SignalServiceAddress,
        timestamp: UInt64,
        messageUniqueId: String?,
        receiptType: ReceiptType,
        tx: SDSAnyWriteTransaction
    ) {
        owsAssertDebug(address.isValid)
        guard timestamp >= 1 else {
            owsFailDebug("Invalid timestamp.")
            return
        }
        let pendingTask = pendingTasks.buildPendingTask(label: "Receipt Send")
        let persistedSet = fetchAndMergeReceiptSet(receiptType: receiptType, address: address, tx: tx.asV2Write)
        persistedSet.insert(timestamp: timestamp, messageUniqueId: messageUniqueId)
        storeReceiptSet(persistedSet, receiptType: receiptType, address: address, tx: tx.asV2Write)
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

            guard AppReadiness.isAppReady, reachabilityManager.isReachable else {
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
        let pendingReceipts = databaseStorage.read { tx in fetchAllReceiptSets(receiptType: receiptType, tx: tx.asV2Read) }
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for (address, receiptSet) in pendingReceipts {
                guard address.isValid else {
                    owsFailDebug("Invalid address.")
                    continue
                }
                guard !receiptSet.timestamps.isEmpty else {
                    owsFailDebug("No timestamps.")
                    continue
                }
                taskGroup.addTask {
                    try await self.sendReceipts(receiptType: receiptType, to: address, receiptSet: receiptSet)
                }
            }
            try await taskGroup.waitForAll()
        }
    }

    private func sendReceipts(
        receiptType: ReceiptType,
        to address: SignalServiceAddress,
        receiptSet: MessageReceiptSet
    ) async throws {
        let sendPromise = await databaseStorage.awaitableWrite { tx -> Promise<Void>? in
            if self.blockingManager.isAddressBlocked(address, transaction: tx) {
                Logger.warn("Dropping receipts for blocked address \(address)")
                return .value(())
            }

            let recipientHidingManager = DependenciesBridge.shared.recipientHidingManager
            if recipientHidingManager.isHiddenAddress(address, tx: tx.asV2Read) {
                Logger.warn("Dropping receipts for hidden address \(address)")
                return .value(())
            }

            // We skip any sends to untrusted identities since we know they'll fail
            // anyway. If an identity state changes we should recheck our
            // pendingReceipts to re-attempt a send to formerly untrusted recipients.
            let identityManager = DependenciesBridge.shared.identityManager
            guard identityManager.untrustedIdentityForSending(to: address, untrustedThreshold: nil, tx: tx.asV2Read) == nil else {
                Logger.warn("Skipping receipts for untrusted address \(address)")
                return nil
            }

            let thread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: tx)
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
            return messageSenderJobQueue.add(
                .promise,
                message: message.asPreparer,
                limitToCurrentProcessLifetime: true,
                transaction: tx
            )
        }

        guard let sendPromise else {
            return
        }

        do {
            try await sendPromise.awaitable()
            await self.dequeueReceipts(for: address, receiptType: receiptType, receiptSet: receiptSet)
        } catch let error as MessageSenderNoSuchSignalRecipientError {
            await self.dequeueReceipts(for: address, receiptType: receiptType, receiptSet: receiptSet)
            throw error
        }
    }

    // MARK: - Fetching & Saving

    enum ReceiptType: CaseIterable {
        case delivery
        case read
        case viewed
    }

    private func dequeueReceipts(for address: SignalServiceAddress, receiptType: ReceiptType, receiptSet: MessageReceiptSet) async {
        owsAssertDebug(address.isValid)
        await databaseStorage.awaitableWrite { tx in
            let persistedSet = self.fetchAndMergeReceiptSet(receiptType: receiptType, address: address, tx: tx.asV2Write)
            persistedSet.subtract(receiptSet)
            self.storeReceiptSet(persistedSet, receiptType: receiptType, address: address, tx: tx.asV2Write)
        }
    }

    func fetchAllReceiptSets(receiptType: ReceiptType, tx: DBReadTransaction) -> [SignalServiceAddress: MessageReceiptSet] {
        let store = keyValueStore(for: receiptType)
        let addresses = Set(store.allKeys(transaction: tx).compactMap { self.parseIdentifier($0) })
        return Dictionary(uniqueKeysWithValues: addresses.map {
            ($0, fetchReceiptSet(
                receiptType: receiptType,
                preferredKey: $0.aciUppercaseString,
                secondaryKey: $0.phoneNumber,
                tx: tx
            ).receiptSet)
        })
    }

    private func parseIdentifier(_ identifier: String) -> SignalServiceAddress? {
        if let aci = Aci.parseFrom(aciString: identifier) {
            return SignalServiceAddress(
                serviceId: aci,
                phoneNumber: nil,
                cache: signalServiceAddressCacheRef,
                cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
            )
        } else if let phoneNumber = E164(identifier) {
            return SignalServiceAddress(
                serviceId: nil,
                phoneNumber: phoneNumber.stringValue,
                cache: signalServiceAddressCacheRef,
                cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
            )
        } else {
            return nil
        }
    }

    func fetchAndMergeReceiptSet(receiptType: ReceiptType, address: SignalServiceAddress, tx: DBWriteTransaction) -> MessageReceiptSet {
        return fetchAndMerge(receiptType: receiptType, preferredKey: address.aciUppercaseString, secondaryKey: address.phoneNumber, tx: tx)
    }

    private func fetchReceiptSet(
        receiptType: ReceiptType,
        preferredKey: String?,
        secondaryKey: String?,
        tx: DBReadTransaction
    ) -> (receiptSet: MessageReceiptSet, hasSecondaryValue: Bool) {
        let store = keyValueStore(for: receiptType)
        let result = MessageReceiptSet()
        if let preferredKey, store.hasValue(preferredKey, transaction: tx) {
            if let receiptSet: MessageReceiptSet = try? store.getCodableValue(forKey: preferredKey, transaction: tx) {
                result.union(receiptSet)
            } else if let numberSet = store.getObject(forKey: preferredKey, transaction: tx) as? Set<UInt64> {
                result.union(timestampSet: numberSet)
            }
        }
        var hasSecondaryValue = false
        if let secondaryKey, store.hasValue(secondaryKey, transaction: tx) {
            if let receiptSet: MessageReceiptSet = try? store.getCodableValue(forKey: secondaryKey, transaction: tx) {
                result.union(receiptSet)
            } else if let numberSet = store.getObject(forKey: secondaryKey, transaction: tx) as? Set<UInt64> {
                result.union(timestampSet: numberSet)
            }
            hasSecondaryValue = true
        }
        return (result, hasSecondaryValue)
    }

    private func fetchAndMerge(
        receiptType: ReceiptType,
        preferredKey: String?,
        secondaryKey: String?,
        tx: DBWriteTransaction
    ) -> MessageReceiptSet {
        let (result, hasSecondaryValue) = fetchReceiptSet(
            receiptType: receiptType,
            preferredKey: preferredKey,
            secondaryKey: secondaryKey,
            tx: tx
        )
        if let preferredKey, let secondaryKey, hasSecondaryValue {
            keyValueStore(for: receiptType).removeValue(forKey: secondaryKey, transaction: tx)
            _storeReceiptSet(result, receiptType: receiptType, key: preferredKey, tx: tx)
        }
        return result
    }

    func storeReceiptSet(_ receiptSet: MessageReceiptSet, receiptType: ReceiptType, address: SignalServiceAddress, tx: DBWriteTransaction) {
        guard let key = address.aciUppercaseString ?? address.phoneNumber else {
            return owsFailDebug("Invalid address")
        }
        _storeReceiptSet(receiptSet, receiptType: receiptType, key: key, tx: tx)
    }

    private func _storeReceiptSet(_ receiptSet: MessageReceiptSet, receiptType: ReceiptType, key: String, tx: DBWriteTransaction) {
        let store = keyValueStore(for: receiptType)
        if receiptSet.timestamps.count > 0 {
            do {
                try store.setCodable(receiptSet, key: key, transaction: tx)
            } catch {
                owsFailDebug("\(error)")
            }
        } else {
            store.removeValue(forKey: key, transaction: tx)
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
