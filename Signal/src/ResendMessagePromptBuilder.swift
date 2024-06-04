//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

class ResendMessagePromptBuilder {
    private let databaseStorage: SDSDatabaseStorage
    private let messageSenderJobQueue: MessageSenderJobQueue

    init(databaseStorage: SDSDatabaseStorage, messageSenderJobQueue: MessageSenderJobQueue) {
        self.databaseStorage = databaseStorage
        self.messageSenderJobQueue = messageSenderJobQueue
    }

    func build(for message: TSOutgoingMessage) -> UIViewController {
        let sendAgain: () -> Void = { [databaseStorage, messageSenderJobQueue] in
            databaseStorage.write { tx in
                let latestMessage = TSOutgoingMessage.anyFetchOutgoingMessage(uniqueId: message.uniqueId, transaction: tx)
                guard let latestMessage, let latestThread = latestMessage.thread(tx: tx) else {
                    return
                }
                // If the message was remotely deleted, resend a *delete* message
                // rather than the message itself.
                let preparedMessage: PreparedOutgoingMessage
                if latestMessage.wasRemotelyDeleted {
                    let messageToSend = TSOutgoingDeleteMessage(thread: latestThread, message: latestMessage, transaction: tx)
                    preparedMessage = PreparedOutgoingMessage.preprepared(
                        transientMessageWithoutAttachments: messageToSend
                    )
                } else {
                    preparedMessage = PreparedOutgoingMessage.preprepared(
                        forResending: latestMessage,
                        messageRowId: latestMessage.sqliteRowId!
                    )
                }
                messageSenderJobQueue.add(message: preparedMessage, transaction: tx)
            }
        }

        let recipientsWithChangedSafetyNumber = message.failedRecipientAddresses(errorCode: UntrustedIdentityError.errorCode)
        guard recipientsWithChangedSafetyNumber.isEmpty else {
            // Show special safety number change dialog
            let confirmationSheet = SafetyNumberConfirmationSheet(
                addressesToConfirm: recipientsWithChangedSafetyNumber,
                confirmationText: MessageStrings.sendButton,
                completionHandler: { didConfirm in
                    if didConfirm {
                        sendAgain()
                    }
                }
            )
            return confirmationSheet
        }

        let actionSheet = ActionSheetController(title: nil, message: message.mostRecentFailureText)
        actionSheet.addAction(OWSActionSheets.cancelAction)
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.deleteForMeButton,
            style: .destructive,
            handler: { [databaseStorage] _ in
                databaseStorage.write { tx in
                    guard let freshInstance = TSInteraction.anyFetch(
                        uniqueId: message.uniqueId, transaction: tx
                    ) else { return }

                    DependenciesBridge.shared.interactionDeleteManager
                        .delete(freshInstance, sideEffects: .default(), tx: tx.asV2Write)
                }
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("SEND_AGAIN_BUTTON", comment: ""),
            accessibilityIdentifier: "send_again",
            style: .default,
            handler: { _ in sendAgain() }
        ))
        return actionSheet
    }
}
