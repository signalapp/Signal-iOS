//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
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

extension OWSOutgoingReceiptManager {
    @objc
    func fetchAllReceiptSets(type: OWSReceiptType, transaction tx: SDSAnyReadTransaction) -> [SignalServiceAddress: MessageReceiptSet] {
        return Dictionary(
            uniqueKeysWithValues: (
                Set(store(for: type).allKeys(transaction: tx).compactMap { SignalServiceAddress(identifier: $0) })
                    .map { ($0, fetchReceiptSet(type: type, preferredKey: $0.uuidString, secondaryKey: $0.phoneNumber, tx: tx).receiptSet) }
            )
        )
    }

    @objc
    func fetchAndMergeReceiptSet(type: OWSReceiptType, address: SignalServiceAddress, transaction tx: SDSAnyWriteTransaction) -> MessageReceiptSet {
        return fetchAndMerge(type: type, preferredKey: address.uuidString, secondaryKey: address.phoneNumber, tx: tx)
    }

    private func fetchReceiptSet(
        type: OWSReceiptType,
        preferredKey: String?,
        secondaryKey: String?,
        tx: SDSAnyReadTransaction
    ) -> (receiptSet: MessageReceiptSet, hasSecondaryValue: Bool) {
        let store = store(for: type)
        let result = MessageReceiptSet()
        if let preferredKey, store.hasValue(forKey: preferredKey, transaction: tx) {
            if let receiptSet: MessageReceiptSet = try? store.getCodableValue(forKey: preferredKey, transaction: tx) {
                result.union(receiptSet)
            } else if let numberSet = store.getObject(forKey: preferredKey, transaction: tx) as? Set<UInt64> {
                result.union(timestampSet: numberSet)
            }
        }
        var hasSecondaryValue = false
        if let secondaryKey, store.hasValue(forKey: secondaryKey, transaction: tx) {
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
        type: OWSReceiptType,
        preferredKey: String?,
        secondaryKey: String?,
        tx: SDSAnyWriteTransaction
    ) -> MessageReceiptSet {
        let (result, hasSecondaryValue) = fetchReceiptSet(
            type: type,
            preferredKey: preferredKey,
            secondaryKey: secondaryKey,
            tx: tx
        )
        if let preferredKey, let secondaryKey, hasSecondaryValue {
            store(for: type).removeValue(forKey: secondaryKey, transaction: tx)
            _storeReceiptSet(result, type: type, key: preferredKey, tx: tx)
        }
        return result
    }

    @objc
    func storeReceiptSet(_ receiptSet: MessageReceiptSet, type: OWSReceiptType, address: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        guard let key = address.uuidString ?? address.phoneNumber else {
            return owsFailDebug("Invalid address")
        }
        _storeReceiptSet(receiptSet, type: type, key: key, tx: transaction)
    }

    private func _storeReceiptSet(_ receiptSet: MessageReceiptSet, type: OWSReceiptType, key: String, tx: SDSAnyWriteTransaction) {
        let store = store(for: type)
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

    public func pendingSendsPromise() -> Promise<Void> {
        // This promise blocks on all operations already in the queue,
        // but will not block on new operations added after this promise
        // is created. That's intentional to ensure that NotificationService
        // instances complete in a timely way.
        pendingTasks.pendingTasksPromise()
    }
}

// MARK: -

fileprivate extension SignalServiceAddress {
    convenience init?(identifier: String) {
        if let uuid = UUID(uuidString: identifier) {
            self.init(uuid: uuid)
        } else if identifier.isStructurallyValidE164 {
            self.init(phoneNumber: identifier)
        } else {
            return nil
        }
    }
}
