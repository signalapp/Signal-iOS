//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Intents
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

public protocol RecipientHidingManager {

    // MARK: Read

    /// Returns set of all hidden recipients.
    ///
    /// - Parameter tx: The transaction to use for database operations.
    func hiddenRecipients(tx: DBReadTransaction) -> Set<SignalRecipient>

    /// Whether a recipient is hidden.
    ///
    /// - Parameter recipient: A ``SignalRecipient``.
    /// - Parameter tx: The transaction to use for database operations.
    ///
    /// - Returns: True if the recipient is hidden.
    func isHiddenRecipient(_ recipient: SignalRecipient, tx: DBReadTransaction) -> Bool

    // MARK: Write

    /// Adds a recipient to the hidden recipient table.
    ///
    /// - Parameter recipient: A ``SignalRecipient``.
    /// - Parameter wasLocallyInitiated: Whether the user initiated
    ///   the hide on this device (true) or a linked device (false).
    /// - Parameter tx: The transaction to use for database operations.
    func addHiddenRecipient(_ recipient: SignalRecipient, wasLocallyInitiated: Bool, tx: DBWriteTransaction) throws

    /// Removes a recipient from the hidden recipient table.
    ///
    /// - Parameter recipient: A ``SignalRecipient``.
    /// - Parameter wasLocallyInitiated: Whether the user initiated
    ///   the hide on this device (true) or a linked device (false).
    /// - Parameter tx: The transaction to use for database operations.
    func removeHiddenRecipient(_ recipient: SignalRecipient, wasLocallyInitiated: Bool, tx: DBWriteTransaction)
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
public final class RecipientHidingManagerImpl: RecipientHidingManager {

    private let profileManager: ProfileManagerProtocol
    private let storageServiceManager: StorageServiceManager
    private let tsAccountManager: TSAccountManager
    private let jobQueues: SSKJobQueues

    public init(
        profileManager: ProfileManagerProtocol,
        storageServiceManager: StorageServiceManager,
        tsAccountManager: TSAccountManager,
        jobQueues: SSKJobQueues
    ) {
        self.profileManager = profileManager
        self.storageServiceManager = storageServiceManager
        self.tsAccountManager = tsAccountManager
        self.jobQueues = jobQueues
    }

    public func hiddenRecipients(tx: DBReadTransaction) -> Set<SignalRecipient> {
        guard FeatureFlags.recipientHiding else {
            return Set()
        }
        do {
            let sql = """
                SELECT \(SignalRecipient.databaseTableName).*
                FROM \(SignalRecipient.databaseTableName)
                INNER JOIN \(HiddenRecipient.databaseTableName)
                    AS hiddenRecipient
                    ON hiddenRecipient.recipientId = \(signalRecipientColumn: .id)
            """
            return Set(
                try SignalRecipient.fetchAll(SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database, sql: sql)
            )
        } catch {
            Logger.warn("Could not fetch hidden recipient records.")
            return Set()
        }
    }

    public func isHiddenRecipient(_ recipient: SignalRecipient, tx: DBReadTransaction) -> Bool {
        guard FeatureFlags.recipientHiding, let id = recipient.id else {
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
            return try Bool.fetchOne(SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database, sql: sql, arguments: arguments) ?? false
        } catch {
            Logger.warn("Could not fetch hidden recipient record.")
            return false
        }
    }

    public func addHiddenRecipient(
        _ recipient: SignalRecipient,
        wasLocallyInitiated: Bool,
        tx: DBWriteTransaction
    ) throws {
        guard !isHiddenRecipient(recipient, tx: tx) else {
            // This is a perhaps extraneous safeguard against
            // hiding an already-hidden address. I say extraneous
            // because theoretically the UI should not be available to
            // hide an already-hidden recipient. However, we return here,
            // just in case, in order to avoid the side-effects of
            // `didSetAsHidden`.
            throw RecipientHidingError.recipientAlreadyHidden
        }
        if let id = recipient.id {
            let record = HiddenRecipient(recipientId: id)
            try record.save(SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database)
            didSetAsHidden(recipient: recipient, wasLocallyInitiated: wasLocallyInitiated, tx: tx)
        } else {
            throw RecipientHidingError.recipientIdNotFound
        }
    }

