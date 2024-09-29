//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

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
                            .buildTextAttachment(transaction: transaction)
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
            timestamp: MessageTimestampGenerator.sharedInstance.generateTimestamp(),
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

    /// When sending to private stories, each private story list may have overlap in recipients. We want to
    /// dedupe sends such that we only send one copy of a given story to each recipient even though they
    /// are represented in multiple targeted lists.
    ///
    /// Additionally, each private story has different levels of permissions. Some may allow replies & reactions
    /// while others do not. Since we convey to the recipient if this is allowed in the sent proto, it's important that
    /// we send to a recipient only from the thread with the most privilege (or randomly select one with equal privilege)
    public static func dedupePrivateStoryRecipients(for messages: [OutgoingStoryMessage], transaction: SDSAnyWriteTransaction) {
        // Bucket outgoing messages per recipient and story. We may be sending multiple stories if the user selected multiple attachments.
        let messagesPerRecipientPerStory = messages.reduce(into: [String: [SignalServiceAddress: [OutgoingStoryMessage]]]()) { result, message in
            guard message.isPrivateStorySend.boolValue else { return }
            var messagesByRecipient = result[message.storyMessageId] ?? [:]
            for address in message.recipientAddresses() {
                var messages = messagesByRecipient[address] ?? []
                // Always prioritize sending to stories that allow replies,
                // we'll later select the first message from this list as
                // the one to actually send to for a given recipient.
                if message.storyAllowsReplies.boolValue {
                    messages.insert(message, at: 0)
                } else {
                    messages.append(message)
                }
                messagesByRecipient[address] = messages
            }
            result[message.storyMessageId] = messagesByRecipient
        }

        for messagesPerRecipient in messagesPerRecipientPerStory.values {
            for (address, messages) in messagesPerRecipient {
                // For every message after the first for a given recipient, mark the
                // recipient as skipped so we don't send them any additional copies.
                for message in messages.dropFirst() {
                    message.updateWithSkippedRecipient(address, transaction: transaction)
                }
            }
        }
    }
}
