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

        struct SortableAccount {
            let signalAccount: SignalAccount
            let comparableName: String
            let comparableAddress: String
        }
        let sortableAccounts = signalAccounts.map { signalAccount in
            return SortableAccount(signalAccount: signalAccount,
                                   comparableName: self.comparableName(for: signalAccount,
                                                                       transaction: transaction),
                                   comparableAddress: signalAccount.recipientAddress.stringForDisplay)
        }
        return sortableAccounts.sorted { (left: SortableAccount, right: SortableAccount) -> Bool in
            var comparisonResult = left.comparableName.compare(right.comparableName)
            if comparisonResult == .orderedSame {
                comparisonResult = left.comparableAddress.compare(right.comparableAddress)
            }
            return comparisonResult == .orderedAscending
        }.map { $0.signalAccount }
    }
}
