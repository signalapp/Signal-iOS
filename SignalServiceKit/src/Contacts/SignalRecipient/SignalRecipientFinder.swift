//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

public class SignalRecipientFinder {
    public init() {}

    public func signalRecipientForServiceId(_ serviceId: ServiceId?, tx: SDSAnyReadTransaction) -> SignalRecipient? {
        guard let serviceId else { return nil }
        let serviceIdColumn: SignalRecipient.CodingKeys
        switch serviceId.kind {
        case .aci:
            serviceIdColumn = .aciString
        case .pni:
            serviceIdColumn = .pni
        }
        let sql = "SELECT * FROM \(SignalRecipient.databaseTableName) WHERE \(signalRecipientColumn: serviceIdColumn) = ?"
        return SignalRecipient.anyFetch(sql: sql, arguments: [serviceId.serviceIdUppercaseString], transaction: tx)
    }

    public func signalRecipientForPhoneNumber(_ phoneNumber: String?, tx: SDSAnyReadTransaction) -> SignalRecipient? {
        guard let phoneNumber = phoneNumber else { return nil }
        let sql = "SELECT * FROM \(SignalRecipient.databaseTableName) WHERE \(signalRecipientColumn: .phoneNumber) = ?"
        return SignalRecipient.anyFetch(sql: sql, arguments: [phoneNumber], transaction: tx)
    }

    public func signalRecipient(for address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> SignalRecipient? {
        if let recipient = signalRecipientForServiceId(address.serviceId, tx: tx) {
            return recipient
        } else if let recipient = signalRecipientForPhoneNumber(address.phoneNumber, tx: tx) {
            return recipient
        } else {
            return nil
        }
    }

    public func signalRecipients(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [SignalRecipient] {
        let phoneNumbersToLookUp = addresses.compactMap { $0.phoneNumber }
        let aciStringsToLookUp = addresses.compactMap { ($0.serviceId as? Aci)?.serviceIdUppercaseString }
        let pniStringsToLookUp = addresses.compactMap { ($0.serviceId as? Pni)?.serviceIdUppercaseString }

        func orClause(column: SignalRecipient.CodingKeys, values: [String]) -> String? {
            if values.isEmpty {
                return nil
            }
            let wrappedValues = values.lazy.map { "'\($0)'" }.joined(separator: ",")
            return "\(signalRecipientColumn: column) IN (\(wrappedValues))"
        }

        // A SQL query for "Col1 IN (v1, v2, v3)" will use an index that's
        // available. A SQL query for "Col1 IN ()" will *not* use an index and will
        // fall back to a full table scan. If you have a series of OR clauses that
        // are all indexed and any of them includes "IN ()", the entire query will
        // bypass all indexes. Therefore, we omit OR clauses that won't return any
        // matches, and we return no results if we're left without any OR clauses.
        let orClauses: [String] = [
            orClause(column: .phoneNumber, values: phoneNumbersToLookUp),
            orClause(column: .aciString, values: aciStringsToLookUp),
            orClause(column: .pni, values: pniStringsToLookUp),
        ].compacted()

        if orClauses.isEmpty {
            return []
        }

        let sql = "SELECT * FROM \(SignalRecipient.databaseTableName) WHERE \(orClauses.joined(separator: " OR "))"

        var result = [SignalRecipient]()
        SignalRecipient.anyEnumerate(transaction: tx, sql: sql, arguments: []) { signalRecipient, _ in
            result.append(signalRecipient)
        }
        return result
    }
}
