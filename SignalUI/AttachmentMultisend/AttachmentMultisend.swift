//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit
import LibSignalClient

public class AttachmentMultisend {

    public struct EnqueueResult {
        public let preparedMessage: PreparedOutgoingMessage
        public let sendPromise: Promise<Void>
    }

    private init() {}

    // MARK: - API

    public class func enqueueApprovedMedia(
        conversations: [ConversationItem],
        approvedMessageBody: MessageBody?,
        approvedAttachments: ApprovedAttachments,
    ) async throws -> [EnqueueResult] {
        let destinations = try await prepareDestinations(
            forSendingMessageBody: approvedMessageBody,
            toConversations: conversations,
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

        let imageQuality = approvedAttachments.imageQuality
        let imageQualityLevel = ImageQualityLevel.resolvedValue(imageQuality: imageQuality)
        let sendableAttachments = try await approvedAttachments.attachments.mapAsync {
            return try await SendableAttachment.forPreviewableAttachment($0, imageQualityLevel: imageQualityLevel)
        }

        let segmentedAttachments = try await segmentAttachmentsIfNecessary(
            for: conversations,
            sendableAttachments: sendableAttachments,
            hasNonStoryDestination: hasNonStoryDestination,
            hasStoryDestination: hasStoryDestination,
        )

        return try await deps.databaseStorage.awaitableWrite { tx in
            let preparedMessages = try prepareMessages(
                // Stories get an untruncated message body
                forSendingMessageBodyForStories: approvedMessageBody,
                approvedAttachments: segmentedAttachments,
                isViewOnce: approvedAttachments.isViewOnce,
                toDestinations: destinations,
                tx: tx,
            )

            return preparedMessages.map {
                let sendPromise = deps.messageSenderJobQueue.add(.promise, message: $0, transaction: tx)
                return EnqueueResult(preparedMessage: $0, sendPromise: sendPromise)
            }
        }
    }

    public class func enqueueTextAttachment(
        _ textAttachment: UnsentTextAttachment,
        to conversations: [ConversationItem]
    ) async throws -> [EnqueueResult] {
        if conversations.isEmpty {
            return []
        }

        // Prepare the text attachment
        let textAttachment = try await textAttachment.validateAndPrepareForSending()

        return try await deps.databaseStorage.awaitableWrite { tx in
            let preparedMessages = try prepareMessages(
                forSendingTextAttachment: textAttachment,
                toConversations: conversations,
                tx: tx,
            )

            return preparedMessages.map {
                let sendPromise = deps.messageSenderJobQueue.add(.promise, message: $0, transaction: tx)
                return EnqueueResult(preparedMessage: $0, sendPromise: sendPromise)
            }
        }
    }

    // MARK: - Dependencies

    struct Dependencies {
        let attachmentManager: AttachmentManager
        let attachmentValidator: AttachmentContentValidator
        let contactsMentionHydrator: ContactsMentionHydrator.Type
        let databaseStorage: SDSDatabaseStorage
        let messageSenderJobQueue: MessageSenderJobQueue
        let tsAccountManager: TSAccountManager
    }

    static let deps = Dependencies(
        attachmentManager: DependenciesBridge.shared.attachmentManager,
        attachmentValidator: DependenciesBridge.shared.attachmentContentValidator,
        contactsMentionHydrator: ContactsMentionHydrator.self,
        databaseStorage: SSKEnvironment.shared.databaseStorageRef,
        messageSenderJobQueue: SSKEnvironment.shared.messageSenderJobQueueRef,
        tsAccountManager: DependenciesBridge.shared.tsAccountManager
    )

    // MARK: - Segmenting Attachments

    private struct SegmentAttachmentResult {
        let original: AttachmentDataSource?
        let segmented: [AttachmentDataSource]?
        let renderingFlag: AttachmentReference.RenderingFlag

        init(
            original: AttachmentDataSource?,
            segmented: [AttachmentDataSource]?,
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
        sendableAttachments: [SendableAttachment],
        hasNonStoryDestination: Bool,
        hasStoryDestination: Bool
    ) async throws -> [SegmentAttachmentResult] {
        let maxSegmentDurations = conversations.compactMap(\.videoAttachmentDurationLimit)
        guard hasStoryDestination, !maxSegmentDurations.isEmpty, let requiredSegmentDuration = maxSegmentDurations.min() else {
            // No need to segment!
            var results = [SegmentAttachmentResult]()
            for attachment in sendableAttachments {
                let dataSource: AttachmentDataSource = try await deps.attachmentValidator.validateContents(
                    sendableAttachment: attachment,
                    shouldUseDefaultFilename: false,
                )
                try results.append(.init(
                    original: dataSource,
                    segmented: nil,
                    renderingFlag: attachment.renderingFlag
                ))
            }
            return results
        }

        var segmentedResults = [SegmentAttachmentResult]()
        for attachment in sendableAttachments {
            let segmentingResult = try await attachment.segmentedIfNecessary(segmentDuration: requiredSegmentDuration)

            let originalDataSource: AttachmentDataSource?
            if hasNonStoryDestination || segmentingResult.segmented == nil {
                // We need to prepare the original, either because there are no segments
                // (e.g., it's an image) or because we are sending to a non-story which
                // doesn't segment.
                originalDataSource = try await deps.attachmentValidator.validateContents(
                    sendableAttachment: segmentingResult.original,
                    shouldUseDefaultFilename: false,
                )
            } else {
                originalDataSource = nil
            }

            let segmentedDataSources: [AttachmentDataSource]? = try await { () -> [AttachmentDataSource]? in
                guard let segments = segmentingResult.segmented, hasStoryDestination else {
                    return nil
                }
                var segmentedDataSources = [AttachmentDataSource]()
                for segment in segments {
                    let dataSource: AttachmentDataSource = try await deps.attachmentValidator.validateContents(
                        sendableAttachment: segment,
                        shouldUseDefaultFilename: false,
                    )
                    segmentedDataSources.append(dataSource)
                }
                return segmentedDataSources
            }()

            segmentedResults.append(try SegmentAttachmentResult(
                original: originalDataSource,
                segmented: segmentedDataSources,
                renderingFlag: attachment.renderingFlag
            ))
        }
        return segmentedResults
    }

    // MARK: - Preparing messages

    private class func prepareMessages(
        forSendingMessageBodyForStories messageBodyForStories: MessageBody?,
        approvedAttachments: [SegmentAttachmentResult],
        isViewOnce: Bool,
        toDestinations destinations: [Destination],
        tx: DBWriteTransaction,
    ) throws -> [PreparedOutgoingMessage] {
        let segmentedAttachments = approvedAttachments.reduce([], { arr, segmented in
            return arr + segmented.segmentedOrOriginal.map { ($0, segmented.renderingFlag == .shouldLoop) }
        })
        let unsegmentedAttachments = approvedAttachments.compactMap { (attachment) -> SendableAttachment.ForSending? in
            guard let original = attachment.original else {
                return nil
            }
            return SendableAttachment.ForSending(
                dataSource: original,
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
            isViewOnceMessage: isViewOnce,
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
        return nonStoryMessages + groupStoryMessages + privateStoryMessages
    }

    private class func prepareMessages(
        forSendingTextAttachment textAttachment: UnsentTextAttachment.ForSending,
        toConversations conversations: [ConversationItem],
        tx: DBWriteTransaction,
    ) throws -> [PreparedOutgoingMessage] {
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
        return groupStoryMessages + privateStoryMessages
    }

    // MARK: Preparing Non-Story Messages

    private class func prepareNonStoryMessages(
        threadDestinations: [Destination],
        unsegmentedAttachments: [SendableAttachment.ForSending],
        isViewOnceMessage: Bool,
        tx: DBWriteTransaction
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
                isViewOnce: isViewOnceMessage,
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
        attachments: [SendableAttachment.ForSending],
        isViewOnce: Bool,
        thread: TSThread,
        tx: DBWriteTransaction
    ) throws -> PreparedOutgoingMessage {
        let unpreparedMessage = UnpreparedOutgoingMessage.build(
            thread: thread,
            messageBody: messageBody,
            mediaAttachments: attachments,
            isViewOnce: isViewOnce,
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
        tx: DBWriteTransaction
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
        tx: DBWriteTransaction
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
        tx: DBWriteTransaction
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
        tx: DBWriteTransaction
    ) throws -> StoryMessage {
        var recipientStates = [ServiceId: StoryRecipientState]()
        for thread in privateStoryThreads {
            guard let threadUuid = UUID(uuidString: thread.uniqueId) else {
                throw OWSAssertionError("Invalid uniqueId for thread \(thread.logString)")
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
            tx: DBWriteTransaction
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
        tx: DBReadTransaction
    ) throws -> [StoryMessageBuilder] {
        if groupStoryThreads.isEmpty && privateStoryThreads.isEmpty {
            // No story destinations, no need to build story messages.
            return []
        }

        guard let localAci = deps.tsAccountManager.localIdentifiers(tx: tx)?.aci else {
            throw OWSAssertionError("Sending without a local aci!")
        }

        let storyCaption = approvedMessageBody?
            .hydrating(mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: tx))
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
        tx: DBWriteTransaction
    ) throws -> StoryMessageBuilder {
        guard let localAci = deps.tsAccountManager.localIdentifiers(tx: tx)?.aci else {
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
