//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

public class SignalRecipientFinder {
    public init() {}

    public func signalRecipientForUUID(_ uuid: UUID?, tx: SDSAnyReadTransaction) -> SignalRecipient? {
        guard let uuidString = uuid?.uuidString else { return nil }
        let sql = "SELECT * FROM \(SignalRecipient.databaseTableName) WHERE \(signalRecipientColumn: .aciString) = ?"
        return SignalRecipient.anyFetch(sql: sql, arguments: [uuidString], transaction: tx)
    }

    public func signalRecipientForPhoneNumber(_ phoneNumber: String?, tx: SDSAnyReadTransaction) -> SignalRecipient? {
        guard let phoneNumber = phoneNumber else { return nil }
        let sql = "SELECT * FROM \(SignalRecipient.databaseTableName) WHERE \(signalRecipientColumn: .phoneNumber) = ?"
        return SignalRecipient.anyFetch(sql: sql, arguments: [phoneNumber], transaction: tx)
    }

    public func signalRecipient(for address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> SignalRecipient? {
        if let recipient = signalRecipientForUUID(address.uuid, tx: tx) {
            return recipient
        } else if let recipient = signalRecipientForPhoneNumber(address.phoneNumber, tx: tx) {
            return recipient
        } else {
            return nil
        }
    }

    public func signalRecipients(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [SignalRecipient] {
        guard !addresses.isEmpty else { return [] }

        // PNI TODO: Support PNIs.
        let phoneNumbersToLookup = addresses.compactMap { $0.phoneNumber }.map { "'\($0)'" }.joined(separator: ",")
        let uuidsToLookup = addresses.compactMap { $0.uuidString }.map { "'\($0)'" }.joined(separator: ",")

        let sql = """
            SELECT * FROM \(SignalRecipient.databaseTableName)
            WHERE \(signalRecipientColumn: .phoneNumber) IN (\(phoneNumbersToLookup))
            OR \(signalRecipientColumn: .aciString) IN (\(uuidsToLookup))
        """

        var result = [SignalRecipient]()
        SignalRecipient.anyEnumerate(transaction: tx, sql: sql, arguments: []) { signalRecipient, _ in
            result.append(signalRecipient)
        }
        return result
    }
}
