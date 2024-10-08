//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Intents
public import GRDB

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

    /// Fetch the hidden-recipient state for the given `SignalRecipient`, if the
    /// `SignalRecipient` is currently hidden.
    func fetchHiddenRecipient(
        signalRecipient: SignalRecipient,
        tx: DBReadTransaction
    ) -> HiddenRecipient?

    /// Should the thread for the given hidden recipient be in a message-request
    /// state?
    ///
    /// - Parameter hiddenRecipient
    /// The hidden recipient in question.
    /// - Parameter contactThread
    /// The thread for our 1:1 conversation with the hidden recipient, if one
    /// has been created.
    func isHiddenRecipientThreadInMessageRequest(
        hiddenRecipient: HiddenRecipient,
        contactThread: TSContactThread?,
        tx: DBReadTransaction
    ) -> Bool

    // MARK: Write

    /// Inserts hidden-recipient state for the given `SignalRecipient`.
    ///
    /// - Parameter inKnownMessageRequestState
    /// Whether we know immediately that this hidden recipient's chat should be
    /// in a message-request state.
    /// - Parameter wasLocallyInitiated
    /// Whether this hide represents one initiated on this device, or one that
    /// occurred on a linked device.
    func addHiddenRecipient(
        _ recipient: SignalRecipient,
        inKnownMessageRequestState: Bool,
        wasLocallyInitiated: Bool,
        tx: DBWriteTransaction
    ) throws

    /// Removes a recipient from the hidden recipient table.
    ///
    /// - Parameter recipient: A ``SignalRecipient``.
    /// - Parameter wasLocallyInitiated: Whether the user initiated
    ///   the hide on this device (true) or a linked device (false).
    /// - Parameter tx: The transaction to use for database operations.
    func removeHiddenRecipient(
        _ recipient: SignalRecipient,
        wasLocallyInitiated: Bool,
        tx: DBWriteTransaction
    ) throws
}

public extension RecipientHidingManager {

    /// Whether the given `SignalRecipient` is currently hidden.
    func isHiddenRecipient(
        _ recipient: SignalRecipient,
        tx: DBReadTransaction
    ) -> Bool {
        return fetchHiddenRecipient(signalRecipient: recipient, tx: tx) != nil
    }
}

// MARK: - Record

/// A database record denoting a hidden ``SignalRecipient`` by their row ID.
/// Presence in the table means the recipient is hidden.
public struct HiddenRecipient: Codable, FetchableRecord, PersistableRecord {
    /// The name of the database where `HiddenRecipient`s are stored.
    public static let databaseTableName = "HiddenRecipient"

    public enum CodingKeys: String, CodingKey {
        case signalRecipientRowId = "recipientId"
        case inKnownMessageRequestState
    }

    /// The hidden recipient's ``SignalRecipient.id``.
    let signalRecipientRowId: Int64

    /// Whether this hidden recipient's chat is known to be in a message-request
    /// state.
    ///
    /// At the time of writing, this is only used when restoring a hidden
    /// contact from a Backup, which stores state on a contact indicating that
    /// they are both hidden and in a message-request state. Generally, the iOS
    /// app determines if a hidden recipient's chat should also be in a
    /// message-request state based on the most-recent message in the chat in
    /// conjunction with a sentinel "contact hidden" info message; however,
    /// since that info message isn't backed up (in favor of the aforementioned
    /// per-contact state) we store this extra bit during Backup restore as an
    /// alternate way to determine that state.
    ///
    /// - SeeAlso: ``RecipientHidingManager/isHiddenThreadInMessageRequest(contactThread:hiddenRecipient:tx:)``
    let inKnownMessageRequestState: Bool
}

// MARK: - Manager Impl

/// Manager in charge of reading from and writing to the `HiddenRecipient` table.
public final class RecipientHidingManagerImpl: RecipientHidingManager {

    private let profileManager: ProfileManager
    private let storageServiceManager: StorageServiceManager
    private let tsAccountManager: TSAccountManager
    private let messageSenderJobQueue: MessageSenderJobQueue

    @objc
    public static let hideListDidChange = Notification.Name("hideListDidChange")

    public init(
        profileManager: ProfileManager,
        storageServiceManager: StorageServiceManager,
        tsAccountManager: TSAccountManager,
        messageSenderJobQueue: MessageSenderJobQueue
    ) {
        self.profileManager = profileManager
        self.storageServiceManager = storageServiceManager
        self.tsAccountManager = tsAccountManager
        self.messageSenderJobQueue = messageSenderJobQueue
    }

