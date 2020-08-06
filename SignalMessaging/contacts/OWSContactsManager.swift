//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension OWSContactsManager {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    func sortSignalAccountsWithSneakyTransaction(_ signalAccounts: [SignalAccount]) -> [SignalAccount] {
        databaseStorage.read { transaction in
            self.sortSignalAccounts(signalAccounts, transaction: transaction)
        }
    }

    func sortSignalAccounts(_ signalAccounts: [SignalAccount],
                            transaction: SDSAnyReadTransaction) -> [SignalAccount] {

        typealias SortableAccount = SortableValue<SignalAccount>
        let sortableAccounts = signalAccounts.map { signalAccount in
            return SortableAccount(value: signalAccount,
                                   comparableName: self.comparableName(for: signalAccount,
                                                                       transaction: transaction),
                                   comparableAddress: signalAccount.recipientAddress.stringForDisplay)
        }
        return sort(sortableAccounts)
    }

    // MARK: -

    func sortSignalServiceAddressesWithSneakyTransaction(_ addresses: [SignalServiceAddress]) -> [SignalServiceAddress] {
        databaseStorage.read { transaction in
            self.sortSignalServiceAddresses(addresses, transaction: transaction)
        }
    }

    func sortSignalServiceAddresses(_ addresses: [SignalServiceAddress],
                                    transaction: SDSAnyReadTransaction) -> [SignalServiceAddress] {

        typealias SortableAddress = SortableValue<SignalServiceAddress>
        let sortableAddresses = addresses.map { address in
            return SortableAddress(value: address,
                                   comparableName: self.comparableName(for: address,
                                                                       transaction: transaction),
                                   comparableAddress: address.stringForDisplay)
        }
        return sort(sortableAddresses)
    }
}

// MARK: -

fileprivate extension OWSContactsManager {

    struct SortableValue<T> {
        let value: T
        let comparableName: String
        let comparableAddress: String
    }

    func sort<T>(_ values: [SortableValue<T>]) -> [T] {
        // We want to sort E164 phone numbers _after_ names.
        let hasE164Prefix = { (string: String) -> Bool in
            string.hasPrefix("+")
        }
        return values.sorted { (left: SortableValue<T>, right: SortableValue<T>) -> Bool in
            let leftHasE164Prefix = hasE164Prefix(left.comparableName)
            let rightHasE164Prefix = hasE164Prefix(right.comparableName)

            if leftHasE164Prefix && !rightHasE164Prefix {
                return false
            } else if !leftHasE164Prefix && rightHasE164Prefix {
                return true
            }

            var comparisonResult = left.comparableName.compare(right.comparableName)
            if comparisonResult == .orderedSame {
                comparisonResult = left.comparableAddress.compare(right.comparableAddress)
            }
            return comparisonResult == .orderedAscending
        }.map { $0.value }
    }
}
