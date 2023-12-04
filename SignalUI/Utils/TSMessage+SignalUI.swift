//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import UIKit

public extension TSMessage {
    func presentDeletionActionSheet(from fromViewController: UIViewController, forceDarkTheme: Bool = false) {
        let actionSheetController = ActionSheetController(
            message: OWSLocalizedString(
                "MESSAGE_ACTION_DELETE_FOR_TITLE",
                comment: "The title for the action sheet asking who the user wants to delete the message for."
            ),
            theme: forceDarkTheme ? .translucentDark : .default
        )

        let deleteForMeAction = ActionSheetAction(
            title: CommonStrings.deleteForMeButton,
            style: .destructive
        ) { _ in
            Self.databaseStorage.asyncWrite { tx in
                TSMessage.anyFetchMessage(uniqueId: self.uniqueId, transaction: tx)?.anyRemove(transaction: tx)
            }
        }
        actionSheetController.addAction(deleteForMeAction)

        if canBeRemotelyDeleted, let outgoingMessage = self as? TSOutgoingMessage {
            let deleteForEveryoneAction = ActionSheetAction(
                title: OWSLocalizedString(
                    "MESSAGE_ACTION_DELETE_FOR_EVERYONE",
                    comment: "The title for the action that deletes a message for all users in the conversation."
                ),
                style: .destructive
            ) { [weak self] _ in
                self?.showDeleteForEveryoneConfirmationIfNecessary {
                    guard let self = self else { return }

                    self.databaseStorage.write { tx in
                        let latestMessage = TSOutgoingMessage.anyFetchOutgoingMessage(
                            uniqueId: outgoingMessage.uniqueId,
                            transaction: tx
                        )
                        guard let latestMessage, let latestThread = latestMessage.thread(tx: tx) else {
                            // We can't reach this point in the UI if a message doesn't have a thread.
                            return owsFailDebug("Trying to delete a message without a thread.")
                        }
                        let deleteMessage = TSOutgoingDeleteMessage(
                            thread: latestThread,
                            message: latestMessage,
                            transaction: tx
                        )
                        // Reset the sending states, so we can render the sending state of the deleted message.
                        // TSOutgoingDeleteMessage will automatically pass through it's send state to the message
                        // record that it is deleting.
                        latestMessage.updateWith(recipientAddressStates: deleteMessage.recipientAddressStates, transaction: tx)

                        if let aci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci {
                            _ = TSMessage.tryToRemotelyDeleteMessage(
                                fromAuthor: aci,
                                sentAtTimestamp: latestMessage.timestamp,
                                threadUniqueId: latestThread.uniqueId,
                                serverTimestamp: 0, // TSOutgoingMessage won't have server timestamp.
                                transaction: tx
                            )
                        } else {
                            owsFailDebug("Local ACI missing during message deletion.")
                        }

                        Self.sskJobQueues.messageSenderJobQueue.add(message: deleteMessage.asPreparer, transaction: tx)
                    }
                }
            }
            actionSheetController.addAction(deleteForEveryoneAction)
        }

        actionSheetController.addAction(OWSActionSheets.cancelAction)

        fromViewController.presentActionSheet(actionSheetController)
    }

    private func showDeleteForEveryoneConfirmationIfNecessary(completion: @escaping () -> Void) {
        guard !Self.preferences.wasDeleteForEveryoneConfirmationShown else { return completion() }

        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString(
                "MESSAGE_ACTION_DELETE_FOR_EVERYONE_CONFIRMATION",
                comment: "A one-time confirmation that you want to delete for everyone"
            ),
            proceedTitle: OWSLocalizedString(
                "MESSAGE_ACTION_DELETE_FOR_EVERYONE",
                comment: "The title for the action that deletes a message for all users in the conversation."
            ),
            proceedStyle: .destructive) { _ in
            Self.preferences.setWasDeleteForEveryoneConfirmationShown()
            completion()
        }
    }
}