    // MARK: -

    public func hiddenRecipients(tx: DBReadTransaction) -> Set<SignalRecipient> {
        do {
            let sql = """
                SELECT \(SignalRecipient.databaseTableName).*
                FROM \(SignalRecipient.databaseTableName)
                INNER JOIN \(HiddenRecipient.databaseTableName)
                    AS hiddenRecipient
                    ON hiddenRecipient.recipientId = \(signalRecipientColumn: .id)
            """
            return Set(
                try SignalRecipient.fetchAll(tx.databaseConnection, sql: sql)
            )
        } catch {
            Logger.warn("Could not fetch hidden recipient records: \(error.grdbErrorForLogging)")
            return Set()
        }
    }

    public func fetchHiddenRecipient(
        signalRecipient: SignalRecipient,
        tx: DBReadTransaction
    ) -> HiddenRecipient? {
        guard let signalRecipientRowId = signalRecipient.id else {
            return nil
        }

        let db = tx.databaseConnection

        do {
            return try HiddenRecipient.fetchOne(db, key: signalRecipientRowId)
        } catch {
            Logger.warn("Failed to fetch HiddenRecipient: \(error.grdbErrorForLogging)")
            return nil
        }
    }

    public func isHiddenRecipientThreadInMessageRequest(
        hiddenRecipient: HiddenRecipient,
        contactThread: TSContactThread?,
        tx: DBReadTransaction
    ) -> Bool {
        if hiddenRecipient.inKnownMessageRequestState {
            /// We know, immediately, that this thread should be in a
            /// message-request state.
            return true
        }

        guard let contactThread else {
            /// If we don't have a 1:1 thread with this recipient, it doesn't
            /// mean much to say that we're in a message-request state.
            ///
            /// This shouldn't happen in the normal app, since UX shouldn't
            /// allow us to hide someone without a `TSContactThread` created.
            /// However, it's plausible we'd restore a Backup from another
            /// platform with a hidden recipient but no corresponding chat.
            return false
        }

        guard
            let mostRecentInteraction = InteractionFinder(threadUniqueId: contactThread.uniqueId)
                .mostRecentInteraction(transaction: SDSDB.shimOnlyBridge(tx))
        else {
            /// Weird, because we should at least have a "contact hidden" info
            /// message. Not impossible, though, since we might have deleted the
            /// contents of this chat. If so, being in message-request would be
            /// confusing.
            return false
        }

        /// Broadly, we want to show message-request if the latest thing to have
        /// happened in the chat since the hiding is an incoming event. Below,
        /// we'll check for interactions that indicate an incoming event (that
        /// are possible in a contact thread).
        ///
        /// This works because when we hid the recipient we inserted a sentinel
        /// `TSInfoMessage`, and consequently won't show message-request state
        /// until we get an incoming interaction that's newer than that info
        /// message. (This logic breaks down if that info message is missing.)
        if mostRecentInteraction is TSIncomingMessage {
            return true
        } else if let individualCall = mostRecentInteraction as? TSCall {
            switch individualCall.callType {
            case
                    .incoming,
                    .incomingMissed,
                    .incomingIncomplete,
                    .incomingMissedBecauseOfChangedIdentity,
                    .incomingDeclined,
                    .incomingAnsweredElsewhere,
                    .incomingDeclinedElsewhere,
                    .incomingBusyElsewhere,
                    .incomingMissedBecauseOfDoNotDisturb,
                    .incomingMissedBecauseBlockedSystemContact:
                return true
            case
                    .outgoing,
                    .outgoingIncomplete,
                    .outgoingMissed:
                return false
            @unknown default:
                owsFailDebug("Unknown call type: \(individualCall.callType)")
                return false
            }
        } else {
            /// Anything else must not be "incoming", and so we do not want to
            /// show message-request.
            return false
        }
    }

    // MARK: -

    public func addHiddenRecipient(
        _ recipient: SignalRecipient,
        inKnownMessageRequestState: Bool,
        wasLocallyInitiated: Bool,
        tx: DBWriteTransaction
    ) throws {
        Logger.info("Hiding recipient")
        guard !isHiddenRecipient(recipient, tx: tx) else {
            // This is a perhaps extraneous safeguard against
            // hiding an already-hidden address. I say extraneous
            // because theoretically the UI should not be available to
            // hide an already-hidden recipient. However, we return here,
            // just in case, in order to avoid the side-effects of
            // `didSetAsHidden`.
            Logger.warn("Cannot hide already-hidden recipient.")
            throw RecipientHidingError.recipientAlreadyHidden
        }

        guard let signalRecipientRowId = recipient.id else {
            throw RecipientHidingError.recipientIdNotFound
        }

        let record = HiddenRecipient(
            signalRecipientRowId: signalRecipientRowId,
            inKnownMessageRequestState: inKnownMessageRequestState
        )
        try record.save(tx.databaseConnection)

        didSetAsHidden(recipient: recipient, wasLocallyInitiated: wasLocallyInitiated, tx: tx)
    }

