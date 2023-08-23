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
        // PNI TODO: Check the PNI column if this is a PNI.
        guard let uuidString = serviceId?.temporary_rawUUID.uuidString else { return nil }
        let sql = "SELECT * FROM \(SignalRecipient.databaseTableName) WHERE \(signalRecipientColumn: .aciString) = ?"
        return SignalRecipient.anyFetch(sql: sql, arguments: [uuidString], transaction: tx)
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
        guard !addresses.isEmpty else { return [] }

        let phoneNumbersToLookup = addresses.compactMap { $0.phoneNumber }.map { "'\($0)'" }.joined(separator: ",")
        // PNI TODO: Check the PNI column if this is a PNI.
        let uuidsToLookup = addresses.compactMap { $0.serviceId?.temporary_rawUUID.uuidString }.map { "'\($0)'" }.joined(separator: ",")

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
