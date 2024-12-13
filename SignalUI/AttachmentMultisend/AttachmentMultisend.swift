//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit
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
                let destinations = try await Self.prepareForSending(
                    approvedMessageBody,
                    to: conversations,
                    db: deps.databaseStorage,
                    attachmentValidator: deps.attachmentValidator
                )

                var hasNonStoryDestination = false
                var hasStoryDestination = false
                destinations.forEach { destination in
                    switch destination.conversationItem.outgoingMessageType {
                    case .message:
                        hasNonStoryDestination = true
                    case .storyMessage:
                        hasStoryDestination = true
                    }
                }

                let segmentedAttachments = try await segmentAttachmentsIfNecessary(
                    for: conversations,
                    approvedAttachments: approvedAttachments,
                    hasNonStoryDestination: hasNonStoryDestination,
                    hasStoryDestination: hasStoryDestination
                )

                (threads, preparedMessages, sendPromises) = try await deps.databaseStorage.awaitableWrite { tx in
                    let threads: [TSThread]
                    let preparedMessages: [PreparedOutgoingMessage]
                    (threads, preparedMessages) = try prepareForSending(
                        destinations: destinations,
                        // Stories get an untruncated message body
                        messageBodyForStories: approvedMessageBody,
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
            // Prepare the text attachment
            let textAttachment = try textAttachment.validateAndPrepareForSending()

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
        let attachmentValidator: AttachmentContentValidator
        let contactsMentionHydrator: ContactsMentionHydrator.Type
        let databaseStorage: SDSDatabaseStorage
        let imageQualityLevel: ImageQualityLevel.Type
        let messageSenderJobQueue: MessageSenderJobQueue
        let tsAccountManager: TSAccountManager
    }

    private static var deps = Dependencies(
        attachmentManager: DependenciesBridge.shared.attachmentManager,
        attachmentValidator: DependenciesBridge.shared.attachmentContentValidator,
        contactsMentionHydrator: ContactsMentionHydrator.self,
        databaseStorage: SSKEnvironment.shared.databaseStorageRef,
        imageQualityLevel: ImageQualityLevel.self,
        messageSenderJobQueue: SSKEnvironment.shared.messageSenderJobQueueRef,
        tsAccountManager: DependenciesBridge.shared.tsAccountManager
    )

    // MARK: - Segmenting Attachments

    private struct SegmentAttachmentResult {
        let original: AttachmentDataSource?
        let segmented: [AttachmentDataSource]?
        let isViewOnce: Bool
        let renderingFlag: AttachmentReference.RenderingFlag

        init(
            original: AttachmentDataSource?,
            segmented: [AttachmentDataSource]?,
            isViewOnce: Bool,
            renderingFlag: AttachmentReference.RenderingFlag
        ) throws {
            // We only create data sources for the original or segments if we need to.
            // Stories use segments if available; non stories always need the original.
            // Creating data sources is expensive, so only create what we need,
            // but always at least one.
            guard original != nil || segmented != nil else {
                throw OWSAssertionError("Must have some kind of attachment!")
            }
            self.original = original
            self.segmented = segmented
            self.isViewOnce = isViewOnce
            self.renderingFlag = renderingFlag
        }

        var segmentedOrOriginal: [AttachmentDataSource] {
            if let segmented {
                return segmented
            }
            return [original].compacted()
        }
    }

    private class func segmentAttachmentsIfNecessary(
        for conversations: [ConversationItem],
        approvedAttachments: [SignalAttachment],
        hasNonStoryDestination: Bool,
        hasStoryDestination: Bool
    ) async throws -> [SegmentAttachmentResult] {
        let maxSegmentDurations = conversations.compactMap(\.videoAttachmentDurationLimit)
        guard hasStoryDestination, !maxSegmentDurations.isEmpty, let requiredSegmentDuration = maxSegmentDurations.min() else {
            // No need to segment!
            var results = [SegmentAttachmentResult]()
            for attachment in approvedAttachments {
                let dataSource: AttachmentDataSource = try deps.attachmentValidator.validateContents(
                    dataSource: attachment.dataSource,
                    shouldConsume: true,
                    mimeType: attachment.mimeType,
                    renderingFlag: attachment.renderingFlag,
                    sourceFilename: attachment.sourceFilename
                )
                try results.append(.init(
                    original: dataSource,
                    segmented: nil,
                    isViewOnce: attachment.isViewOnceAttachment,
                    renderingFlag: attachment.renderingFlag
                ))
            }
            return results
        }

        let qualityLevel = deps.databaseStorage.read(block: deps.imageQualityLevel.resolvedQuality(tx:))

        let segmentedResults = try await withThrowingTaskGroup(
            of: (Int, SegmentAttachmentResult).self
        ) { taskGroup in
            for (index, attachment) in approvedAttachments.enumerated() {
                taskGroup.addTask(operation: {
                    let segmentingResult = try await attachment.preparedForOutput(qualityLevel: qualityLevel)
                        .segmentedIfNecessary(segmentDuration: requiredSegmentDuration)

                    let originalDataSource: AttachmentDataSource?
                    if hasNonStoryDestination || segmentingResult.segmented == nil {
                        // We need to prepare the original, either because there are no segments
                        // or because we are sending to a non-story which doesn't segment.
                        originalDataSource = try deps.attachmentValidator.validateContents(
                            dataSource: segmentingResult.original.dataSource,
                            shouldConsume: true,
                            mimeType: segmentingResult.original.mimeType,
                            renderingFlag: segmentingResult.original.renderingFlag,
                            sourceFilename: segmentingResult.original.sourceFilename
                        )
                    } else {
                        originalDataSource = nil
                    }

                    let segmentedDataSources: [AttachmentDataSource]? = try { () -> [AttachmentDataSource]? in
                        guard let segments = segmentingResult.segmented, hasStoryDestination else {
                            return nil
                        }
                        var segmentedDataSources = [AttachmentDataSource]()
                        for segment in segments {
                            let dataSource: AttachmentDataSource = try deps.attachmentValidator.validateContents(
                                dataSource: segment.dataSource,
                                shouldConsume: true,
                                mimeType: segment.mimeType,
                                renderingFlag: segment.renderingFlag,
                                sourceFilename: segment.sourceFilename
                            )
                            segmentedDataSources.append(dataSource)
                        }
                        return segmentedDataSources
                    }()

                    return try (index, .init(
                        original: originalDataSource,
                        segmented: segmentedDataSources,
                        isViewOnce: attachment.isViewOnceAttachment,
                        renderingFlag: attachment.renderingFlag
                    ))
                })
            }
            var segmentedResults = [SegmentAttachmentResult?].init(repeating: nil, count: approvedAttachments.count)
            for try await result in taskGroup {
                segmentedResults[result.0] = result.1
            }
            return segmentedResults.compacted()
        }

        return segmentedResults
    }

    // MARK: - Preparing messages

    private class func prepareForSending(
        destinations: [Destination],
        messageBodyForStories: MessageBody?,
        approvedAttachments: [SegmentAttachmentResult],
        tx: SDSAnyWriteTransaction
    ) throws -> ([TSThread], [PreparedOutgoingMessage]) {
        let segmentedAttachments = approvedAttachments.reduce([], { arr, segmented in
            return arr + segmented.segmentedOrOriginal.map { ($0, segmented.renderingFlag == .shouldLoop) }
        })
        let unsegmentedAttachments = approvedAttachments.compactMap { (attachment) -> SignalAttachment.ForSending? in
            guard let original = attachment.original else {
                return nil
            }
            return SignalAttachment.ForSending(
                dataSource: original,
                isViewOnce: attachment.isViewOnce,
                renderingFlag: attachment.renderingFlag
            )
        }

        var nonStoryThreads = [Destination]()
        var privateStoryThreads = [TSPrivateStoryThread]()
        var groupStoryThreads = [TSGroupThread]()
        for destination in destinations {
            let conversation = destination.conversationItem
            let thread = destination.thread
            switch conversation.outgoingMessageType {
            case .message:
                owsAssertDebug(conversation.limitsVideoAttachmentLengthForStories == false)
                nonStoryThreads.append(destination)
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
            threadDestinations: nonStoryThreads,
            unsegmentedAttachments: unsegmentedAttachments,
            isViewOnceMessage: approvedAttachments.contains(where: \.isViewOnce),
            tx: tx
        )

        let storyMessageBuilders = try storyMessageBuilders(
            segmentedAttachments: segmentedAttachments,
            approvedMessageBody: messageBodyForStories,
            groupStoryThreads: groupStoryThreads,
            privateStoryThreads: privateStoryThreads,
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
        let allThreads = nonStoryThreads.map(\.thread) + groupStoryThreads + privateStoryThreads
        return (allThreads, preparedMessages)
    }

    private class func prepareForSending(
        conversations: [ConversationItem],
        _ textAttachment: UnsentTextAttachment.ForSending,
        tx: SDSAnyWriteTransaction
    ) throws -> ([TSThread], [PreparedOutgoingMessage]) {
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

        let storyMessageBuilder = try storyMessageBuilder(
            textAttachment: textAttachment,
            groupStoryThreads: groupStoryThreads,
            privateStoryThreads: privateStoryThreads,
            tx: tx
        )

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
        threadDestinations: [Destination],
        unsegmentedAttachments: [SignalAttachment.ForSending],
        isViewOnceMessage: Bool,
        tx: SDSAnyWriteTransaction
    ) throws -> [PreparedOutgoingMessage] {
        return try threadDestinations.map { destination in
            let thread = destination.thread
            // If this thread has a pending message request, treat it as accepted.
            ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequest(
                thread,
                setDefaultTimerIfNecessary: true,
                tx: tx
            )

            let preparedMessage = try prepareNonStoryMessage(
                messageBody: destination.messageBody,
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
        messageBody: ValidatedMessageBody?,
        attachments: [SignalAttachment.ForSending],
        thread: TSThread,
        tx: SDSAnyWriteTransaction
    ) throws -> PreparedOutgoingMessage {
        let unpreparedMessage = UnpreparedOutgoingMessage.build(
            thread: thread,
            messageBody: messageBody,
            mediaAttachments: attachments,
            quotedReplyDraft: nil,
            linkPreviewDataSource: nil,
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
        if privateStoryThreads.isEmpty {
            return []
        }
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
        /// Group id to builder; each group thread gets its own builder.
        let groupThreadAttachmentBuilders: [Data: OwnedAttachmentBuilder<StoryMessageAttachment>]
        /// All private story threads share a single builder (because they share a single StoryMessage).
        let privateStoryThreadAttachmentBuilder: OwnedAttachmentBuilder<StoryMessageAttachment>?
        let localAci: Aci
        let mediaCaption: StyleOnlyMessageBody?
        let shouldLoop: Bool

        func build(
            groupId: Data?,
            manifest: StoryManifest,
            tx: SDSAnyWriteTransaction
        ) throws -> StoryMessage {
            let attachmentBuilder: OwnedAttachmentBuilder<StoryMessageAttachment>?
            if let groupId {
                attachmentBuilder = groupThreadAttachmentBuilders[groupId]
            } else {
                attachmentBuilder = privateStoryThreadAttachmentBuilder
            }
            guard let attachmentBuilder else {
                throw OWSAssertionError("Building for an unprepared thread")
            }

            let storyMessage = try StoryMessage.createAndInsert(
                timestamp: MessageTimestampGenerator.sharedInstance.generateTimestamp(),
                authorAci: self.localAci,
                groupId: groupId,
                manifest: manifest,
                replyCount: 0,
                attachmentBuilder: attachmentBuilder,
                mediaCaption: self.mediaCaption,
                shouldLoop: self.shouldLoop,
                transaction: tx
            )
            return storyMessage
        }
    }

    private class func storyMessageBuilders(
        segmentedAttachments: [(AttachmentDataSource, isLoopingVideo: Bool)],
        approvedMessageBody: MessageBody?,
        groupStoryThreads: [TSGroupThread],
        privateStoryThreads: [TSPrivateStoryThread],
        tx: SDSAnyReadTransaction
    ) throws -> [StoryMessageBuilder] {
        if groupStoryThreads.isEmpty && privateStoryThreads.isEmpty {
            // No story destinations, no need to build story messages.
            return []
        }

        guard let localAci = deps.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci else {
            throw OWSAssertionError("Sending without a local aci!")
        }

        let storyCaption = approvedMessageBody?
            .hydrating(mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: tx.asV2Read))
            .asStyleOnlyBody()

        return segmentedAttachments.map { attachmentDataSource, isLoopingVideo in
            let attachmentManager = deps.attachmentManager
            let attachmentBuilder = OwnedAttachmentBuilder<StoryMessageAttachment>(
                info: .media,
                finalize: { owner, tx in
                    try attachmentManager.createAttachmentStream(
                        consuming: .init(dataSource: attachmentDataSource, owner: owner),
                        tx: tx
                    )
                }
            )
            return storyMessageBuilder(
                attachmentBuilder: attachmentBuilder,
                groupStoryThreads: groupStoryThreads,
                privateStoryThreads: privateStoryThreads,
                localAci: localAci,
                mediaCaption: storyCaption,
                shouldLoop: isLoopingVideo
            )
        }
    }

    private class func storyMessageBuilder(
        textAttachment: UnsentTextAttachment.ForSending,
        groupStoryThreads: [TSGroupThread],
        privateStoryThreads: [TSPrivateStoryThread],
        tx: SDSAnyWriteTransaction
    ) throws -> StoryMessageBuilder {
        guard let localAci = deps.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci else {
            throw OWSAssertionError("Sending without a local aci!")
        }
        guard
            let textAttachmentBuilder = textAttachment
                .buildTextAttachment(transaction: tx)?
                .wrap({ StoryMessageAttachment.text($0) })
        else {
            throw OWSAssertionError("Invalid text attachment")
        }
        return storyMessageBuilder(
            attachmentBuilder: textAttachmentBuilder,
            groupStoryThreads: groupStoryThreads,
            privateStoryThreads: privateStoryThreads,
            localAci: localAci,
            mediaCaption: nil,
            shouldLoop: false
        )
    }

    private class func storyMessageBuilder(
        attachmentBuilder: OwnedAttachmentBuilder<StoryMessageAttachment>,
        groupStoryThreads: [TSGroupThread],
        privateStoryThreads: [TSPrivateStoryThread],
        localAci: Aci,
        mediaCaption: StyleOnlyMessageBody?,
        shouldLoop: Bool
    ) -> StoryMessageBuilder {
        var numDestinations = groupStoryThreads.count
        if !privateStoryThreads.isEmpty {
            numDestinations += 1
        }
        let duplicatedAttachmentBuilders = attachmentBuilder.forMultisendReuse(
            numDestinations: numDestinations
        )
        var groupThreadAttachmentBuilders = [Data: OwnedAttachmentBuilder<StoryMessageAttachment>]()
        for (index, groupStoryThread) in groupStoryThreads.enumerated() {
            groupThreadAttachmentBuilders[groupStoryThread.groupId] = duplicatedAttachmentBuilders[index]
        }
        return .init(
            groupThreadAttachmentBuilders: groupThreadAttachmentBuilders,
            privateStoryThreadAttachmentBuilder: privateStoryThreads.isEmpty
                ? nil
                : duplicatedAttachmentBuilders.last,
            localAci: localAci,
            mediaCaption: mediaCaption,
            shouldLoop: shouldLoop
        )
    }
}
