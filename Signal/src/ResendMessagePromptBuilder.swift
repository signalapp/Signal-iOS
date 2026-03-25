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

    func build(for message: TSMessage, isTerminatedGroup: Bool) -> UIViewController {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        let sendAgain: () -> Void = { [databaseStorage, messageSenderJobQueue] in
            databaseStorage.write { tx in
                let latestMessage = TSMessage.fetchMessageViaCache(uniqueId: message.uniqueId, transaction: tx)
                guard let latestMessage, let latestThread = latestMessage.thread(tx: tx) else {
                    return
                }
                // If the message was remotely deleted, resend a *delete* message
                // rather than the message itself.
                let preparedMessage: PreparedOutgoingMessage
                if latestMessage.wasRemotelyDeleted {
                    let messageToSend: TransientOutgoingMessage
                    if let outgoingMessage = latestMessage as? TSOutgoingMessage {
                        messageToSend = OutgoingDeleteMessage(thread: latestThread, message: outgoingMessage, tx: tx)
                    } else if latestMessage.isIncoming {
                        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
                            return owsFailDebug("Local user not registered")
                        }
                        messageToSend = OutgoingAdminDeleteMessage(
                            thread: latestThread,
                            message: latestMessage,
                            localIdentifiers: localIdentifiers,
                            tx: tx,
                        )
                    } else {
                        return owsFailDebug("Message to resend is not incoming or outgoing")
                    }
                    preparedMessage = PreparedOutgoingMessage.preprepared(
                        transientMessageWithoutAttachments: messageToSend,
                    )
                } else if let outgoingMessage = latestMessage as? TSOutgoingMessage {
                    preparedMessage = PreparedOutgoingMessage.preprepared(
                        forResending: outgoingMessage,
                        messageRowId: outgoingMessage.sqliteRowId!,
                    )
                } else {
                    return owsFailDebug("Message to resend is not remotely deleted or outgoing")
                }
                messageSenderJobQueue.add(message: preparedMessage, transaction: tx)
            }
        }

        var recipientsWithChangedSafetyNumber: [SignalServiceAddress] = []
        if let outgoingMessage = message as? TSOutgoingMessage {
            recipientsWithChangedSafetyNumber = outgoingMessage.failedRecipientAddresses(errorCode: UntrustedIdentityError.errorCode)
        } else if message.isIncoming {
            if let recipientAddressStates = databaseStorage.read(block: { tx in AdminDeleteManager.recipientAddressStates(message: message, tx: tx) }) {
                recipientsWithChangedSafetyNumber = AdminDeleteManager.failedRecipientsWithErrorCode(UntrustedIdentityError.errorCode, recipientAddressStates: recipientAddressStates)
            }
        }

        guard recipientsWithChangedSafetyNumber.isEmpty else {
            // Show special safety number change dialog
            let confirmationSheet = SafetyNumberConfirmationSheet(
                addressesToConfirm: recipientsWithChangedSafetyNumber,
                confirmationText: MessageStrings.sendButton,
                completionHandler: { didConfirm in
                    if didConfirm {
                        sendAgain()
                    }
                },
            )
            return confirmationSheet
        }

        var mostRecentFailureText: String?
        if let outgoingMessage = message as? TSOutgoingMessage {
            mostRecentFailureText = outgoingMessage.mostRecentFailureText
        }

        if isTerminatedGroup {
            mostRecentFailureText = OWSLocalizedString(
                "GROUP_TERMINATED_MESSAGE_SEND_ERROR",
                comment: "Error indicating a send failure due to the group being terminated.",
            )
        }

        // TODO: [AdminDelete] message text for failed delete on incoming message
        // Since we don't have mostRecentFailureText, we will just show generic error text.

        let actionSheet = ActionSheetController(title: nil, message: mostRecentFailureText)
        actionSheet.addAction(OWSActionSheets.cancelAction)
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.deleteForMeButton,
            style: .destructive,
            handler: { [databaseStorage] _ in
                databaseStorage.write { tx in
                    guard
                        let freshInstance = TSInteraction.fetchViaCache(
                            uniqueId: message.uniqueId,
                            transaction: tx,
                        ) else { return }

                    DependenciesBridge.shared.interactionDeleteManager
                        .delete(freshInstance, sideEffects: .default(), tx: tx)
                }
            },
        ))
        if !isTerminatedGroup {
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString("SEND_AGAIN_BUTTON", comment: ""),
                style: .default,
                handler: { _ in sendAgain() },
            ))
        }
        return actionSheet
    }
}
