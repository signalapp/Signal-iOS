//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit
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

        if
            let outgoingMessage = self as? TSOutgoingMessage,
            outgoingMessage.canBeRemotelyDeleted
        {
            let deleteForEveryoneAction = ActionSheetAction(
                title: CommonStrings.deleteForEveryoneButton,
                style: .destructive,
            ) { [weak self] _ in
                guard self != nil else { return }
                Self.showDeleteForEveryoneConfirmationIfNecessary {
                    SSKEnvironment.shared.databaseStorageRef.write { tx in
                        let latestMessage = TSOutgoingMessage.anyFetchOutgoingMessage(
                            uniqueId: outgoingMessage.uniqueId,
                            transaction: tx,
                        )
                        guard let latestMessage, let latestThread = latestMessage.thread(tx: tx) else {
                            // We can't reach this point in the UI if a message doesn't have a thread.
                            return owsFailDebug("Trying to delete a message without a thread.")
                        }
                        let deleteMessage = TSOutgoingDeleteMessage(
                            thread: latestThread,
                            message: latestMessage,
                            transaction: tx,
                        )
                        // Reset the sending states, so we can render the sending state of the deleted message.
                        // TSOutgoingDeleteMessage will automatically pass through it's send state to the message
                        // record that it is deleting.
                        latestMessage.updateWithRecipientAddressStates(deleteMessage.recipientAddressStates, tx: tx)

                        if let aci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aci {
                            _ = TSMessage.tryToRemotelyDeleteMessage(
                                fromAuthor: aci,
                                sentAtTimestamp: latestMessage.timestamp,
                                threadUniqueId: latestThread.uniqueId,
                                serverTimestamp: 0, // TSOutgoingMessage won't have server timestamp.
                                transaction: tx,
                            )
                        } else {
                            owsFailDebug("Local ACI missing during message deletion.")
                        }
                        let preparedMessage = PreparedOutgoingMessage.preprepared(
                            transientMessageWithoutAttachments: deleteMessage,
                        )

                        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
                    }
                }
            }
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
                    let freshSelf = TSInteraction.anyFetch(uniqueId: self.uniqueId, transaction: tx),
                    let freshThread = TSThread.anyFetch(uniqueId: thread.uniqueId, transaction: tx)
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
