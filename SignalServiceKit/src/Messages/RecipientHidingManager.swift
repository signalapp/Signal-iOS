//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

// Recipient hiding (also called "contact hiding," "contact management," or
// "contact removal/deletion" by Product) is a feature that allows users to
// remove a recipient from certain UI surfaces without fully blocking them.
// Namely, hidden recipients will not appear in the user's recipient picker
// lists, such when picking a person to whom to send a message. The hidden
// user can still send a message to the user who hid them, but it appears
// in the message request state. A hidden user becomes like someone with
// whom you've never exchanged messages before: this is the guiding principle
// behind how hidden users should be treated in the app.

// MARK: - Protocol

@objc
public protocol RecipientHidingManager: NSObjectProtocol {

    // MARK: Read

    /// Returns set of ``SignalServiceAddress``es corresponding with
    /// all hidden recipients.
    ///
    /// - Parameter tx: The transaction to use for database operations.
    func hiddenAddresses(tx: SDSAnyReadTransaction) -> Set<SignalServiceAddress>

    /// Whether a service address corresponds with a hidden recipient.
    ///
    /// - Parameter address: The service address corresponding with
    ///   the ``SignalRecipient``.
    /// - Parameter tx: The transaction to use for database operations.
    ///
    /// - Returns: True if the address is hidden.
    func isHiddenAddress(_ address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> Bool

    // MARK: Write

    /// Adds a recipient to the hidden recipient table.
    ///
    /// - Parameter address: The service address corresponding with
    ///   the ``SignalRecipient``.
    /// - Parameter wasLocallyInitiated: Whether the user initiated
    ///   the hide on this device (true) or a linked device (false).
    /// - Parameter tx: The transaction to use for database operations.
    func addHiddenRecipient(_ address: SignalServiceAddress, wasLocallyInitiated: Bool, tx: SDSAnyWriteTransaction) throws

    /// Removes a recipient from the hidden recipient table.
    ///
    /// - Parameter address: The service address corresponding with
    ///   the ``SignalRecipient``.
    /// - Parameter wasLocallyInitiated: Whether the user initiated
    ///   the hide on this device (true) or a linked device (false).
    /// - Parameter tx: The transaction to use for database operations.
    func removeHiddenRecipient(_ address: SignalServiceAddress, wasLocallyInitiated: Bool, tx: SDSAnyWriteTransaction)
}

// MARK: - Record

/// A database record denoting a hidden ``SignalRecipient`` by their row ID.
/// Presence in the table means the recipient is hidden.
struct HiddenRecipient: Codable, FetchableRecord, PersistableRecord {
    /// The name of the database where `HiddenRecipient`s are stored.
    public static let databaseTableName = "HiddenRecipient"

    public enum CodingKeys: String, CodingKey {
        /// The column name for the `recipientId`.
        case recipientId
    }

    /// The hidden recipient's ``SignalRecipient.id``.
    var recipientId: Int64
}

// MARK: - Manager Impl

/// Manager in charge of reading from and writing to the `HiddenRecipient` table.
@objc
public final class RecipientHidingManagerImpl: NSObject, RecipientHidingManager {
    @objc
    public func hiddenAddresses(tx: SDSAnyReadTransaction) -> Set<SignalServiceAddress> {
        do {
            let sql = """
                SELECT \(SignalRecipient.databaseTableName).*
                FROM \(SignalRecipient.databaseTableName)
                INNER JOIN \(HiddenRecipient.databaseTableName)
                    AS hiddenRecipient
                    ON hiddenRecipient.recipientId = \(signalRecipientColumn: .id)
            """
            return Set(
                try SignalRecipient.fetchAll(tx.unwrapGrdbRead.database, sql: sql).lazy
                    .map { $0.address }
                    .filter { $0.isValid }
            )
        } catch {
            Logger.warn("Could not fetch hidden recipient records.")
            return Set<SignalServiceAddress>()
        }
    }

