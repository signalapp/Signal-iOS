//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class AnySignalRecipientFinder: NSObject {
    let grdbAdapter = GRDBSignalRecipientFinder()
    let yapdbAdapter = YAPDBSignalServiceAddressIndex()
}

extension AnySignalRecipientFinder {
    @objc(signalRecipientForUUID:transaction:)
    public func signalRecipientForUUID(_ uuid: UUID?, transaction: SDSAnyReadTransaction) -> SignalRecipient? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.signalRecipientForUUID(uuid, transaction: transaction)
        case .yapRead(let transaction):
            return yapdbAdapter.fetchOneForUUID(uuid, transaction: transaction)
        }
    }

    @objc(signalRecipientForPhoneNumber:transaction:)
    public func signalRecipientForPhoneNumber(_ phoneNumber: String?, transaction: SDSAnyReadTransaction) -> SignalRecipient? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.signalRecipientForPhoneNumber(phoneNumber, transaction: transaction)
        case .yapRead(let transaction):
            return yapdbAdapter.fetchOneForPhoneNumber(phoneNumber, transaction: transaction)
        }
    }

    @objc(signalRecipientForAddress:transaction:)
    public func signalRecipient(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalRecipient? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.signalRecipient(for: address, transaction: transaction)
        case .yapRead(let transaction):
            return yapdbAdapter.fetchOne(for: address, transaction: transaction)
        }
    }

    public func signalRecipients(for addresses: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> [SignalRecipient] {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.signalRecipients(for: addresses, transaction: transaction)
        case .yapRead:
            fatalError("yap not supported")
        }
    }

    /// Fetches and returns all registered SignalRecipients that do not have a UUID
    /// Note: The registered device set is currently represented in an archive blob. So the schema doesn't currently
    /// allow us to filter on registered recipients. So the underlying query fetches *all* recipients without a UUID,
    /// then filters where devices.count > 0.
    public func registeredRecipientsWithoutUUID(transaction: SDSAnyReadTransaction) -> [SignalRecipient] {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.registeredRecipientsWithoutUUID(transaction: transaction)
        case .yapRead:
            fatalError("yap not supported")
        }
    }
}

@objc
class GRDBSignalRecipientFinder: NSObject {
    func signalRecipient(for address: SignalServiceAddress, transaction: GRDBReadTransaction) -> SignalRecipient? {
        if let recipient = signalRecipientForUUID(address.uuid, transaction: transaction) {
            return recipient
        } else if let recipient = signalRecipientForPhoneNumber(address.phoneNumber, transaction: transaction) {
            return recipient
        } else {
            return nil
        }
    }

    fileprivate func signalRecipientForUUID(_ uuid: UUID?, transaction: GRDBReadTransaction) -> SignalRecipient? {
        guard let uuidString = uuid?.uuidString else { return nil }
        let sql = "SELECT * FROM \(SignalRecipientRecord.databaseTableName) WHERE \(signalRecipientColumn: .recipientUUID) = ?"
        return SignalRecipient.grdbFetchOne(sql: sql, arguments: [uuidString], transaction: transaction)
    }

    fileprivate func signalRecipientForPhoneNumber(_ phoneNumber: String?, transaction: GRDBReadTransaction) -> SignalRecipient? {
        guard let phoneNumber = phoneNumber else { return nil }
        let sql = "SELECT * FROM \(SignalRecipientRecord.databaseTableName) WHERE \(signalRecipientColumn: .recipientPhoneNumber) = ?"
        return SignalRecipient.grdbFetchOne(sql: sql, arguments: [phoneNumber], transaction: transaction)
    }

    func signalRecipients(for addresses: [SignalServiceAddress], transaction: GRDBReadTransaction) -> [SignalRecipient] {
        guard !addresses.isEmpty else { return [] }

        let phoneNumbersToLookup = addresses.compactMap { $0.phoneNumber }.map { "'\($0)'" }.joined(separator: ",")
        let uuidsToLookup = addresses.compactMap { $0.uuidString }.map { "'\($0)'" }.joined(separator: ",")

        let sql = """
            SELECT * FROM \(SignalRecipientRecord.databaseTableName)
            WHERE \(signalRecipientColumn: .recipientPhoneNumber) IN (\(phoneNumbersToLookup))
            OR \(signalRecipientColumn: .recipientUUID) IN (\(uuidsToLookup))
        """

        let cursor = SignalRecipient.grdbFetchCursor(sql: sql, transaction: transaction)

        var recipients = Set<SignalRecipient>()
        do {
            while let recipient = try cursor.next() {
                recipients.insert(recipient)
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }

        return Array(recipients)
    }

    fileprivate func registeredRecipientsWithoutUUID(transaction: GRDBReadTransaction) -> [SignalRecipient] {
        let sql = """
        SELECT * FROM \(SignalRecipientRecord.databaseTableName) WHERE
        \(signalRecipientColumn: .recipientUUID) IS NULL OR
        \(signalRecipientColumn: .recipientUUID) IS ""
        """
        let cursor = SignalRecipient.grdbFetchCursor(sql: sql, transaction: transaction)

        let allLegacyRecipients = try! cursor.all()
        return allLegacyRecipients.filter { $0.devices.count > 0 }
    }
}
