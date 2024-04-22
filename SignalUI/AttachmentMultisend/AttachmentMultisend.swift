//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import LibSignalClient

public class AttachmentMultisend {

    public struct Result {
        /// Resolved when the messages are prepared but before uploading/sending.
        public let preparedPromise: Promise<[PreparedOutgoingMessage]>
        /// Resolved when sending is durably enqueued but before uploading/sending.
        public let enqueuedPromise: Promise<[TSThread]>
        /// Resolved when the message is sent.
        public let sentPromise: Promise<[TSThread]>
    }

    private init() {}

    // MARK: - API

    public class func sendApprovedMedia(
        conversations: [ConversationItem],
        approvedMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment]
    ) -> AttachmentMultisend.Result {
        let (preparedPromise, preparedFuture) = Promise<[PreparedOutgoingMessage]>.pending()
        let (enqueuedPromise, enqueuedFuture) = Promise<[TSThread]>.pending()

        let sentPromise = Promise<[TSThread]>.wrapAsync {
            let threads: [TSThread]
            let preparedMessages: [PreparedOutgoingMessage]
            let sendPromises: [Promise<Void>]
            do {
                let segmentedAttachments = try await segmentAttachmentsIfNecessary(
                    for: conversations,
                    approvedAttachments: approvedAttachments
                )
                (threads, preparedMessages, sendPromises) = try await deps.databaseStorage.awaitableWrite { tx in
                    let threads: [TSThread]
                    let preparedMessages: [PreparedOutgoingMessage]
                    (threads, preparedMessages) = try prepareForSending(
                        conversations: conversations,
                        approvedMessageBody: approvedMessageBody,
                        approvedAttachments: segmentedAttachments,
                        tx: tx
                    )

                    let sendPromises: [Promise<Void>] = preparedMessages.map {
                        deps.messageSenderJobQueue.add(
                            .promise,
                            message: $0,
                            transaction: tx
                        )
                    }
                    return (threads, preparedMessages, sendPromises)
                }
            } catch let error {
                preparedFuture.reject(error)
                enqueuedFuture.reject(error)
                throw error
            }
            preparedFuture.resolve(preparedMessages)
            enqueuedFuture.resolve(threads)

            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                sendPromises.forEach { promise in
                    taskGroup.addTask {
                        try await promise.awaitable()
                    }
                }
                try await taskGroup.waitForAll()
            }
            return threads
        }

        return .init(
            preparedPromise: preparedPromise,
            enqueuedPromise: enqueuedPromise,
            sentPromise: sentPromise
        )
    }

    public class func sendTextAttachment(
        _ textAttachment: UnsentTextAttachment,
        to conversations: [ConversationItem]
    ) -> AttachmentMultisend.Result {
        let (preparedPromise, preparedFuture) = Promise<[PreparedOutgoingMessage]>.pending()
        let (enqueuedPromise, enqueuedFuture) = Promise<[TSThread]>.pending()

        let sentPromise = Promise<[TSThread]>.wrapAsync {
            let threads: [TSThread]
            let preparedMessages: [PreparedOutgoingMessage]
            let sendPromises: [Promise<Void>]
            do {
                (threads, preparedMessages, sendPromises) = try await deps.databaseStorage.awaitableWrite { tx in
                    let threads: [TSThread]
                    let preparedMessages: [PreparedOutgoingMessage]
                    (threads, preparedMessages) = try prepareForSending(
                        conversations: conversations,
                        textAttachment,
                        tx: tx
                    )

                    let sendPromises: [Promise<Void>] = preparedMessages.map {
                        deps.messageSenderJobQueue.add(
                            .promise,
                            message: $0,
                            transaction: tx
                        )
                    }
                    return (threads, preparedMessages, sendPromises)
                }
            } catch let error {
                preparedFuture.reject(error)
                enqueuedFuture.reject(error)
                throw error
            }
            preparedFuture.resolve(preparedMessages)
            enqueuedFuture.resolve(threads)

            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                sendPromises.forEach { promise in
                    taskGroup.addTask {
                        try await promise.awaitable()
                    }
                }
                try await taskGroup.waitForAll()
            }
            return threads
        }

        return .init(
            preparedPromise: preparedPromise,
            enqueuedPromise: enqueuedPromise,
            sentPromise: sentPromise
        )
    }

    // MARK: - Dependencies

    private struct Dependencies {
        let attachmentManager: AttachmentManager
        let contactsMentionHydrator: ContactsMentionHydrator.Type
        let databaseStorage: SDSDatabaseStorage
        let imageQualityLevel: ImageQualityLevel.Type
        let messageSenderJobQueue: MessageSenderJobQueue
        let tsAccountManager: TSAccountManager
    }

    private static var deps = Dependencies(
        attachmentManager: DependenciesBridge.shared.attachmentManager,
        contactsMentionHydrator: ContactsMentionHydrator.self,
        databaseStorage: SSKEnvironment.shared.databaseStorage,
        imageQualityLevel: ImageQualityLevel.self,
        messageSenderJobQueue: SSKEnvironment.shared.messageSenderJobQueueRef,
        tsAccountManager: DependenciesBridge.shared.tsAccountManager
    )

    // MARK: - Segmenting Attachments

    private class func segmentAttachmentsIfNecessary(
        for conversations: [ConversationItem],
        approvedAttachments: [SignalAttachment]
    ) async throws -> [SignalAttachment.SegmentAttachmentResult] {
        let maxSegmentDurations = conversations.compactMap(\.videoAttachmentDurationLimit)
        guard !maxSegmentDurations.isEmpty, let requiredSegmentDuration = maxSegmentDurations.min() else {
            // No need to segment!
            return approvedAttachments.map { .init($0) }
        }

        let qualityLevel = deps.databaseStorage.read(block: deps.imageQualityLevel.resolvedQuality(tx:))

        let segmentedResults = try await withThrowingTaskGroup(
            of: (Int, SignalAttachment.SegmentAttachmentResult).self
        ) { taskGroup in
            for (index, attachment) in approvedAttachments.enumerated() {
                taskGroup.addTask(operation: {
                    let result = try await attachment.preparedForOutput(qualityLevel: qualityLevel)
                        .segmentedIfNecessary(on: ThreadUtil.enqueueSendQueue, segmentDuration: requiredSegmentDuration)
                        .awaitable()
                    return (index, result)
                })
            }
            var segmentedResults = [SignalAttachment.SegmentAttachmentResult?].init(repeating: nil, count: approvedAttachments.count)
            for try await result in taskGroup {
                segmentedResults[result.0] = result.1
            }
            return segmentedResults.compacted()
        }

        return segmentedResults
    }

    // MARK: - Preparing messages

    private class func prepareForSending(
        conversations: [ConversationItem],
        approvedMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment.SegmentAttachmentResult],
        tx: SDSAnyWriteTransaction
    ) throws -> ([TSThread], [PreparedOutgoingMessage]) {
        let segmentedAttachments = approvedAttachments.reduce([], { arr, segmented in
            return arr + (segmented.segmented ?? [segmented.original])
        })
        let unsegmentedAttachments = approvedAttachments.map(\.original)

        var nonStoryThreads = [TSThread]()
        var privateStoryThreads = [TSPrivateStoryThread]()
        var groupStoryThreads = [TSGroupThread]()
        for conversation in conversations {
            guard let thread = conversation.getOrCreateThread(transaction: tx) else {
                throw OWSAssertionError("Missing thread for conversation")
            }
            switch conversation.outgoingMessageType {
            case .message:
                owsAssertDebug(conversation.limitsVideoAttachmentLengthForStories == false)
                nonStoryThreads.append(thread)
            case .storyMessage where thread is TSPrivateStoryThread:
                owsAssertDebug(conversation.limitsVideoAttachmentLengthForStories == true)
                privateStoryThreads.append(thread as! TSPrivateStoryThread)
            case .storyMessage where thread is TSGroupThread:
                owsAssertDebug(conversation.limitsVideoAttachmentLengthForStories == true)
                groupStoryThreads.append(thread as! TSGroupThread)
            case .storyMessage:
                throw OWSAssertionError("Invalid story message target!")
            }
        }

        let nonStoryMessages = try prepareNonStoryMessages(
            threads: nonStoryThreads,
            approvedMessageBody: approvedMessageBody,
            unsegmentedAttachments: unsegmentedAttachments,
            tx: tx
        )

        let storyMessageBuilders = try storyMessageBuilders(
            segmentedAttachments: segmentedAttachments,
            approvedMessageBody: approvedMessageBody,
            tx: tx
        )

        let groupStoryMessages = try prepareGroupStoryMessages(
            groupStoryThreads: groupStoryThreads,
            builders: storyMessageBuilders,
            tx: tx
        )
        let privateStoryMessages = try preparePrivateStoryMessages(
            privateStoryThreads: privateStoryThreads,
            builders: storyMessageBuilders,
            tx: tx
        )
        let preparedMessages = nonStoryMessages + groupStoryMessages + privateStoryMessages
        let allThreads = nonStoryThreads + groupStoryThreads + privateStoryThreads
        return (allThreads, preparedMessages)
    }

    private class func prepareForSending(
        conversations: [ConversationItem],
        _ textAttachment: UnsentTextAttachment,
        tx: SDSAnyWriteTransaction
    ) throws -> ([TSThread], [PreparedOutgoingMessage]) {
        let storyMessageBuilder = try storyMessageBuilder(textAttachment: textAttachment, tx: tx)

        var allStoryThreads = [TSThread]()
        var privateStoryThreads = [TSPrivateStoryThread]()
        var groupStoryThreads = [TSGroupThread]()
        for conversation in conversations {
            guard let thread = conversation.getOrCreateThread(transaction: tx) else {
                throw OWSAssertionError("Missing thread for conversation")
            }
            switch conversation.outgoingMessageType {
            case .message:
                throw OWSAssertionError("Cannot send TextAttachment to chats.")
            case .storyMessage where thread is TSPrivateStoryThread:
                privateStoryThreads.append(thread as! TSPrivateStoryThread)
            case .storyMessage where thread is TSGroupThread:
                groupStoryThreads.append(thread as! TSGroupThread)
            case .storyMessage:
                throw OWSAssertionError("Invalid story message target!")
            }
            allStoryThreads.append(thread)
        }

        let groupStoryMessages = try prepareGroupStoryMessages(
            groupStoryThreads: groupStoryThreads,
            builders: [storyMessageBuilder],
            tx: tx
        )
        let privateStoryMessages = try preparePrivateStoryMessages(
            privateStoryThreads: privateStoryThreads,
            builders: [storyMessageBuilder],
            tx: tx
        )
        let preparedMessages = groupStoryMessages + privateStoryMessages
        return (allStoryThreads, preparedMessages)
    }

    // MARK: Preparing Non-Story Messages

    private class func prepareNonStoryMessages(
        threads: [TSThread],
        approvedMessageBody: MessageBody?,
        unsegmentedAttachments: [SignalAttachment],
        tx: SDSAnyWriteTransaction
    ) throws -> [PreparedOutgoingMessage] {
        return try threads.map { thread in
            // If this thread has a pending message request, treat it as accepted.
            ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequest(
                thread,
                setDefaultTimerIfNecessary: true,
                tx: tx
            )

            let preparedMessage = try prepareNonStoryMessage(
                messageBody: approvedMessageBody,
                attachments: unsegmentedAttachments,
                thread: thread,
                tx: tx
            )
            if let message = preparedMessage.messageForIntentDonation(tx: tx) {
                thread.donateSendMessageIntent(for: message, transaction: tx)
            }
            return preparedMessage
        }
    }

    private class func prepareNonStoryMessage(
        messageBody: MessageBody?,
        attachments: [SignalAttachment],
        thread: TSThread,
        tx: SDSAnyWriteTransaction
    ) throws -> PreparedOutgoingMessage {
        let unpreparedMessage = UnpreparedOutgoingMessage.build(
            thread: thread,
            messageBody: messageBody,
            mediaAttachments: attachments,
            quotedReplyDraft: nil,
            linkPreviewDraft: nil,
            transaction: tx
        )
        return try unpreparedMessage.prepare(tx: tx)
    }

    // MARK: Preparing Group Story Messages

    /// Prepare group stories for sending.
    ///
    /// Stories can only have one attachment, so we create a separate StoryMessage per attachment.
    ///
    /// Group stories otherwise behave similarly to message sends; we create one StoryMessage per group,
    /// and an OutgoingStoryMessage for each StoryMessage.
    private class func prepareGroupStoryMessages(
        groupStoryThreads: [TSGroupThread],
        builders: [StoryMessageBuilder],
        tx: SDSAnyWriteTransaction
    ) throws -> [PreparedOutgoingMessage] {
        return try groupStoryThreads
            .flatMap { groupThread in
                return try builders.map { builder in
                    let storyMessage = try createAndInsertStoryMessage(
                        builder: builder,
                        groupThread: groupThread,
                        tx: tx
                    )
                    let outgoingMessage = OutgoingStoryMessage(
                        thread: groupThread,
                        storyMessage: storyMessage,
                        storyMessageRowId: storyMessage.id!,
                        skipSyncTranscript: false,
                        transaction: tx
                    )
                    return outgoingMessage
                }
            }
            .map { outgoingStoryMessage in
                return try UnpreparedOutgoingMessage.forOutgoingStoryMessage(
                    outgoingStoryMessage,
                    storyMessageRowId: outgoingStoryMessage.storyMessageRowId
                ).prepare(tx: tx)
            }
    }

    private class func createAndInsertStoryMessage(
        builder: StoryMessageBuilder,
        groupThread: TSGroupThread,
        tx: SDSAnyWriteTransaction
    ) throws -> StoryMessage {
        let storyManifest: StoryManifest = .outgoing(
            recipientStates: groupThread.recipientAddresses(with: tx)
                .lazy
                .compactMap { $0.serviceId }
                .dictionaryMappingToValues { _ in
                    return .init(allowsReplies: true, contexts: [])
                }
        )
        return try builder.build(
            groupId: groupThread.groupId,
            manifest: storyManifest,
            tx: tx
        )
    }

    // MARK: Preparing Private Story Messages

    /// Prepare group stories for sending.
    ///
    /// Stories can only have one attachment, so we create a separate StoryMessage per attachment.
    ///
    /// For private story threads, we create a single StoryMessage per attachment across all of them.
    /// Then theres one OutgoingStoryMessage per thread, all pointing to that same StoryMessage.
    private class func preparePrivateStoryMessages(
        privateStoryThreads: [TSPrivateStoryThread],
        builders: [StoryMessageBuilder],
        tx: SDSAnyWriteTransaction
    ) throws -> [PreparedOutgoingMessage] {
        return try builders
            .flatMap { builder in
                let storyMessage = try createAndInsertStoryMessage(
                    builder: builder,
                    privateStoryThreads: privateStoryThreads,
                    tx: tx
                )
                return OutgoingStoryMessage.createDedupedOutgoingMessages(
                    for: storyMessage,
                    sendingTo: privateStoryThreads,
                    tx: tx
                )
            }
            .map { outgoingStoryMessage in
                return try UnpreparedOutgoingMessage.forOutgoingStoryMessage(
                    outgoingStoryMessage,
                    storyMessageRowId: outgoingStoryMessage.storyMessageRowId
                ).prepare(tx: tx)
            }
    }

    private class func createAndInsertStoryMessage(
        builder: StoryMessageBuilder,
        privateStoryThreads: [TSPrivateStoryThread],
        tx: SDSAnyWriteTransaction
    ) throws -> StoryMessage {
        var recipientStates = [ServiceId: StoryRecipientState]()
        for thread in privateStoryThreads {
            guard let threadUuid = UUID(uuidString: thread.uniqueId) else {
                throw OWSAssertionError("Invalid uniqueId for thread \(thread.uniqueId)")
            }
            for recipientAddress in thread.recipientAddresses(with: tx) {
                guard let recipient = recipientAddress.serviceId else {
                    continue
                }
                let existingState = recipientStates[recipient] ?? .init(allowsReplies: false, contexts: [])
                let newState = StoryRecipientState(
                    allowsReplies: existingState.allowsReplies || thread.allowsReplies,
                    contexts: existingState.contexts + [threadUuid]
                )
                recipientStates[recipient] = newState
            }
        }

        let storyManifest = StoryManifest.outgoing(recipientStates: recipientStates)

        return try builder.build(
            groupId: nil,
            manifest: storyManifest,
            tx: tx
        )
    }

    // MARK: Generic story construction

    private struct StoryMessageBuilder {
        let attachmentBuilder: OwnedAttachmentBuilder<StoryMessageAttachment>
        let localAci: Aci
        let mediaCaption: StyleOnlyMessageBody?
        let shouldLoop: Bool

        func build(
            groupId: Data?,
            manifest: StoryManifest,
            tx: SDSAnyWriteTransaction
        ) throws -> StoryMessage {
            let storyMessage = try StoryMessage.createAndInsert(
                timestamp: Date.ows_millisecondTimestamp(),
                authorAci: self.localAci,
                groupId: groupId,
                manifest: manifest,
                replyCount: 0,
                attachmentBuilder: self.attachmentBuilder,
                mediaCaption: self.mediaCaption,
                shouldLoop: self.shouldLoop,
                transaction: tx
            )
            return storyMessage
        }
    }

    private class func storyMessageBuilders(
        segmentedAttachments: [SignalAttachment],
        approvedMessageBody: MessageBody?,
        tx: SDSAnyReadTransaction
    ) throws -> [StoryMessageBuilder] {
        guard let localAci = deps.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci else {
            throw OWSAssertionError("Sending without a local aci!")
        }

        let storyCaption = approvedMessageBody?
            .hydrating(mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: tx.asV2Read))
            .asStyleOnlyBody()

        return segmentedAttachments.map { attachment in
            let attachmentDataSource = AttachmentDataSource.from(
                dataSource: attachment.dataSource,
                mimeType: attachment.mimeType
            )

            let attachmentManager = deps.attachmentManager
            let attachmentBuilder = OwnedAttachmentBuilder<StoryMessageAttachment>(
                info: .foreignReferenceAttachment,
                finalize: { owner, tx in
                    try attachmentManager.createAttachmentStream(
                        consuming: .init(dataSource: attachmentDataSource, owner: owner),
                        tx: tx
                    )
                }
            )
            return .init(
                attachmentBuilder: attachmentBuilder,
                localAci: localAci,
                mediaCaption: storyCaption,
                shouldLoop: attachment.isLoopingVideo
            )
        }
    }

    private class func storyMessageBuilder(
        textAttachment: UnsentTextAttachment,
        tx: SDSAnyWriteTransaction
    ) throws -> StoryMessageBuilder {
        guard let localAci = deps.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci else {
            throw OWSAssertionError("Sending without a local aci!")
        }
        guard
            let textAttachmentBuilder = textAttachment
                .validateLinkPreviewAndBuildTextAttachment(transaction: tx)?
                .wrap({ StoryMessageAttachment.text($0) })
        else {
            throw OWSAssertionError("Invalid text attachment")
        }
        return .init(
            attachmentBuilder: textAttachmentBuilder,
            localAci: localAci,
            mediaCaption: nil,
            shouldLoop: false
        )
    }
}
