//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient

public class SignalAccountFinder: NSObject {
    func signalAccount(
        for address: SignalServiceAddress,
        tx: SDSAnyReadTransaction
    ) -> SignalAccount? {
        if
            let serviceId = address.serviceId,
            let uuidMatch = signalAccountWhere(
                column: SignalAccount.columnName(.recipientServiceId),
                matches: serviceId.serviceIdUppercaseString,
                tx: tx
            )
        {
            return uuidMatch
        } else if
            let phoneNumber = address.phoneNumber,
            let phoneNumberMatch = signalAccountWhere(
                column: SignalAccount.columnName(.recipientPhoneNumber),
                matches: phoneNumber,
                tx: tx
            )
        {
            return phoneNumberMatch
        }
        return nil
    }

    public func signalAccount(
        for e164: E164,
        tx: SDSAnyReadTransaction
    ) -> SignalAccount? {
        return signalAccountWhere(
            column: SignalAccount.columnName(.recipientPhoneNumber),
            matches: e164.stringValue,
            tx: tx
        )
    }

    func signalAccounts(
        for addresses: [SignalServiceAddress],
        tx: SDSAnyReadTransaction
    ) -> [SignalAccount?] {
        return Refinery<SignalServiceAddress, SignalAccount>(addresses).refine { addresses in
            return signalAccountsForServiceIds(
                addresses.map { $0.serviceId },
                tx: tx
            )
        }.refine { addresses in
            return signalAccountsForPhoneNumbers(
                addresses.map { $0.phoneNumber },
                tx: tx
            )
        }.values
    }

    private func signalAccountsForServiceIds(
        _ serviceIds: [ServiceId?],
        tx: SDSAnyReadTransaction
    ) -> [SignalAccount?] {
        let accounts = signalAccountsWhere(
            column: SignalAccount.columnName(.recipientServiceId),
            anyValueIn: serviceIds.compactMap { $0?.serviceIdUppercaseString },
            tx: tx
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
        tx: SDSAnyReadTransaction
    ) -> [SignalAccount?] {
        let accounts = signalAccountsWhere(
            column: SignalAccount.columnName(.recipientPhoneNumber),
            anyValueIn: phoneNumbers.compacted(),
            tx: tx
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

    private func signalAccountsWhere(
        column: String,
        anyValueIn values: [String],
        tx: SDSAnyReadTransaction
    ) -> [SignalAccount?] {
        guard !values.isEmpty else {
            return []
        }
        let qms = Array(repeating: "?", count: values.count).joined(separator: ", ")
        let sql = "SELECT * FROM \(SignalAccount.databaseTableName) WHERE \(column) in (\(qms))"

        /// Why did we use `allSignalAccounts` instead of `SignalAccount.anyFetchAll`?
        /// The reason is that the `SignalAccountReadCache` needs to have
        /// `didReadSignalAccount` called on it for each record we enumerate, and
        /// `SignalAccount.anyEnumerate` has this built in.
        return allSignalAccounts(
            tx: tx,
            sql: sql,
            arguments: StatementArguments(values)
        )
    }

    private func signalAccountWhere(
        column: String,
        matches matchString: String,
        tx: SDSAnyReadTransaction
    ) -> SignalAccount? {
        let sql = "SELECT * FROM \(SignalAccount.databaseTableName) WHERE \(column) = ? LIMIT 1"

        /// Why did we use `allSignalAccounts` instead of `SignalAccount.anyFetchAll`?
        /// The reason is that the `SignalAccountReadCache` needs to have
        /// `didReadSignalAccount` called on it for each record we enumerate, and
        /// `SignalAccount.anyEnumerate` has this built in.
        return allSignalAccounts(
            tx: tx,
            sql: sql,
            arguments: [matchString]
        ).first
    }

    private func allSignalAccounts(
        tx: SDSAnyReadTransaction,
        sql: String,
        arguments: StatementArguments
    ) -> [SignalAccount] {
        var result = [SignalAccount]()
        SignalAccount.anyEnumerate(
            transaction: tx,
            sql: sql,
            arguments: arguments
        ) { account, _ in
            result.append(account)
        }
        return result
    }
}
