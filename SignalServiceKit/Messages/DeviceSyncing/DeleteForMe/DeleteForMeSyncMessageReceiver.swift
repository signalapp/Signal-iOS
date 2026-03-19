//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

protocol DeleteForMeSyncMessageReceiver {
    func handleDeleteForMeProto(
        deleteForMeProto: SSKProtoSyncMessageDeleteForMe,
        tx: DBWriteTransaction,
    )
}

/// Responsible for parsing an incoming `DeleteForMe` sync message and
/// delegating the delete-actions it contains.
final class DeleteForMeSyncMessageReceiverImpl: DeleteForMeSyncMessageReceiver {
    private typealias AttachmentIdentifier = DeleteForMeSyncMessage.Incoming.AttachmentIdentifier

    private let deleteForMeIncomingSyncMessageManager: DeleteForMeIncomingSyncMessageManager

    private let logger = PrefixedLogger(prefix: "[DeleteForMe]")

    init(
        deleteForMeIncomingSyncMessageManager: DeleteForMeIncomingSyncMessageManager,
    ) {
        self.deleteForMeIncomingSyncMessageManager = deleteForMeIncomingSyncMessageManager
    }

    // MARK: -

    func handleDeleteForMeProto(
        deleteForMeProto: SSKProtoSyncMessageDeleteForMe,
        tx: DBWriteTransaction,
    ) {
        for messageDeletes in deleteForMeProto.messageDeletes {
            guard
                let conversationIdentifierProto = messageDeletes.conversation,
                let conversationIdentifier = ConversationIdentifier(proto: conversationIdentifierProto)
            else {
                owsFailDebug("Missing conversation ID in message delete proto!")
                continue
            }

            let messages: [AddressableMessage] = messageDeletes.messages.compactMap { AddressableMessage(proto: $0) }
            owsAssertDebug(
                messages.count == messageDeletes.messages.count,
                "Invalid addressable messages in message delete proto: \(messageDeletes.messages.count - messages.count) / \(messageDeletes.messages.count)!",
            )

            for message in messages {
                deleteForMeIncomingSyncMessageManager.handleMessageDelete(
                    conversationIdentifier: conversationIdentifier,
                    addressableMessage: message,
                    tx: tx,
                )
            }
        }

        for attachmentDelete in deleteForMeProto.attachmentDeletes {
            guard
                let conversationIdentifierProto = attachmentDelete.conversation,
                let conversationIdentifier = ConversationIdentifier(proto: conversationIdentifierProto)
            else {
                owsFailDebug("Missing conversation ID in attachment delete proto!")
                continue
            }

            guard
                let targetMessageProto = attachmentDelete.targetMessage,
                let targetMessage = AddressableMessage(proto: targetMessageProto)
            else {
                owsFailDebug("Missing target message in attachment delete proto!")
                continue
            }

            let attachmentIdentifier = AttachmentIdentifier(
                clientUuid: attachmentDelete.clientUuid.flatMap { UUID(data: $0) },
                encryptedDigest: attachmentDelete.fallbackDigest,
                plaintextHash: attachmentDelete.fallbackPlaintextHash,
            )

            deleteForMeIncomingSyncMessageManager.handleAttachmentDelete(
                conversationIdentifier: conversationIdentifier,
                targetMessage: targetMessage,
                attachmentIdentifier: attachmentIdentifier,
                tx: tx,
            )
        }

        for conversationDelete in deleteForMeProto.conversationDeletes {
            guard
                let conversationIdentifierProto = conversationDelete.conversation,
                let conversationIdentifier = ConversationIdentifier(proto: conversationIdentifierProto)
            else {
                owsFailDebug("Missing conversation ID in conversation delete proto!")
                continue
            }

            let mostRecentMessages: [AddressableMessage] = conversationDelete.mostRecentMessages.compactMap { AddressableMessage(proto: $0) }
            owsAssertDebug(
                mostRecentMessages.count == conversationDelete.mostRecentMessages.count,
                "Invalid addressable messages in conversation delete proto: \(conversationDelete.mostRecentMessages.count - mostRecentMessages.count) / \(conversationDelete.mostRecentMessages.count)!",
            )

            let mostRecentNonExpiringMessages: [AddressableMessage] = conversationDelete.mostRecentNonExpiringMessages.compactMap { AddressableMessage(proto: $0) }
            owsAssertDebug(
                mostRecentNonExpiringMessages.count == conversationDelete.mostRecentNonExpiringMessages.count,
                "Invalid addressable messages in conversation delete proto: \(conversationDelete.mostRecentNonExpiringMessages.count - mostRecentNonExpiringMessages.count) / \(conversationDelete.mostRecentNonExpiringMessages.count)!",
            )

            guard conversationDelete.hasIsFullDelete else {
                owsFailDebug("Unset isFullDelete flag!")
                continue
            }

            deleteForMeIncomingSyncMessageManager.handleConversationDelete(
                conversationIdentifier: conversationIdentifier,
                mostRecentAddressableMessages: mostRecentMessages,
                mostRecentNonExpiringAddressableMessages: mostRecentNonExpiringMessages,
                isFullDelete: conversationDelete.isFullDelete,
                tx: tx,
            )
        }

        for localOnlyConversationDelete in deleteForMeProto.localOnlyConversationDeletes {
            guard
                let conversationIdentifierProto = localOnlyConversationDelete.conversation,
                let conversationIdentifier = ConversationIdentifier(proto: conversationIdentifierProto)
            else {
                owsFailDebug("Missing conversation ID in local-only conversation delete proto!")
                continue
            }

            deleteForMeIncomingSyncMessageManager.handleLocalOnlyConversationDelete(
                conversationIdentifier: conversationIdentifier,
                tx: tx,
            )
        }
    }

}
