//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class MessageReceiptSet: NSObject {
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

    fileprivate func union(_ otherSet: Set<UInt64>) {
        timestamps.formUnion(otherSet)
    }
}

extension OWSOutgoingReceiptManager {
    @objc
    func fetchAllReceiptSets(type: OWSReceiptType, transaction: SDSAnyReadTransaction) -> [SignalServiceAddress: MessageReceiptSet] {
        let allAddresses = store(for: type)
            .allKeys(transaction: transaction)
            .map { SignalServiceAddress(identifier: $0) }

        let tuples = allAddresses.map { ($0, fetchReceiptSet(type: type, address: $0, transaction: transaction)) }
        return Dictionary(uniqueKeysWithValues: tuples)
    }

    @objc
    func fetchReceiptSet(type: OWSReceiptType, address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> MessageReceiptSet {
        let store = store(for: type)
        let builderSet = MessageReceiptSet()

        let existingUUIDStore = address.uuidString.flatMap { store.getObject(forKey: $0, transaction: transaction) }
        if let numberSet = existingUUIDStore as? Set<UInt64> {
            builderSet.union(numberSet)
        } else if let receiptSet = existingUUIDStore as? MessageReceiptSet {
            builderSet.union(receiptSet)
        }

        let existingPhoneNumberStore = address.phoneNumber.flatMap { store.getObject(forKey: $0, transaction: transaction) }
        if let numberSet = existingPhoneNumberStore as? Set<UInt64> {
            builderSet.union(numberSet)
        } else if let receiptSet = existingPhoneNumberStore as? MessageReceiptSet {
            builderSet.union(receiptSet)
        }

        // If we're in a write transaction and we have a phone number and uuid
        // store that need to be merged, remove the phone number
        // If it's not a write transaction, we can leave it unmerged and do it later.
        if let writeTx = transaction as? SDSAnyWriteTransaction,
           existingUUIDStore != nil,
           existingPhoneNumberStore != nil,
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
            store.setObject(set, key: identifier, transaction: transaction)
        } else {
            store.removeValue(forKey: identifier, transaction: transaction)
        }
    }
}

fileprivate extension SignalServiceAddress {
    convenience init(identifier: String) {
        if let uuid = UUID(uuidString: identifier) {
            self.init(uuid: uuid)
        } else {
            self.init(phoneNumber: identifier)
        }
    }
}
