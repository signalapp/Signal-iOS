//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient

@objc
public class AnySignalAccountFinder: NSObject {
    let grdbAdapter = GRDBSignalAccountFinder()
}

extension AnySignalAccountFinder {
    func signalAccount(
        for address: SignalServiceAddress,
        transaction: SDSAnyReadTransaction
    ) -> SignalAccount? {
        return grdbAdapter.signalAccount(for: address, transaction: transaction.unwrapGrdbRead)
    }

    func signalAccounts(
        for addresses: [SignalServiceAddress],
        transaction: SDSAnyReadTransaction
    ) -> [SignalAccount?] {
        return grdbAdapter.signalAccounts(for: addresses, transaction: transaction.unwrapGrdbRead)
    }
}

@objc
class GRDBSignalAccountFinder: NSObject {
    func signalAccount(for address: SignalServiceAddress, transaction: GRDBReadTransaction) -> SignalAccount? {
        return signalAccounts(for: [address], transaction: transaction)[0]
    }

    func signalAccounts(
        for addresses: [SignalServiceAddress],
        transaction: GRDBReadTransaction
    ) -> [SignalAccount?] {
        return Refinery<SignalServiceAddress, SignalAccount>(addresses).refine { addresses in
            return signalAccountsForServiceIds(
                addresses.map { $0.serviceId },
                transaction: transaction
            )
        }.refine { addresses in
            return signalAccountsForPhoneNumbers(
                addresses.map { $0.phoneNumber },
                transaction: transaction
            )
        }.values
    }

    private func signalAccountsWhere(column: String, anyValueIn values: [String], transaction: GRDBReadTransaction) -> [SignalAccount?] {
        guard !values.isEmpty else {
            return []
        }
        let qms = Array(repeating: "?", count: values.count).joined(separator: ", ")
        let sql = "SELECT * FROM \(SignalAccount.databaseTableName) WHERE \(column) in (\(qms))"

        /// Why did we use `allSignalAccounts` instead of `SignalAccount.anyFetchAll`?
        /// The reason is that the `SignalAccountReadCache` needs to have
        /// `didReadSignalAccount` called on it for each record we enumerate, and
        /// `SignalAccount.anyEnumerate` has this built in.
        return allSignalAccounts(transaction: transaction, sql: sql, arguments: StatementArguments(values))
    }

    private func allSignalAccounts(
        transaction: GRDBReadTransaction,
        sql: String,
        arguments: StatementArguments
    ) -> [SignalAccount] {
        var result = [SignalAccount]()
        SignalAccount.anyEnumerate(transaction: transaction.asAnyRead, sql: sql, arguments: arguments) { account, _ in
            result.append(account)
        }
        return result
    }

    private func signalAccountsForServiceIds(_ serviceIds: [ServiceId?], transaction: GRDBReadTransaction) -> [SignalAccount?] {
        let accounts = signalAccountsWhere(
            column: SignalAccount.columnName(.recipientServiceId),
            anyValueIn: serviceIds.compactMap { $0?.serviceIdUppercaseString },
            transaction: transaction
        )

        let index: [ServiceId?: [SignalAccount?]] = Dictionary(grouping: accounts) { $0?.recipientServiceId }
        return serviceIds.map { maybeServiceId -> SignalAccount? in
            guard
                let serviceId = maybeServiceId,
                let accountsForServiceId = index[serviceId],
                let firstAccountForServiceId = accountsForServiceId.first
            else {
                return nil
            }

            return firstAccountForServiceId
        }
    }

    private func signalAccountsForPhoneNumbers(
        _ phoneNumbers: [String?],
        transaction: GRDBReadTransaction
    ) -> [SignalAccount?] {
        let accounts = signalAccountsWhere(
            column: SignalAccount.columnName(.recipientPhoneNumber),
            anyValueIn: phoneNumbers.compacted(),
            transaction: transaction
        )

        let index: [String?: [SignalAccount?]] = Dictionary(grouping: accounts) { $0?.recipientPhoneNumber }
        return phoneNumbers.map { maybePhoneNumber -> SignalAccount? in
            guard
                let phoneNumber = maybePhoneNumber,
                let accountsForPhoneNumber = index[phoneNumber],
                let firstAccountForPhoneNumber = accountsForPhoneNumber.first
            else {
                return nil
            }

            return firstAccountForPhoneNumber
        }
    }
}