    /// Returns the id for a recipient, if the recipient exists.
    ///
    /// - Parameter address: The service address corresponding with
    ///   the ``SignalRecipient``.
    /// - Parameter tx: The transaction to use for database operations.
    ///
    /// - Returns: The ``SignalRecipient``'s `id`.
    private func recipientId(from address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> Int64? {
        return SignalRecipient.fetchRecipient(for: address, onlyIfRegistered: false, tx: tx)?.id
    }

    @objc
    public func isHiddenAddress(_ address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> Bool {
        guard
            let localAddress = tsAccountManager.localAddress(with: tx),
            !localAddress.isEqualToAddress(address) else
        {
            return false
        }
        guard let id = recipientId(from: address, tx: tx) else {
            return false
        }
        do {
            let sql = """
            SELECT EXISTS(
                SELECT 1
                FROM \(HiddenRecipient.databaseTableName)
                WHERE \(HiddenRecipient.CodingKeys.recipientId.stringValue) = ?
                LIMIT 1
            )
            """
            let arguments: StatementArguments = [id]
            return try Bool.fetchOne(tx.unwrapGrdbRead.database, sql: sql, arguments: arguments) ?? false
        } catch {
            Logger.warn("Could not fetch hidden recipient record.")
            return false
        }
    }

    public func addHiddenRecipient(
        _ address: SignalServiceAddress,
        wasLocallyInitiated: Bool,
        tx: SDSAnyWriteTransaction
    ) throws {
        guard address.isValid else {
            owsFailDebug("Invalid address: \(address).")
            return
        }
        guard
            let localAddress = tsAccountManager.localAddress(with: tx),
            !localAddress.isEqualToAddress(address)
        else {
            owsFailDebug("Cannot hide the local address")
            return
        }
        if let id = OWSAccountIdFinder.ensureId(forAddress: address, transaction: tx) {
            let record = HiddenRecipient(recipientId: id)
            try record.save(tx.unwrapGrdbWrite.database)
            didSetAsHidden(address: address, tx: tx)
        } else {
            Logger.warn("Could not find id on recipient to hide.")
        }
    }

    public func removeHiddenRecipient(
        _ address: SignalServiceAddress,
        wasLocallyInitiated: Bool,
        tx: SDSAnyWriteTransaction
    ) {
        guard
            let localAddress = tsAccountManager.localAddress(with: tx),
            !localAddress.isEqualToAddress(address)
        else {
            owsFailDebug("Cannot unhide the local address")
            return
        }
        if let id = recipientId(from: address, tx: tx), isHiddenAddress(address, tx: tx) {
            let sql = """
                DELETE FROM \(HiddenRecipient.databaseTableName)
                WHERE \(HiddenRecipient.CodingKeys.recipientId.stringValue) = ?
            """
            tx.unwrapGrdbWrite.execute(sql: sql, arguments: [id])
            didSetAsUnhidden(address: address, tx: tx)
        }
    }
}

// MARK: - Recipient Hiding Callbacks

private extension RecipientHidingManager {
    /// Callback performing side effects of committing a hide
    /// to the database.
    ///
    /// - Parameter address: The service address corresponding
    ///   with the ``SignalRecipient`` who was just hidden.
    /// - Parameter wasLocallyInitiated: Whether the user initiated
    ///   the hide on this device (true) or a linked device (false).
    /// - Parameter tx: The transaction to use for database operations.
    ///
    /// TODO recipientHiding: utilize `wasLocallyInitiated`.
    func didSetAsHidden(
        address: SignalServiceAddress,
        wasLocallyInitiated: Bool = false,
        tx: SDSAnyWriteTransaction
    ) {
        if let thread = TSContactThread.getWithContactAddress(address, transaction: tx) {

            let message = TSInfoMessage(thread: thread, messageType: .contactHidden)
            message.anyInsert(transaction: tx)

            /// TODO recipientHiding:
            /// - Turn off read/delivery receipts.
            /// - Throw out other user's profile key if not in group with user.
            /// - Flush incoming/outgoing messages first.
            /// - Throw away existing Stories from hidden user.
            /// - If this is primary device, rotate own Profile Key if not in group with them.

            if wasLocallyInitiated {
                /// TODO recipientHiding:
                /// - Update ContactRecord in StorageService: hidden, whitelisted properties.
            }
        }
    }

    /// Callback performing side effects of removing a hide
    /// from the database.
    ///
    /// - Parameter address: The service address corresponding
    ///   with the ``SignalRecipient`` who was just unhidden.
    /// - Parameter tx: The transaction to use for database operations.
    ///
    /// Note: If a ``SignalRecipient`` is deleted, a cascade
    /// rule is in place that will also delete the corresponding
    /// `HiddenRecipient` entry. This method does not get hit in
    /// that case.
    func didSetAsUnhidden(address: SignalServiceAddress, tx: SDSAnyWriteTransaction) {
        SSKEnvironment.shared.profileManagerRef.addUser(toProfileWhitelist: address, userProfileWriter: .storageService, transaction: tx)
        SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedAddresses: [address])
    }
}

private extension OWSAccountIdFinder {
    /// Returns the `id` of a ``SignalRecipient``, creating
    /// a new recipient for the given service address if one
    /// does not exist already.
    ///
    /// - Parameter address: The service address for the
    ///   recipient we are looking up.
    /// - Parameter transaction: The transaction to use for
    ///   database operations.
    class func ensureId(
        forAddress address: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) -> Int64? {
        return OWSAccountIdFinder.ensureRecipient(forAddress: address, transaction: transaction).id
    }
}
