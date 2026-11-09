//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import SignalServiceKit
import SignalUI

extension TSInteraction {
    func presentDeletionActionSheet(from fromViewController: UIViewController, forceDarkTheme: Bool = false) {
        let (
            associatedThread,
            hasLinkedDevices,
        ): (
            TSThread?,
            Bool,
        ) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return (
                thread(tx: tx),
                DependenciesBridge.shared.deviceStore.hasLinkedDevices(tx: tx),
            )
        }

        guard let associatedThread else { return }

        if associatedThread.isNoteToSelf {
            presentDeletionActionSheetForNoteToSelf(
                fromViewController: fromViewController,
                thread: associatedThread,
                hasLinkedDevices: hasLinkedDevices,
                forceDarkTheme: forceDarkTheme,
            )
        } else {
            presentDeletionActionSheetForNotNoteToSelf(
                fromViewController: fromViewController,
                thread: associatedThread,
                forceDarkTheme: forceDarkTheme,
            )
        }
    }

    private func presentDeletionActionSheetForNoteToSelf(
        fromViewController: UIViewController,
        thread: TSThread,
        hasLinkedDevices: Bool,
        forceDarkTheme: Bool,
    ) {
        let deleteMessageHeaderText = OWSLocalizedString(
            "DELETE_FOR_ME_NOTE_TO_SELF_ACTION_SHEET_HEADER",
            comment: "Header text for an action sheet confirming deleting a message in Note to Self.",
        )
        let deleteActionSheetButtonTitle = OWSLocalizedString(
            "DELETE_FOR_ME_NOTE_TO_SELF_ACTION_SHEET_BUTTON_TITLE",
            comment: "Title for an action sheet button explaining that a message will be deleted.",
        )
        let (title, message, deleteActionTitle): (String?, String, String) = if hasLinkedDevices {
            (
                deleteMessageHeaderText,
                OWSLocalizedString(
                    "DELETE_FOR_ME_NOTE_TO_SELF_LINKED_DEVICES_PRESENT_ACTION_SHEET_SUBHEADER",
                    comment: "Subheader for an action sheet explaining that a Note to Self deleted on this device will be deleted on the user's other devices as well.",
                ),
                deleteActionSheetButtonTitle,
            )
        } else {
            (
                nil,
                deleteMessageHeaderText,
                deleteActionSheetButtonTitle,
            )
        }

        let actionSheet = ActionSheetController(
            title: title,
            message: message,
        )
        if forceDarkTheme {
            actionSheet.overrideUserInterfaceStyle = .dark
        }
        actionSheet.addAction(deleteForMeAction(
            title: deleteActionTitle,
            thread: thread,
            fromViewController: fromViewController,
        ))
        actionSheet.addAction(.cancel)

        fromViewController.presentActionSheet(actionSheet)
    }

    private func presentDeletionActionSheetForNotNoteToSelf(
        fromViewController: UIViewController,
        thread: TSThread,
        forceDarkTheme: Bool,
    ) {
        let actionSheetController = ActionSheetController(
            message: OWSLocalizedString(
                "MESSAGE_ACTION_DELETE_FOR_TITLE",
                comment: "The title for the action sheet asking who the user wants to delete the message for.",
            ),
        )
        if forceDarkTheme {
            actionSheetController.overrideUserInterfaceStyle = .dark
        }

        actionSheetController.addAction(deleteForMeAction(
            title: CommonStrings.deleteForMeButton,
            thread: thread,
            fromViewController: fromViewController,
        ))

        if let deleteForEveryoneAction = buildDeleteForEveryoneAction(thread: thread) {
            actionSheetController.addAction(deleteForEveryoneAction)
        }

        actionSheetController.addAction(OWSActionSheets.cancelAction)

        fromViewController.presentActionSheet(actionSheetController)
    }

    // MARK: -

    private func deleteForMeAction(
        title: String,
        thread: TSThread,
        fromViewController: UIViewController,
    ) -> ActionSheetAction {
        let db = DependenciesBridge.shared.db
        let interactionDeleteManager = DependenciesBridge.shared.interactionDeleteManager

        return ActionSheetAction(
            title: CommonStrings.deleteForMeButton,
            style: .destructive,
        ) { [weak self, weak fromViewController] _ in
            guard let self else { return }

            let deletedForMeMessages = db.write { tx -> [DeletedForMeMessage]? in
                guard
                    let freshSelf = TSInteraction.fetchViaCache(uniqueId: self.uniqueId, transaction: tx),
                    let freshThread = TSThread.fetchViaCache(uniqueId: thread.uniqueId, transaction: tx)
                else { return nil }

                let deletedForMeMessages = Self.buildDeletedForMeMessages(
                    interactions: [freshSelf],
                    thread: freshThread,
                    tx: tx,
                )

                interactionDeleteManager.delete(
                    interactions: [freshSelf],
                    sideEffects: .custom(
                        deleteForMeSyncMessage: .sendSyncMessage(interactionsThread: freshThread),
                    ),
                    tx: tx,
                )

                return deletedForMeMessages
            }

            if let fromViewController {
                Self.presentDeletedForMeToast(
                    deletedForMeMessages: deletedForMeMessages,
                    thread: thread,
                    fromViewController: fromViewController,
                )
            }
        }
    }

    private func buildDeleteForEveryoneAction(thread: TSThread) -> ActionSheetAction? {
        let db = DependenciesBridge.shared.db
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        guard let message = self as? TSMessage else {
            return nil
        }

        let deleteType = db.read { tx -> TSMessage.DeleteForEveryoneType? in
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
                return nil
            }
            return message.deleteForEveryoneType(
                thread: thread,
                localIdentifiers: localIdentifiers,
                remoteConfig: RemoteConfig.current,
                now: Date(),
            )
        }
        guard let deleteType else {
            return nil
        }

        return ActionSheetAction(
            title: CommonStrings.deleteForEveryoneButton,
            style: .destructive,
        ) { _ in
            Self.showDeleteForEveryoneConfirmationIfNecessary(
                deleteTypes: [deleteType],
                completion: {
                    db.write { tx in
                        guard
                            let latestMessage = TSMessage.fetchMessageViaCache(
                                uniqueId: message.uniqueId,
                                transaction: tx,
                            )
                        else {
                            Logger.warn("User tried to delete a message that no longer exists")

                            guard let fromViewController = CurrentAppContext().frontmostViewController() else {
                                owsFailDebug("frontmostViewController was unexpectedly nil")
                                return
                            }

                            fromViewController.presentToast(
                                text: OWSLocalizedString(
                                    "REMOTE_DELETE_DISAPPEARED_MESSAGE_TOAST",
                                    comment: "Toast that appears when local user tried to delete a message that has disappeared",
                                ),
                            )
                            return
                        }
                        guard let latestThread = latestMessage.thread(tx: tx) else {
                            // We can't reach this point in the UI if a message doesn't have a thread.
                            return owsFailDebug("Trying to delete a message without a thread.")
                        }
                        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
                            return owsFailDebug("LocalIdentifiers missing during message deletion.")
                        }

                        _ = Self.deleteForEveryone(
                            message: latestMessage,
                            thread: latestThread,
                            localIdentifiers: localIdentifiers,
                            tx: tx,
                        )
                    }
                },
            )
        }
    }

    // MARK: -

    static func showDeleteForEveryoneConfirmationIfNecessary(
        deleteTypes: Set<TSMessage.DeleteForEveryoneType>,
        completion: @escaping () -> Void,
    ) {
        let adminDeleteManager = DependenciesBridge.shared.adminDeleteManager
        let db = DependenciesBridge.shared.db
        let preferences = SSKEnvironment.shared.preferencesRef

        let (
            shouldShowAdminDeleteConfirmation,
            shouldShowRegularDeleteConfirmation,
        ) = db.read { tx -> (Bool, Bool) in
            let shouldShowAdmin = deleteTypes.contains(.admin)
                && !adminDeleteManager.adminDeleteEducationReadStatus(tx: tx)
            let shouldShowRegular = deleteTypes.contains(.regular)
                && !preferences.wasDeleteForEveryoneConfirmationShown(tx: tx)
            return (shouldShowAdmin, shouldShowRegular)
        }

        guard shouldShowAdminDeleteConfirmation || shouldShowRegularDeleteConfirmation else { return completion() }

        let deleteType: TSMessage.DeleteForEveryoneType = shouldShowAdminDeleteConfirmation ? .admin : .regular
        showDeleteForEveryoneConfirmation(deleteType: deleteType) {
            switch deleteType {
            case .admin:
                db.write { tx in
                    adminDeleteManager.setAdminDeleteEducationRead(tx: tx, updateStorageService: true)
                }
            case .regular:
                preferences.setWasDeleteForEveryoneConfirmationShown()
            }
            completion()
        }
    }

    private static func showDeleteForEveryoneConfirmation(
        deleteType: TSMessage.DeleteForEveryoneType,
        onConfirm: @escaping () -> Void,
    ) {
        let message: String
        switch deleteType {
        case .admin:
            message = OWSLocalizedString(
                "DELETE_FOR_EVERYONE_CONFIRMATION_SHEET_ADMIN_MESSAGE",
                comment: "Message for a sheet confirming that the user, as a group admin, wants to delete messages for everyone.",
            )
        case .regular:
            message = OWSLocalizedString(
                "DELETE_FOR_EVERYONE_CONFIRMATION_SHEET_MESSAGE",
                comment: "Message for a sheet confirming that the user wants to delete their message for everyone.",
            )
        }

        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString(
                "DELETE_FOR_EVERYONE_CONFIRMATION_SHEET_TITLE",
                comment: "Title for a sheet confirming that the user wants to delete messages for everyone.",
            ),
            message: message,
            proceedTitle: CommonStrings.deleteForEveryoneButton,
            proceedStyle: .destructive,
        ) { _ in
            onConfirm()
        }
    }

    // MARK: -

    /// Deletes `message` for everyone, if the local user still may. Returns
    /// whether the delete was sent.
    static func deleteForEveryone(
        message: TSMessage,
        thread: TSThread,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) -> Bool {
        let adminDeleteManager = DependenciesBridge.shared.adminDeleteManager
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueueRef

        guard
            let deleteType = message.deleteForEveryoneType(
                thread: thread,
                localIdentifiers: localIdentifiers,
                remoteConfig: RemoteConfig.current,
                now: Date(),
            )
        else {
            Logger.warn("Message is no longer eligible for delete for everyone.")
            return false
        }

        let deleteMessage: TransientOutgoingMessage
        switch deleteType {
        case .regular:
            guard let outgoingMessage = message as? TSOutgoingMessage else {
                owsFailDebug("Regular delete for a non-outgoing message.")
                return false
            }
            deleteMessage = OutgoingDeleteMessage(thread: thread, message: outgoingMessage, tx: tx)

            do {
                try TSMessage.tryToRemotelyDeleteMessageAsNonAdmin(
                    fromAuthor: localIdentifiers.aci,
                    sentAtTimestamp: message.timestamp,
                    threadUniqueId: thread.uniqueId,
                    serverTimestamp: 0, // TSOutgoingMessage won't have server timestamp.
                    transaction: tx,
                )
            } catch {
                owsFailDebug("Unable to remotely delete message")
                return false
            }
        case .admin:
            guard let groupThread = thread as? TSGroupThread else {
                owsFailDebug("Admin delete outside a group.")
                return false
            }
            let originalMessageAuthorAci: Aci?
            if let incomingMessage = message as? TSIncomingMessage {
                originalMessageAuthorAci = incomingMessage.authorAddress.aci
            } else {
                originalMessageAuthorAci = localIdentifiers.aci
            }
            guard let originalMessageAuthorAci else {
                owsFailDebug("Unable to admin delete without original message author")
                return false
            }

            deleteMessage = OutgoingAdminDeleteMessage(
                thread: thread,
                message: message,
                localIdentifiers: localIdentifiers,
                tx: tx,
            )

            do {
                try adminDeleteManager.tryToAdminDeleteMessage(
                    originalMessageAuthorAci: originalMessageAuthorAci,
                    deleteAuthorAci: localIdentifiers.aci,
                    sentAtTimestamp: message.timestamp,
                    groupThread: groupThread,
                    threadUniqueId: thread.uniqueId,
                    serverTimestamp: 0, // TSOutgoingMessage won't have server timestamp.
                    transaction: tx,
                )
            } catch {
                owsFailDebug("Unable to remotely delete message")
                return false
            }
        }

        // Reset the sending states, so we can render the sending state of the
        // deleted message. The delete message passes its send state through to
        // the message it deletes.
        // TODO: support sending state animation for incoming messages.
        (message as? TSOutgoingMessage)?.updateWithRecipientAddressStates(deleteMessage.recipientAddressStates, tx: tx)

        messageSenderJobQueue.add(
            message: PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: deleteMessage,
            ),
            transaction: tx,
        )
        return true
    }

    // MARK: -

    /// Snapshots `interactions`, which are about to be deleted for the local
    /// user, if they could all instead be deleted for everyone.
    static func buildDeletedForMeMessages(
        interactions: [TSInteraction],
        thread: TSThread,
        tx: DBReadTransaction,
    ) -> [DeletedForMeMessage]? {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        guard
            BuildFlags.deleteForMeToast,
            let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)
        else {
            return nil
        }

        let now = Date()
        var deletedForMeMessages = [DeletedForMeMessage]()
        for interaction in interactions {
            guard
                let message = interaction as? TSOutgoingMessage,
                let rowId = message.sqliteRowId
            else {
                return nil
            }

            switch message.deleteForEveryoneType(
                thread: thread,
                localIdentifiers: localIdentifiers,
                remoteConfig: RemoteConfig.current,
                now: now,
            ) {
            case .regular:
                break
            case .admin, nil:
                return nil
            }

            deletedForMeMessages.append(DeletedForMeMessage(
                rowId: rowId,
                uniqueId: message.uniqueId,
                timestamp: message.timestamp,
                receivedAtTimestamp: message.receivedAtTimestamp,
                expiresInSeconds: message.expiresInSeconds,
                expireStartedAt: message.expireStartedAt,
                storyAuthorAci: message.storyAuthorAci?.wrappedAciValue,
                storyTimestamp: message.storyTimestamp?.uint64Value,
            ))
        }
        return deletedForMeMessages
    }

    /// - Parameter deletedForMeMessages: If present, the toast offers to
    /// delete them for everyone.
    static func presentDeletedForMeToast(
        deletedForMeMessages: [DeletedForMeMessage]?,
        thread: TSThread,
        fromViewController: UIViewController,
    ) {
        guard BuildFlags.deleteForMeToast, !thread.isNoteToSelf else {
            return
        }

        let text = OWSLocalizedString(
            "DELETED_FOR_ME_TOAST_TEXT",
            comment: "Text for a toast shown after the user deletes messages for themselves only.",
        )
        let button = deletedForMeMessages.map { deletedForMeMessages in
            ToastController.Button(
                title: OWSLocalizedString(
                    "DELETED_FOR_ME_TOAST_DELETE_FOR_EVERYONE_BUTTON_TITLE",
                    comment: "Title for a button in a toast shown after the user deletes messages for themselves only.",
                ),
                onPrimaryAction: {
                    Self.deleteForEveryone(
                        deletedForMeMessages: deletedForMeMessages,
                        threadUniqueId: thread.uniqueId,
                    )
                },
            )
        }

        if let conversationViewController = fromViewController as? ConversationViewController {
            conversationViewController.presentToastCVC(text, button: button)
        } else {
            fromViewController.presentToast(text: text, button: button)
        }
    }

    private static func deleteForEveryone(
        deletedForMeMessages: [DeletedForMeMessage],
        threadUniqueId: String,
    ) {
        let db = DependenciesBridge.shared.db

        showDeleteForEveryoneConfirmation(
            deleteType: .regular,
            onConfirm: {
                db.write { tx in
                    guard let thread = TSThread.fetchViaCache(uniqueId: threadUniqueId, transaction: tx) else {
                        owsFailDebug("Missing thread.")
                        return
                    }
                    for deletedForMeMessage in deletedForMeMessages {
                        Self.enqueueDeleteForEveryone(
                            deletedForMeMessage: deletedForMeMessage,
                            thread: thread,
                            tx: tx,
                        )
                    }
                }
            },
        )
    }

    private static func enqueueDeleteForEveryone(
        deletedForMeMessage: DeletedForMeMessage,
        thread: TSThread,
        tx: DBWriteTransaction,
    ) {
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueueRef

        let message = insertRemotelyDeletedMessage(
            deletedForMeMessage: deletedForMeMessage,
            thread: thread,
            tx: tx,
        )

        let deleteMessage = OutgoingDeleteMessage(thread: thread, message: message, tx: tx)
        message.updateWithRecipientAddressStates(deleteMessage.recipientAddressStates, tx: tx)

        messageSenderJobQueue.add(
            message: PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: deleteMessage,
            ),
            transaction: tx,
        )
    }

    /// Restores `deletedForMeMessage` in its original row, as if it had been
    /// deleted for everyone.
    static func insertRemotelyDeletedMessage(
        deletedForMeMessage: DeletedForMeMessage,
        thread: TSThread,
        tx: DBWriteTransaction,
    ) -> TSOutgoingMessage {
        let disappearingMessagesExpirationJob = DependenciesBridge.shared.disappearingMessagesExpirationJob

        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            timestamp: deletedForMeMessage.timestamp,
            receivedAtTimestamp: deletedForMeMessage.receivedAtTimestamp,
            expiresInSeconds: deletedForMeMessage.expiresInSeconds,
            expireStartedAt: deletedForMeMessage.expireStartedAt,
            wasRemotelyDeleted: true,
            storyAuthorAci: deletedForMeMessage.storyAuthorAci,
            storyTimestamp: deletedForMeMessage.storyTimestamp,
        )
        let message = TSOutgoingMessage(
            outgoingMessageWith: builder,
            recipientAddressStates: [:],
        )
        message.replaceRowId(deletedForMeMessage.rowId, uniqueId: deletedForMeMessage.uniqueId)
        message.replaceSortId(UInt64(deletedForMeMessage.rowId))

        // Insert directly, avoiding insert side effects (e.g., unarchiving the
        // thread). This message replaces the one deleted from this row, so
        // treat it as an update instead.
        message.anyWillUpdate(with: tx)
        failIfThrows {
            try message.asRecord().insert(tx.database)
        }
        message.anyDidUpdate(with: tx)

        if deletedForMeMessage.expireStartedAt > 0 {
            tx.addSyncCompletion {
                disappearingMessagesExpirationJob.restart()
            }
        }

        return message
    }
}

// MARK: -

/// An outgoing message that was deleted for the local user, but which could
/// still be deleted for everyone.
struct DeletedForMeMessage {
    let rowId: Int64
    let uniqueId: String

    let timestamp: UInt64
    let receivedAtTimestamp: UInt64

    let expiresInSeconds: UInt32
    let expireStartedAt: UInt64

    let storyAuthorAci: Aci?
    let storyTimestamp: UInt64?
}

// MARK: -

extension CommonStrings {
    static var deleteForEveryoneButton: String {
        OWSLocalizedString(
            "MESSAGE_ACTION_DELETE_FOR_EVERYONE",
            comment: "The title for the action that deletes a message for all users in the conversation.",
        )
    }
}
