//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

public extension TSMessage {
    func presentDeletionActionSheet(from fromViewController: UIViewController) {
        let actionSheetController = ActionSheetController(message: OWSLocalizedString(
            "MESSAGE_ACTION_DELETE_FOR_TITLE",
            comment: "The title for the action sheet asking who the user wants to delete the message for."
        ))

        let deleteForMeAction = ActionSheetAction(
            title: CommonStrings.deleteForMeButton,
            style: .destructive
        ) { _ in
            Self.databaseStorage.asyncWrite { self.anyRemove(transaction: $0) }
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

                    self.databaseStorage.write { transaction in
                        let deleteMessage = TSOutgoingDeleteMessage(
                            thread: outgoingMessage.thread(transaction: transaction),
                            message: outgoingMessage,
                            transaction: transaction
                        )

                        // Reset the sending states, so we can render the sending state of the deleted message.
                        // TSOutgoingDeleteMessage will automatically pass through it's send state to the message
                        // record that it is deleting.
                        outgoingMessage.updateWith(recipientAddressStates: deleteMessage.recipientAddressStates, transaction: transaction)
                        outgoingMessage.updateWithRemotelyDeletedAndRemoveRenderableContent(with: transaction)
                        Self.messageSenderJobQueue.add(message: deleteMessage.asPreparer, transaction: transaction)
                    }
                }
            }
            actionSheetController.addAction(deleteForEveryoneAction)
        }

        actionSheetController.addAction(OWSActionSheets.cancelAction)

        fromViewController.presentActionSheet(actionSheetController)
    }

    private func showDeleteForEveryoneConfirmationIfNecessary(completion: @escaping () -> Void) {
        guard !Self.preferences.wasDeleteForEveryoneConfirmationShown() else { return completion() }

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
