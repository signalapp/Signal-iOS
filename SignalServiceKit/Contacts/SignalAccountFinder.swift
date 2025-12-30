//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient

public struct SignalAccountFinder {
    public init() {
    }

    public func signalAccount(
        for e164: E164,
        tx: DBReadTransaction,
    ) -> SignalAccount? {
        return signalAccount(for: e164.stringValue, tx: tx)
    }

    func signalAccount(
        for phoneNumber: String,
        tx: DBReadTransaction,
    ) -> SignalAccount? {
        return signalAccountWhere(
            column: SignalAccount.columnName(.recipientPhoneNumber),
            matches: phoneNumber,
            tx: tx,
        )
    }

    func signalAccounts(
        for phoneNumbers: [String],
        tx: DBReadTransaction,
    ) -> [SignalAccount?] {
        return signalAccountsForPhoneNumbers(phoneNumbers, tx: tx)
    }

    private func signalAccountsForPhoneNumbers(
        _ phoneNumbers: [String?],
        tx: DBReadTransaction,
    ) -> [SignalAccount?] {
        let accounts = signalAccountsWhere(
            column: SignalAccount.columnName(.recipientPhoneNumber),
            anyValueIn: phoneNumbers.compacted(),
            tx: tx,
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
        tx: DBReadTransaction,
    ) -> [SignalAccount?] {
        guard !values.isEmpty else {
            return []
        }
        let qms = Array(repeating: "?", count: values.count).joined(separator: ", ")
        let sql = "SELECT * FROM \(SignalAccount.databaseTableName) WHERE \(column) in (\(qms))"

        return allSignalAccounts(
            tx: tx,
            sql: sql,
            arguments: StatementArguments(values),
        )
    }

    private func signalAccountWhere(
        column: String,
        matches matchString: String,
        tx: DBReadTransaction,
    ) -> SignalAccount? {
        let sql = "SELECT * FROM \(SignalAccount.databaseTableName) WHERE \(column) = ? LIMIT 1"

        return allSignalAccounts(
            tx: tx,
            sql: sql,
            arguments: [matchString],
        ).first
    }

    private func allSignalAccounts(
        tx: DBReadTransaction,
        sql: String,
        arguments: StatementArguments,
    ) -> [SignalAccount] {
        var result = [SignalAccount]()
        SignalAccount.anyEnumerate(
            transaction: tx,
            sql: sql,
            arguments: arguments,
        ) { account, _ in
            result.append(account)
        }
        return result
    }

    func fetchPhoneNumbers(tx: DBReadTransaction) throws -> [String] {
        let sql = """
            SELECT \(SignalAccount.columnName(.recipientPhoneNumber)) FROM \(SignalAccount.databaseTableName)
        """
        do {
            return try String?.fetchAll(tx.database, sql: sql).compacted()
        } catch {
            throw error.grdbErrorForLogging
        }
    }
}
