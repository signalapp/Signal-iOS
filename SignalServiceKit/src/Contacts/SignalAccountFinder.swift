//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

@objc
public class AnySignalAccountFinder: NSObject {
    let grdbAdapter = GRDBSignalAccountFinder()
}

extension AnySignalAccountFinder {
    @objc(signalAccountForAddress:transaction:)
    func signalAccount(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalAccount? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.signalAccount(for: address, transaction: transaction)
        }
    }

    func signalAccounts(for addresses: [SignalServiceAddress],
                        transaction: SDSAnyReadTransaction) -> [SignalAccount?] {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.signalAccounts(for: addresses, transaction: transaction)
        }
    }
}

@objc
class GRDBSignalAccountFinder: NSObject {
    func signalAccount(for address: SignalServiceAddress, transaction: GRDBReadTransaction) -> SignalAccount? {
        return signalAccounts(for: [address], transaction: transaction)[0]
    }

    func signalAccounts(for addresses: [SignalServiceAddress],
                        transaction: GRDBReadTransaction) -> [SignalAccount?] {
        return Refinery<SignalServiceAddress, SignalAccount>(addresses).refine { addresses in
            return signalAccountsForUUIDs(addresses.map { $0.uuid }, transaction: transaction)
        }.refine { addresses in
            return signalAccountsForPhoneNumbers(addresses.map { $0.phoneNumber },
                                                 transaction: transaction)
        }.values
    }

    private func signalAccountsWhere(column: String, anyValueIn values: [String], transaction: GRDBReadTransaction) -> [SignalAccount?] {
        guard !values.isEmpty else {
            return []
        }
        let qms = Array(repeating: "?", count: values.count).joined(separator: ", ")
        let sql = "SELECT * FROM \(SignalAccount.databaseTableName) WHERE \(column) in (\(qms))"
        do {
            let cursor = try SignalAccount.fetchCursor(
                transaction.database,
                sql: sql,
                arguments: StatementArguments(values)
            )
            /// Why did we use `allSignalAccounts` instead of `SignalAccount.anyFetchAll`?
            /// The reason is that the `SignalAccountReadCache` needs to have
            /// `didReadSignalAccount` called on it for each record we enumerate, and
            /// `SignalAccount.anyEnumerate` has this built in.
            return allSignalAccounts(cursor: cursor, transaction: transaction)
        } catch {
            owsAssertDebug(false, "Database error while fetching \(column) for \(values.count) values: \(error.localizedDescription)")
            return Array(repeating: nil, count: values.count)
        }
    }

    private func allSignalAccounts(cursor: RecordCursor<SignalAccount>,
                                   transaction: GRDBReadTransaction) -> [SignalAccount] {
        var result = [SignalAccount]()
        SignalAccount.anyEnumerate(transaction: transaction.asAnyRead) { account, _ in
            result.append(account)
        }
        return result
    }

    private func signalAccountsForUUIDs(_ uuids: [UUID?], transaction: GRDBReadTransaction) -> [SignalAccount?] {
        let accounts = signalAccountsWhere(column: SignalAccount.columnName(.recipientUUID),
                                           anyValueIn: uuids.lazy.compactMap { $0?.uuidString },
                                           transaction: transaction)
        let index: [String?: [SignalAccount?]] = Dictionary(grouping: accounts) { $0?.recipientUUID }
        return uuids.map { maybeUUID -> SignalAccount? in
            guard let uuid = maybeUUID else {
                return nil
            }
            return index[uuid.uuidString]?.first ?? nil
        }
    }

    private func signalAccountsForPhoneNumbers(_ phoneNumbers: [String?], transaction: GRDBReadTransaction) -> [SignalAccount?] {
        return Refinery<String?, SignalAccount>(phoneNumbers).refineNonnilKeys { phoneNumbers -> [SignalAccount?] in
            let accounts = signalAccountsWhere(column: SignalAccount.columnName(.recipientPhoneNumber),
                                               anyValueIn: Array(phoneNumbers),
                                               transaction: transaction)
            let index = Dictionary(grouping: accounts) { $0?.recipientPhoneNumber }
            let orderedAccounts = phoneNumbers.map { phoneNumber -> SignalAccount? in
                guard let array = index[phoneNumber], let first = array.first else {
                    return nil
                }
                return first
            }
            return orderedAccounts
        }.values
    }
}
