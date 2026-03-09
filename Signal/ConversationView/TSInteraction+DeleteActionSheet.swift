//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit
import LibSignalClient
import SignalUI
import UIKit

public extension TSInteraction {
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
        ))
        actionSheet.addAction(.cancel)

        fromViewController.presentActionSheet(actionSheet)
    }

    /// If the local user is an admin, we prefer regular remote delete. We only fallback to
    /// admin delete if the remote delete timeframe has expired and admin delete timeframe has not.
    class func buildDeleteMessage(
        thread: TSThread,
        message: TSMessage,
        localIdentifiers: LocalIdentifiers,
        canAdminDelete: Bool,
        tx: DBReadTransaction,
    ) -> TransientOutgoingMessage? {
        if
            message.canBeRemotelyDeletedByNonAdmin,
            let outgoingMessage = message as? TSOutgoingMessage
        {
            return OutgoingDeleteMessage(thread: thread, message: outgoingMessage, tx: tx)
        }

        guard canAdminDelete else {
            owsFailDebug("Unable to admin-delete incoming message")
            return nil
        }

        return OutgoingAdminDeleteMessage(
            thread: thread,
            message: message,
            localIdentifiers: localIdentifiers,
            tx: tx,
        )
    }

    private func buildDeleteForEveryoneAction(thread: TSThread) -> ActionSheetAction? {
        let adminDeleteManager = DependenciesBridge.shared.adminDeleteManager
        let db = DependenciesBridge.shared.db

        guard let message = self as? TSMessage else {
            return nil
        }

        let canAdminDelete = db.read { tx in adminDeleteManager.canAdminDeleteMessage(message: message, thread: thread, tx: tx) }
        if message.canBeRemotelyDeletedByNonAdmin || canAdminDelete {
            return ActionSheetAction(
                title: CommonStrings.deleteForEveryoneButton,
                style: .destructive,
            ) { [weak self] _ in
                guard self != nil else { return }
                Self.showDeleteForEveryoneConfirmationIfNecessary {
                    SSKEnvironment.shared.databaseStorageRef.write { tx in
                        let latestMessage = TSMessage.fetchMessageViaCache(
                            uniqueId: message.uniqueId,
                            transaction: tx,
                        )
                        guard let latestMessage else {
                            ToastViewHelper.presentToastOnFrontmostViewController(
                                text: OWSLocalizedString(
                                    "REMOTE_DELETE_DISAPPEARED_MESSAGE_TOAST",
                                    comment: "Toast that appears when local user tried to delete a message that has disappeared",
                                ),
                            )
                            Logger.warn("User tried to delete a message that no longer exists")
                            return
                        }

                        guard let latestThread = latestMessage.thread(tx: tx) else {
                            // We can't reach this point in the UI if a message doesn't have a thread.
                            return owsFailDebug("Trying to delete a message without a thread.")
                        }
                        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx) else {
                            return owsFailDebug("LocalIdentifiers missing during message deletion.")
                        }

                        guard
                            let deleteMessage = Self.buildDeleteMessage(
                                thread: latestThread,
                                message: latestMessage,
                                localIdentifiers: localIdentifiers,
                                canAdminDelete: canAdminDelete,
                                tx: tx,
                            )
                        else {
                            return owsFailDebug("Failure to build outgoing delete for everyone.")
                        }
                        // Reset the sending states, so we can render the sending state of the
                        // deleted message. OutgoingDeleteMessage will automatically pass through
                        // it's send state to the message record that it is deleting.
                        // TODO: support sending state animation for incoming messages.
                        (latestMessage as? TSOutgoingMessage)?.updateWithRecipientAddressStates(deleteMessage.recipientAddressStates, tx: tx)

                        if message.canBeRemotelyDeletedByNonAdmin {
                            do {
                                try TSMessage.tryToRemotelyDeleteMessageAsNonAdmin(
                                    fromAuthor: localIdentifiers.aci,
                                    sentAtTimestamp: latestMessage.timestamp,
                                    threadUniqueId: latestThread.uniqueId,
                                    serverTimestamp: 0, // TSOutgoingMessage won't have server timestamp.
                                    transaction: tx,
                                )
                            } catch {
                                return owsFailDebug("Unable to remotely delete message")
                            }
                        } else if
                            canAdminDelete,
                            let groupThread = thread as? TSGroupThread
                        {
                            let originalMessageAuthorAci: Aci?
                            if let incomingMessage = (latestMessage as? TSIncomingMessage) {
                                originalMessageAuthorAci = incomingMessage.authorAddress.aci
                            } else {
                                originalMessageAuthorAci = localIdentifiers.aci
                            }

                            guard let originalMessageAuthorAci else {
                                owsFailDebug("Unable to admin delete without original message author")
                                return
                            }

                            do {
                                try DependenciesBridge.shared.adminDeleteManager.tryToAdminDeleteMessage(
                                    originalMessageAuthorAci: originalMessageAuthorAci,
                                    deleteAuthorAci: localIdentifiers.aci,
                                    sentAtTimestamp: latestMessage.timestamp,
                                    groupThread: groupThread,
                                    threadUniqueId: latestThread.uniqueId,
                                    serverTimestamp: 0, // TSOutgoingMessage won't have server timestamp.
                                    transaction: tx,
                                )
                            } catch {
                                return owsFailDebug("Unable to remotely delete message")
                            }
                        } else {
                            owsFailDebug("Unable to delete as admin or as non-admin")
                            return
                        }

                        let preparedMessage = PreparedOutgoingMessage.preprepared(
                            transientMessageWithoutAttachments: deleteMessage,
                        )

                        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
                    }
                }
            }
        }
        return nil
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
        ))

        if let deleteForEveryoneAction = buildDeleteForEveryoneAction(thread: thread) {
            actionSheetController.addAction(deleteForEveryoneAction)
        }

        actionSheetController.addAction(OWSActionSheets.cancelAction)

        fromViewController.presentActionSheet(actionSheetController)
    }

    static func showDeleteForEveryoneConfirmationIfNecessary(completion: @escaping () -> Void) {
        guard !SSKEnvironment.shared.preferencesRef.wasDeleteForEveryoneConfirmationShown else { return completion() }

        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString(
                "MESSAGE_ACTION_DELETE_FOR_EVERYONE_CONFIRMATION",
                comment: "A one-time confirmation that you want to delete for everyone",
            ),
            proceedTitle: CommonStrings.deleteForEveryoneButton,
            proceedStyle: .destructive,
        ) { _ in
            SSKEnvironment.shared.preferencesRef.setWasDeleteForEveryoneConfirmationShown()
            completion()
        }
    }

    private func deleteForMeAction(
        title: String,
        thread: TSThread,
    ) -> ActionSheetAction {
        let db = DependenciesBridge.shared.db
        let interactionDeleteManager = DependenciesBridge.shared.interactionDeleteManager

        return ActionSheetAction(
            title: CommonStrings.deleteForMeButton,
            style: .destructive,
        ) { [weak self] _ in
            guard let self else { return }

            db.asyncWrite { tx in
                guard
                    let freshSelf = TSInteraction.fetchViaCache(uniqueId: self.uniqueId, transaction: tx),
                    let freshThread = TSThread.fetchViaCache(uniqueId: thread.uniqueId, transaction: tx)
                else { return }

                interactionDeleteManager.delete(
                    interactions: [freshSelf],
                    sideEffects: .custom(
                        deleteForMeSyncMessage: .sendSyncMessage(interactionsThread: freshThread),
                    ),
                    tx: tx,
                )
            }
        }
    }
}

extension CommonStrings {
    public static var deleteForEveryoneButton: String {
        OWSLocalizedString(
            "MESSAGE_ACTION_DELETE_FOR_EVERYONE",
            comment: "The title for the action that deletes a message for all users in the conversation.",
        )
    }
}