    public func removeHiddenRecipient(
        _ recipient: SignalRecipient,
        wasLocallyInitiated: Bool,
        tx: DBWriteTransaction
    ) {
        if let id = recipient.id, isHiddenRecipient(recipient, tx: tx) {
            let sql = """
                DELETE FROM \(HiddenRecipient.databaseTableName)
                WHERE \(HiddenRecipient.CodingKeys.recipientId.stringValue) = ?
            """
            SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.execute(sql: sql, arguments: [id])
            didSetAsUnhidden(recipient: recipient, wasLocallyInitiated: wasLocallyInitiated, tx: tx)
        }
    }
}

// MARK: - Recipient Hiding Callbacks

private extension RecipientHidingManagerImpl {
    /// Callback performing side effects of committing a hide
    /// to the database.
    ///
    /// - Parameter recipient: The ``SignalRecipient`` who was just hidden.
    /// - Parameter wasLocallyInitiated: Whether the user initiated
    ///   the hide on this device (true) or a linked device (false).
    /// - Parameter tx: The transaction to use for database operations.
    func didSetAsHidden(
        recipient: SignalRecipient,
        wasLocallyInitiated: Bool,
        tx: DBWriteTransaction
    ) {
        if let thread = TSContactThread.getWithContactAddress(
            recipient.address,
            transaction: SDSDB.shimOnlyBridge(tx)
        ) {
            let message = TSInfoMessage(thread: thread, messageType: .contactHidden)
            message.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))

            // Delete any send message intents.
            INInteraction.delete(with: thread.uniqueId, completion: nil)
        }

        /// TODO recipientHiding:
        /// - Throw out other user's profile key if not in group with user.
        if wasLocallyInitiated {
            profileManager.removeUser(
                fromProfileWhitelist: recipient.address,
                userProfileWriter: .storageService,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
            StoryManager.removeAddressFromAllPrivateStoryThreads(recipient.address, tx: SDSDB.shimOnlyBridge(tx))
            storageServiceManager.recordPendingUpdates(updatedAddresses: [recipient.address])
        }

        // Stories are always sent from an ACI. We will start dropping new stories
        // from the recipient; delete any existing ones we already have.
        if let aci = recipient.aci {
            StoryManager.deleteAllStories(forSender: aci, tx: SDSDB.shimOnlyBridge(tx))
        }

        if tsAccountManager.isPrimaryDevice(transaction: SDSDB.shimOnlyBridge(tx)) {
            // Profile key rotations should only be initiated by the primary device.
            self.profileManager.rotateProfileKeyUponRecipientHide(
                withTx: SDSDB.shimOnlyBridge(tx)
            )
        }
    }

    /// Callback performing side effects of removing a hide
    /// from the database.
    ///
    /// - Parameter recipient: The ``SignalRecipient`` who was just unhidden.
    /// - Parameter wasLocallyInitiated: Whether the user initiated
    ///   the hide on this device (true) or a linked device (false).
    /// - Parameter tx: The transaction to use for database operations.
    ///
    /// Note: If a ``SignalRecipient`` is deleted, a cascade
    /// rule is in place that will also delete the corresponding
    /// `HiddenRecipient` entry. This method does not get hit in
    /// that case.
    func didSetAsUnhidden(recipient: SignalRecipient, wasLocallyInitiated: Bool, tx: DBWriteTransaction) {
        if wasLocallyInitiated {
            profileManager.addUser(
                toProfileWhitelist: recipient.address,
                userProfileWriter: .storageService,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
            storageServiceManager.recordPendingUpdates(updatedAddresses: [recipient.address])
        }

        if
            let thread = TSContactThread.getWithContactAddress(
                recipient.address,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        {
            let profileKeyMessage = OWSProfileKeyMessage(
                thread: thread,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
            self.jobQueues.messageSenderJobQueue.add(
                message: profileKeyMessage.asPreparer,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        }
    }
}

/// Custom errors that can arise when attempting to hide a recipient.
public enum RecipientHidingError: Error, CustomStringConvertible {
    /// The recipient is already hidden. In theory, the UI should never
    /// allow for an already-hidden recipient to be hidden again, but
    /// never say never.
    case recipientAlreadyHidden
    /// The recipient did not have an id.
    case recipientIdNotFound
    /// The recipient's address was invalid.
    case invalidRecipientAddress(SignalServiceAddress)
    /// The recipient attempted to hide themselves (ie, Note to Self).
    /// In theory, this should not be possible in the UI.
    case cannotHideLocalAddress

    // MARK: CustomStringConvertible

    public var description: String {
        switch self {
        case .recipientAlreadyHidden:
            return "Recipient already hidden."
        case .recipientIdNotFound:
            return "Id of recipient to hide was not found."
        case .invalidRecipientAddress(let address):
            return "Address of recipient to hide was invalid: \(address)."
        case .cannotHideLocalAddress:
            return "Cannot hide local address."
        }
    }
}

// MARK: - Objc-Compat

@objc
public class RecipientHidingManagerObjcBridge: NSObject {

    @objc
    public static func isHiddenAddress(_ address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> Bool {
        return DependenciesBridge.shared.recipientHidingManager.isHiddenAddress(address, tx: tx.asV2Read)
    }
}
