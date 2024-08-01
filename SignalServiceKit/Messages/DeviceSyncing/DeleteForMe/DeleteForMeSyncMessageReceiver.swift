//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

protocol DeleteForMeSyncMessageReceiver {
    func handleDeleteForMeProto(
        deleteForMeProto: SSKProtoSyncMessageDeleteForMe,
        tx: any DBWriteTransaction
    )
}

/// Responsible for parsing an incoming `DeleteForMe` sync message and
/// delegating the delete-actions it contains.
final class DeleteForMeSyncMessageReceiverImpl: DeleteForMeSyncMessageReceiver {
    private typealias Conversation = DeleteForMeSyncMessage.Incoming.Conversation
    private typealias AddressableMessage = DeleteForMeSyncMessage.Incoming.AddressableMessage
    private typealias AttachmentIdentifier = DeleteForMeSyncMessage.Incoming.AttachmentIdentifier

    private let deleteForMeIncomingSyncMessageManager: DeleteForMeIncomingSyncMessageManager
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let threadStore: ThreadStore
    private let tsAccountManager: TSAccountManager

    private let logger = PrefixedLogger(prefix: "[DeleteForMe]")

    init(
        deleteForMeIncomingSyncMessageManager: DeleteForMeIncomingSyncMessageManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        threadStore: ThreadStore,
        tsAccountManager: TSAccountManager
    ) {
        self.deleteForMeIncomingSyncMessageManager = deleteForMeIncomingSyncMessageManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.threadStore = threadStore
        self.tsAccountManager = tsAccountManager
    }

    // MARK: -

    func handleDeleteForMeProto(
        deleteForMeProto: SSKProtoSyncMessageDeleteForMe,
        tx: any DBWriteTransaction
    ) {
        for messageDeletes in deleteForMeProto.messageDeletes {
            guard let conversation = conversation(
                forProtoIdentifier: messageDeletes.conversation,
                tx: tx
            ) else {
                owsFailDebug("Missing conversation ID in message delete proto!")
                continue
            }

            let messages: [AddressableMessage] = addressableMessages(
                forProtoMessages: messageDeletes.messages,
                tx: tx
            )
            owsAssertDebug(
                messages.count == messageDeletes.messages.count,
                "Invalid addressable messages in message delete proto: \(messageDeletes.messages.count - messages.count) / \(messageDeletes.messages.count)!"
            )

            for message in messages {
                deleteForMeIncomingSyncMessageManager.handleMessageDelete(
                    conversation: conversation,
                    addressableMessage: message,
                    tx: tx
                )
            }
        }

        for attachmentDelete in deleteForMeProto.attachmentDeletes {
            guard let conversation = conversation(
                forProtoIdentifier: attachmentDelete.conversation,
                tx: tx
            ) else {
                owsFailDebug("Missing conversation ID in attachment delete proto!")
                continue
            }

            guard let targetMessage: AddressableMessage = addressableMessage(
                forProtoMessage: attachmentDelete.targetMessage,
                tx: tx
            ) else {
                owsFailDebug("Missing target message in attachment delete proto!")
                continue
            }

            let attachmentIdentifier = AttachmentIdentifier(
                clientUuid: attachmentDelete.clientUuid.flatMap { UUID(data: $0) },
                encryptedDigest: attachmentDelete.fallbackDigest,
                plaintextHash: attachmentDelete.fallbackPlaintextHash
            )

            deleteForMeIncomingSyncMessageManager.handleAttachmentDelete(
                conversation: conversation,
                targetMessage: targetMessage,
                attachmentIdentifier: attachmentIdentifier,
                tx: tx
            )
        }

        for conversationDelete in deleteForMeProto.conversationDeletes {
            guard let conversation = conversation(
                forProtoIdentifier: conversationDelete.conversation,
                tx: tx
            ) else {
                owsFailDebug("Missing conversation ID in conversation delete proto!")
                continue
            }

            let mostRecentMessages: [AddressableMessage] = addressableMessages(
                forProtoMessages: conversationDelete.mostRecentMessages,
                tx: tx
            )
            owsAssertDebug(
                mostRecentMessages.count == conversationDelete.mostRecentMessages.count,
                "Invalid addressable messages in conversation delete proto: \(conversationDelete.mostRecentMessages.count - mostRecentMessages.count) / \(conversationDelete.mostRecentMessages.count)!"
            )

            let mostRecentNonExpiringMessages: [AddressableMessage] = addressableMessages(
                forProtoMessages: conversationDelete.mostRecentNonExpiringMessages,
                tx: tx
            )
            owsAssertDebug(
                mostRecentNonExpiringMessages.count == conversationDelete.mostRecentNonExpiringMessages.count,
                "Invalid addressable messages in conversation delete proto: \(conversationDelete.mostRecentNonExpiringMessages.count - mostRecentNonExpiringMessages.count) / \(conversationDelete.mostRecentNonExpiringMessages.count)!"
            )

            guard conversationDelete.hasIsFullDelete else {
                owsFailDebug("Unset isFullDelete flag!")
                continue
            }

            deleteForMeIncomingSyncMessageManager.handleConversationDelete(
                conversation: conversation,
                mostRecentAddressableMessages: mostRecentMessages,
                mostRecentNonExpiringAddressableMessages: mostRecentNonExpiringMessages,
                isFullDelete: conversationDelete.isFullDelete,
                tx: tx
            )
        }

        for localOnlyConversationDelete in deleteForMeProto.localOnlyConversationDeletes {
            guard let conversation = conversation(
                forProtoIdentifier: localOnlyConversationDelete.conversation,
                tx: tx
            ) else {
                owsFailDebug("Missing conversation ID in local-only conversation delete proto!")
                continue
            }

            deleteForMeIncomingSyncMessageManager.handleLocalOnlyConversationDelete(
                conversation: conversation,
                tx: tx
            )
        }
    }

