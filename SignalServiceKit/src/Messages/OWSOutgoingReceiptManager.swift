//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
    func fetchAllReceiptSets(type: OWSReceiptType, transaction: SDSAnyReadTransaction) -> [SignalServiceAddress: MessageReceiptSet] {
        let allAddresses = Set(store(for: type)
            .allKeys(transaction: transaction)
            .compactMap { SignalServiceAddress(identifier: $0) })

        let tuples = allAddresses.map { ($0, fetchReceiptSet(type: type, address: $0, transaction: transaction)) }
        return Dictionary(uniqueKeysWithValues: tuples)
    }

    @objc
    func fetchReceiptSet(type: OWSReceiptType, address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> MessageReceiptSet {
        let store = store(for: type)
        let builderSet = MessageReceiptSet()

        let hasStoredUuidSet: Bool
        let hasStoredPhoneNumberSet: Bool

        if let uuidString = address.uuidString, store.hasValue(forKey: uuidString, transaction: transaction) {
            if let receiptSet: MessageReceiptSet = try? store.getCodableValue(forKey: uuidString, transaction: transaction) {
                builderSet.union(receiptSet)
            } else if let numberSet = store.getObject(forKey: uuidString, transaction: transaction) as? Set<UInt64> {
                builderSet.union(timestampSet: numberSet)
            }
            hasStoredUuidSet = true
        } else {
            hasStoredUuidSet = false
        }

        if let phoneNumber = address.phoneNumber, store.hasValue(forKey: phoneNumber, transaction: transaction) {
            if let receiptSet: MessageReceiptSet = try? store.getCodableValue(forKey: phoneNumber, transaction: transaction) {
                builderSet.union(receiptSet)
            } else if let numberSet = store.getObject(forKey: phoneNumber, transaction: transaction) as? Set<UInt64> {
                builderSet.union(timestampSet: numberSet)
            }
            hasStoredPhoneNumberSet = true
        } else {
            hasStoredPhoneNumberSet = false
        }

        // If we're in a write transaction and we have a phone number and uuid
        // set that needed to be merged, remove the phone number set and store the merged set
        // If it's not a write transaction, we can leave it unmerged and do it later.
        if let writeTx = transaction as? SDSAnyWriteTransaction,
           hasStoredUuidSet,
           hasStoredPhoneNumberSet,
           let phoneNumber = address.phoneNumber {
            store.removeValue(forKey: phoneNumber, transaction: writeTx)
            storeReceiptSet(builderSet, type: type, address: address, transaction: writeTx)
        }

        return builderSet
    }

    @objc
    func storeReceiptSet(_ set: MessageReceiptSet, type: OWSReceiptType, address: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        let store = store(for: type)
        guard let identifier = address.uuidString ?? address.phoneNumber else {
            owsFailDebug("Invalid address")
            return
        }

        if set.timestamps.count > 0 {
            do {
                try store.setCodable(set, key: identifier, transaction: transaction)
            } catch {
                owsFailDebug("\(error)")
            }
        } else {
            store.removeValue(forKey: identifier, transaction: transaction)
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
        } else if (identifier as NSString).isValidE164() {
            self.init(phoneNumber: identifier)
        } else {
            return nil
        }
    }
}