    public func removeHiddenRecipient(
        _ recipient: SignalRecipient,
        wasLocallyInitiated: Bool,
        tx: DBWriteTransaction
    ) throws {
        if let id = recipient.id, isHiddenRecipient(recipient, tx: tx) {
            Logger.info("Unhiding recipient")
            let sql = """
                DELETE FROM \(HiddenRecipient.databaseTableName)
                WHERE \(HiddenRecipient.CodingKeys.signalRecipientRowId.stringValue) = ?
            """
            try tx.databaseConnection.execute(sql: sql, arguments: [id])
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
        // Triggers UI updates of recipient lists.
        NotificationCenter.default.postNotificationNameAsync(Self.hideListDidChange, object: nil)

        Logger.info("[Recipient hiding][side effects] Beginning side effects of setting as hidden.")
        if let thread = TSContactThread.getWithContactAddress(
            recipient.address,
            transaction: SDSDB.shimOnlyBridge(tx)
        ) {
            Logger.info("[Recipient hiding][side effects] Posting TSInfoMessage.")
            let infoMessage: TSInfoMessage = .makeForContactHidden(contactThread: thread)
            infoMessage.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))

            // Delete any send message intents.
            Logger.info("[Recipient hiding][side effects] Deleting INIntents.")
            INInteraction.delete(with: thread.uniqueId, completion: nil)
        }

        if wasLocallyInitiated {
            Logger.info("[Recipient hiding][side effects] Remove from whitelist.")
            profileManager.removeUser(
                fromProfileWhitelist: recipient.address,
                userProfileWriter: .localUser,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
            Logger.info("[Recipient hiding][side effects] Remove from story distribution lists.")
            StoryManager.removeAddressFromAllPrivateStoryThreads(recipient.address, tx: SDSDB.shimOnlyBridge(tx))
            Logger.info("[Recipient hiding][side effects] Sync with storage service.")
            storageServiceManager.recordPendingUpdates(updatedAddresses: [recipient.address])
        }

        // Stories are always sent from an ACI. We will start dropping new stories
        // from the recipient; delete any existing ones we already have.
        if let aci = recipient.aci {
            Logger.info("[Recipient hiding][side effects] Delete stories from removed user.")
            StoryManager.deleteAllStories(forSender: aci, tx: SDSDB.shimOnlyBridge(tx))
        }

        if
            tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice,
            let recipientServiceId = recipient.address.serviceId,
            let localAci = self.tsAccountManager.localIdentifiers(tx: tx)?.aci,
            !GroupManager.hasMutualGroupThread(
                with: recipientServiceId,
                localAci: localAci,
                tx: SDSDB.shimOnlyBridge(tx)
            )
        {
            // Profile key rotations should only be initiated by the primary device
            // when we have no common groups with the hidee (because mutual group
            // members are authorized to have profile keys of all group members).
            Logger.info("[Recipient hiding][side effects] Rotate profile key.")
            self.profileManager.rotateProfileKeyUponRecipientHide(
                withTx: SDSDB.shimOnlyBridge(tx)
            )
            // A nice-to-have was to throw out the other user's profile key if we're
            // not in a group with them. Product said this was not strictly necessary.
            // Note that this _is_ something that is done on Android, so there is a
            // slight lack of parity here.
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
        // Triggers UI updates of recipient lists.
        NotificationCenter.default.postNotificationNameAsync(Self.hideListDidChange, object: nil)

        Logger.info("[Recipient hiding][side effects] Beginning side effects of setting as unhidden.")
        if wasLocallyInitiated {
            Logger.info("[Recipient hiding][side effects] Add to whitelist.")
            profileManager.addUser(
                toProfileWhitelist: recipient.address,
                userProfileWriter: .localUser,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
            Logger.info("[Recipient hiding][side effects] Sync with storage service.")
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
            Logger.info("[Recipient hiding][side effects] Share profile key.")
            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: profileKeyMessage
            )
            self.messageSenderJobQueue.add(
                message: preparedMessage,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        }
    }
}

// MARK: -

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