    // MARK: -

    private func conversation(
        forProtoIdentifier proto: SSKProtoSyncMessageDeleteForMeConversationIdentifier?,
        tx: DBReadTransaction
    ) -> Conversation? {
        guard let proto else { return nil }

        if
            let threadServiceId = proto.threadServiceID.flatMap({ try? ServiceId.parseFrom(serviceIdString: $0) })
        {
            if
                let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx),
                localIdentifiers.contains(serviceId: threadServiceId),
                let localThread = threadStore.fetchContactThreads(serviceId: threadServiceId, tx: tx).first
            {
                return .localUser(localThread)
            } else if
                let threadRecipient = recipientDatabaseTable.fetchRecipient(serviceId: threadServiceId, transaction: tx),
                let contactThread = threadStore.fetchContactThread(recipient: threadRecipient, tx: tx)
            {
                return .contact(contactThread)
            }
        } else if
            let threadE164 = proto.threadE164?.nilIfEmpty,
            let threadRecipient = recipientDatabaseTable.fetchRecipient(phoneNumber: threadE164, transaction: tx),
            let contactThread = threadStore.fetchContactThread(recipient: threadRecipient, tx: tx)
        {
            // We should only be deleting by E164 if we have no ACI. If we do,
            // something is up and we'll err on the side of not deleting.
            if threadRecipient.aci != nil {
                logger.warn("Received E164 conversation identifier, but we have an ACI for this thread. Skipping delete.")
                return nil
            }

            return .contact(contactThread)
        } else if
            let threadGroupId = proto.threadGroupID,
            let groupThread = threadStore.fetchGroupThread(groupId: threadGroupId, tx: tx)
        {
            return .group(groupThread)
        }

        return nil
    }

    private func addressableMessage(
        forProtoMessage proto: SSKProtoSyncMessageDeleteForMeAddressableMessage?,
        tx: DBReadTransaction
    ) -> AddressableMessage? {
        guard let proto else { return nil }

        return addressableMessages(forProtoMessages: [proto], tx: tx).first
    }

    private func addressableMessages(
        forProtoMessages protos: [SSKProtoSyncMessageDeleteForMeAddressableMessage],
        tx: DBReadTransaction
    ) -> [AddressableMessage] {
        return protos.compactMap { proto -> AddressableMessage? in
            guard proto.hasSentTimestamp, SDS.fitsInInt64(proto.sentTimestamp) else {
                return nil
            }

            let sentTimestamp = proto.sentTimestamp
            var author: AddressableMessage.Author?

            if let authorServiceId = proto.authorServiceID.flatMap({ try? ServiceId.parseFrom(serviceIdString: $0) }) {
                if
                    let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx),
                    localIdentifiers.contains(serviceId: authorServiceId)
                {
                    author = .localUser
                } else if let _author = recipientDatabaseTable.fetchRecipient(serviceId: authorServiceId, transaction: tx) {
                    author = .otherUser(_author)
                }
            } else if
                let authorE164 = proto.authorE164?.nilIfEmpty,
                let _author = recipientDatabaseTable.fetchRecipient(phoneNumber: authorE164, transaction: tx)
            {
                author = .otherUser(_author)
            }

            guard let author else { return nil }

            return AddressableMessage(
                author: author,
                sentTimestamp: sentTimestamp
            )
        }
    }
}
