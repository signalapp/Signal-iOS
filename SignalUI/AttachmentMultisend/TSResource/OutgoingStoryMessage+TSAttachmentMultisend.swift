//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension OutgoingStoryMessage {
    override class func prepareForMultisending(
        destinations: [MultisendDestination],
        state: MultisendState,
        transaction: SDSAnyWriteTransaction
    ) throws {
        var privateStoryMessageIds: [UUID: String] = [:]

        for destination in destinations {
            switch destination.content {
            case .media(let attachments):
                for identifiedAttachment in attachments {
                    let message: OutgoingStoryMessage
                    if destination.thread is TSPrivateStoryThread, let privateStoryMessageId = privateStoryMessageIds[identifiedAttachment.id] {
                        message = try OutgoingStoryMessage.createUnsentMessage(
                            thread: destination.thread,
                            storyMessageId: privateStoryMessageId,
                            transaction: transaction
                        )
                    } else {
                        let attachment = identifiedAttachment.value
                        let captionBody = state.approvalMessageBody?
                            .hydrating(mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: transaction.asV2Read))
                            .asStyleOnlyBody()
                        attachment.captionText = captionBody?.text
                        let dataSource = attachment.buildLegacyAttachmentDataSource()
                        let attachmentStreamId = try TSAttachmentManager().createAttachmentStream(
                            from: dataSource,
                            tx: transaction
                        )
                        let attachmentBuilder = OwnedAttachmentBuilder<StoryMessageAttachment>.withoutFinalizer(
                            .file(StoryMessageFileAttachment(
                                attachmentId: attachmentStreamId,
                                captionStyles: captionBody?.collapsedStyles ?? []
                            ))
                        )

                        var correspondingIdsForAttachment = state.correspondingAttachmentIds[identifiedAttachment.id] ?? []
                        correspondingIdsForAttachment += [attachmentStreamId]
                        state.correspondingAttachmentIds[identifiedAttachment.id] = correspondingIdsForAttachment

                        message = try OutgoingStoryMessage.createUnsentMessage(
                            thread: destination.thread,
                            attachmentBuilder: attachmentBuilder,
                            mediaCaption: captionBody,
                            shouldLoop: attachment.isLoopingVideo,
                            transaction: transaction
                        )
                        if destination.thread is TSPrivateStoryThread {
                            privateStoryMessageIds[identifiedAttachment.id] = message.storyMessageId
                        }
                    }

                    state.messages.append(PreparedOutgoingMessage.preprepared(
                        outgoingStoryMessage: message
                    ))
                    state.storyMessagesToSend.append(message)
                }

            case .text(let textAttachment):
                let message: OutgoingStoryMessage
                if destination.thread is TSPrivateStoryThread, let privateStoryMessageId = privateStoryMessageIds[textAttachment.id] {
                    message = try OutgoingStoryMessage.createUnsentMessage(
                        thread: destination.thread,
                        storyMessageId: privateStoryMessageId,
                        transaction: transaction
                    )
                } else {
                    guard
                        let textAttachmentBuilder = textAttachment.value
                            .validateLinkPreviewAndBuildTextAttachment(transaction: transaction)
                    else {
                        throw OWSAssertionError("Invalid text attachment")
                    }
                    if let linkPreviewAttachmentId = textAttachmentBuilder.info.preview?.legacyImageAttachmentId {
                        var correspondingIdsForAttachment = state.correspondingAttachmentIds[textAttachment.id] ?? []
                        correspondingIdsForAttachment += [linkPreviewAttachmentId]
                        state.correspondingAttachmentIds[textAttachment.id] = correspondingIdsForAttachment
                    }
                    message = try OutgoingStoryMessage.createUnsentMessage(
                        thread: destination.thread,
                        attachmentBuilder: textAttachmentBuilder.wrap { .text($0) },
                        mediaCaption: nil,
                        shouldLoop: false,
                        transaction: transaction
                    )
                    if destination.thread is TSPrivateStoryThread {
                        privateStoryMessageIds[textAttachment.id] = message.storyMessageId
                    }
                }

                state.messages.append(PreparedOutgoingMessage.preprepared(
                    outgoingStoryMessage: message
                ))
                state.storyMessagesToSend.append(message)
            }
        }

        OutgoingStoryMessage.dedupePrivateStoryRecipients(for: state.messages.lazy.compactMap(\.storyMessage), transaction: transaction)
    }

    public class func createUnsentMessage(
        thread: TSThread,
        attachmentBuilder: OwnedAttachmentBuilder<StoryMessageAttachment>,
        mediaCaption: StyleOnlyMessageBody?,
        shouldLoop: Bool,
        transaction: SDSAnyWriteTransaction
    ) throws -> OutgoingStoryMessage {
        let storyManifest: StoryManifest = .outgoing(
            recipientStates: try thread.recipientAddresses(with: transaction)
                .lazy
                .compactMap { $0.serviceId }
                .dictionaryMappingToValues { _ in
                    if let privateStoryThread = thread as? TSPrivateStoryThread {
                        guard let threadUuid = UUID(uuidString: privateStoryThread.uniqueId) else {
                            throw OWSAssertionError("Invalid uniqueId for thread \(privateStoryThread.uniqueId)")
                        }
                        return .init(allowsReplies: privateStoryThread.allowsReplies, contexts: [threadUuid])
                    } else {
                        return .init(allowsReplies: true, contexts: [])
                    }
                }
        )

        let storyMessage = try StoryMessage.createAndInsert(
            timestamp: Date.ows_millisecondTimestamp(),
            authorAci: DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aci,
            groupId: (thread as? TSGroupThread)?.groupId,
            manifest: storyManifest,
            replyCount: 0,
            attachmentBuilder: attachmentBuilder,
            mediaCaption: mediaCaption,
            shouldLoop: shouldLoop,
            transaction: transaction
        )

        thread.updateWithLastSentStoryTimestamp(NSNumber(value: storyMessage.timestamp), transaction: transaction)

        // If story sending for a group was implicitly enabled, explicitly enable it
        if let groupThread = thread as? TSGroupThread, !groupThread.isStorySendExplicitlyEnabled {
            groupThread.updateWithStorySendEnabled(true, transaction: transaction)
        }

        let outgoingMessage = OutgoingStoryMessage(
            thread: thread,
            storyMessage: storyMessage,
            storyMessageRowId: storyMessage.id!,
            transaction: transaction
        )
        return outgoingMessage
    }

    private class func createUnsentMessage(
        thread: TSThread,
        storyMessageId: String,
        transaction: SDSAnyWriteTransaction
    ) throws -> OutgoingStoryMessage {
        guard let privateStoryThread = thread as? TSPrivateStoryThread else {
            throw OWSAssertionError("Only private stories should share an existing story message context")
        }

        guard let threadUuid = UUID(uuidString: privateStoryThread.uniqueId) else {
            throw OWSAssertionError("Invalid uniqueId for thread \(privateStoryThread.uniqueId)")
        }

        guard let storyMessage = StoryMessage.anyFetch(uniqueId: storyMessageId, transaction: transaction),
                case .outgoing(var recipientStates) = storyMessage.manifest else {
            throw OWSAssertionError("Missing existing story message")
        }

        let recipientAddresses = Set(privateStoryThread.recipientAddresses(with: transaction))

        for address in recipientAddresses {
            guard let serviceId = address.serviceId else { continue }
            if var recipient = recipientStates[serviceId] {
                recipient.contexts.append(threadUuid)
                recipient.allowsReplies = recipient.allowsReplies || privateStoryThread.allowsReplies
                recipientStates[serviceId] = recipient
            } else {
                recipientStates[serviceId] = .init(allowsReplies: privateStoryThread.allowsReplies, contexts: [threadUuid])
            }
        }

        storyMessage.updateRecipientStates(recipientStates, transaction: transaction)

        privateStoryThread.updateWithLastSentStoryTimestamp(NSNumber(value: storyMessage.timestamp), transaction: transaction)

        // We skip the sync transcript for this message, since it's for
        // an already existing StoryMessage that has been sync'd to our
        // linked devices by another message.
        let outgoingMessage = OutgoingStoryMessage(
            thread: privateStoryThread,
            storyMessage: storyMessage,
            storyMessageRowId: storyMessage.id!,
            skipSyncTranscript: true,
            transaction: transaction
        )
        return outgoingMessage
    }
}
