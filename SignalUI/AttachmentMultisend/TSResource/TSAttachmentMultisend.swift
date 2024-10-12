//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

public class TSAttachmentMultisend {

    private struct PreparedMultisend {
        let attachmentIdMap: [String: [String]]
        let messages: [PreparedOutgoingMessage]
        let storyMessagesToSend: [OutgoingStoryMessage]
        let threads: [TSThread]
    }

    public class func sendApprovedMedia(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment]
    ) -> AttachmentMultisend.Result {
        let preparedPromise = firstly(on: ThreadUtil.enqueueSendQueue) { () -> Promise<PreparedMultisend> in
            self.prepareForSendingWithSneakyTransaction(
                conversations: conversations,
                approvalMessageBody: approvalMessageBody,
                approvedAttachments: approvedAttachments,
                on: ThreadUtil.enqueueSendQueue
            )
        }
        return sendAttachment(preparedSend: preparedPromise)
    }

    private class func prepareForSendingWithSneakyTransaction(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment],
        on queue: DispatchQueue
    ) -> Promise<PreparedMultisend> {
        if let segmentDuration = conversations.lazy.compactMap(\.videoAttachmentDurationLimit).min() {
            let qualityLevel = SSKEnvironment.shared.databaseStorageRef.read { tx in ImageQualityLevel.resolvedQuality(tx: tx) }
            let attachmentPromises = approvedAttachments.map {
                $0.preparedForOutput(qualityLevel: qualityLevel)
                    .segmentedIfNecessary(on: queue, segmentDuration: segmentDuration)
            }
            return Promise.when(fulfilled: attachmentPromises).map(on: queue) { segmentedResults in
                return try prepareForSending(
                    conversations: conversations,
                    approvalMessageBody: approvalMessageBody,
                    approvedAttachments: segmentedResults
                )
            }
        } else {
            do {
                let preparedMedia = try prepareForSending(
                    conversations: conversations,
                    approvalMessageBody: approvalMessageBody,
                    approvedAttachments: approvedAttachments.map { .init($0) }
                )
                return .value(preparedMedia)
            } catch {
                return .init(error: error)
            }
        }

    }

    private class func prepareForSending(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment.SegmentAttachmentResult]
    ) throws -> PreparedMultisend {
        struct IdentifiedSegmentedResult {
            let original: Identified<SignalAttachment>
            let segmented: [Identified<SignalAttachment>]?
        }
        let identifiedAttachments: [IdentifiedSegmentedResult] = approvedAttachments.map {
            return IdentifiedSegmentedResult(
                original: .init($0.original),
                segmented: $0.segmented?.map { .init($0) }
            )
        }

        var attachmentsByMessageType = [ConversationItemMessageType: [(ConversationItem, [Identified<SignalAttachment>])]]()

        var hasConversationRequiringSegments = false
        var hasConversationRequiringOriginals = false
        for conversation in conversations {
            hasConversationRequiringSegments = hasConversationRequiringSegments || conversation.limitsVideoAttachmentLengthForStories
            hasConversationRequiringOriginals = hasConversationRequiringOriginals || !conversation.limitsVideoAttachmentLengthForStories
            let clonedAttachments: [Identified<SignalAttachment>] = try identifiedAttachments
                .lazy
                .flatMap { attachment -> [Identified<SignalAttachment>] in
                    guard
                        conversation.limitsVideoAttachmentLengthForStories,
                        let segmented = attachment.segmented
                    else {
                        return [attachment.original]
                    }
                    return segmented
                }
                .map {
                    // Duplicate the segmented attachments per conversation
                    try $0.mapValue { return try $0.cloneAttachment() }
                }

            let messageType = conversation.outgoingMessageType
            var messageTypeArray = attachmentsByMessageType[messageType] ?? []
            messageTypeArray.append((conversation, clonedAttachments))
            attachmentsByMessageType[messageType] = messageTypeArray
        }

        // We only upload one set of attachments, and then copy the upload details into
        // each conversation before sending.
        let attachmentsToUpload: [Identified<OutgoingAttachmentInfo>] = identifiedAttachments
            .lazy
            .flatMap { segmentedAttachment -> [Identified<SignalAttachment>] in
                var attachmentsToUpload = [Identified<SignalAttachment>]()
                if hasConversationRequiringOriginals || (segmentedAttachment.segmented?.isEmpty ?? true) {
                    attachmentsToUpload.append(segmentedAttachment.original)
                }
                if hasConversationRequiringSegments, let segmented = segmentedAttachment.segmented {
                    attachmentsToUpload.append(contentsOf: segmented)
                }
                return attachmentsToUpload
            }
            .map { identifiedAttachment in
                identifiedAttachment.mapValue { attachment in
                    return OutgoingAttachmentInfo(
                        dataSource: attachment.dataSource,
                        contentType: attachment.mimeType,
                        sourceFilename: attachment.filenameOrDefault,
                        caption: attachment.captionText,
                        isBorderless: attachment.isBorderless,
                        isVoiceMessage: attachment.isVoiceMessage,
                        isLoopingVideo: attachment.isLoopingVideo
                    )
                }
            }

        let state = MultisendState(approvalMessageBody: approvalMessageBody)

        try SSKEnvironment.shared.databaseStorageRef.write { transaction in
            for (type, values) in attachmentsByMessageType {
                let destinations = try values.lazy.map { conversation, attachments -> MultisendDestination in
                    guard let thread = conversation.getOrCreateThread(transaction: transaction) else {
                        throw OWSAssertionError("Missing thread for conversation")
                    }
                    return .init(thread: thread, content: .media(attachments))
                }
                // This will create TSAttachments for each destination, but will not actually upload anything.
                // It will map the UUIDs we created above for each attachment we want to upload to the unique ids
                // of each created TSAttachment in state.correspondingAttachmentIds.
                try type.prepareForMultisending(destinations: destinations, state: state, transaction: transaction)
            }

            // Every attachment we plan to upload should be accounted for, since at least one destination
            // should be using it and have added its UUID to correspondingAttachmentIds.
            owsAssertDebug(state.correspondingAttachmentIds.values.count == attachmentsToUpload.count)

            for attachmentInfo in attachmentsToUpload {
                do {
                    let dataSource = attachmentInfo.value.asLegacyAttachmentDataSource()
                    let attachmentIdToUpload = try TSAttachmentManager().createAttachmentStream(
                        from: dataSource,
                        tx: transaction
                    )

                    // Finally we map the unique ID of each TSAttachment we intend to upload to the unique IDs of
                    // all the independent TSAttachments we created for each destination. This lets us upload only
                    // the one attachment (the one whose id is the key below) instead of uploading once per destination.
                    state.attachmentIdMap[attachmentIdToUpload] = state.correspondingAttachmentIds[attachmentInfo.id]
                } catch {
                    owsFailDebug("error: \(error)")
                }
            }
        }

        return PreparedMultisend(
            attachmentIdMap: state.attachmentIdMap,
            messages: state.messages,
            storyMessagesToSend: state.storyMessagesToSend,
            threads: state.threads
        )
    }

    public class func sendTextAttachment(
        _ textAttachment: UnsentTextAttachment,
        to conversations: [ConversationItem]
    ) -> AttachmentMultisend.Result {
        let preparedPromise = firstly(on: ThreadUtil.enqueueSendQueue) { () -> PreparedMultisend in
            try self.prepareForSending(
                conversations: conversations,
                textAttachment: textAttachment.validateAndPrepareForSending()
            )
        }
        return sendAttachment(preparedSend: preparedPromise)
    }

    private class func prepareForSending(
        conversations: [ConversationItem],
        textAttachment: UnsentTextAttachment.ForSending
    ) throws -> PreparedMultisend {

        let state = MultisendState(approvalMessageBody: nil)
        let conversationsByMessageType = Dictionary(grouping: conversations, by: { $0.outgoingMessageType })
        try SSKEnvironment.shared.databaseStorageRef.write { transaction in

            // Create one special TextAttachment from our UnsentTextAttachment; this implicitly creates a TSAttachment
            // for the link preview's image (if there is any link preview image).
            // This is the TSAttachment we will upload to the server, and whose uploaded information we will
            // propagate to the independent TSAttachments that will be created per each destination.
            // (Each destination needs its own independent TSAttachment so that deleting one has no effect on
            // the others)
            let attachmentToUploadIdentifier = UUID()
            guard
                let (_, imageAttachmentUniqueId) =
                    Self.validateLinkPreviewAndBuildUnownedTextAttachment(textAttachment, transaction: transaction)
            else {
                throw OWSAssertionError("Invalid text attachment")
            }

            for (type, conversations) in conversationsByMessageType {
                let destinations = try conversations.lazy.map { conversation -> MultisendDestination in
                    guard let thread = conversation.getOrCreateThread(transaction: transaction) else {
                        throw OWSAssertionError("Missing thread for conversation")
                    }
                    return .init(thread: thread, content: .text(.init(textAttachment, id: attachmentToUploadIdentifier)))
                }

                // This will create TextAttachments and TSAttachments if needed for each destination, but
                // will not actually upload anything.
                // It will map the id we created above to the unique ids of each created TSAttachment in
                // state.correspondingAttachmentIds.
                try type.prepareForMultisending(destinations: destinations, state: state, transaction: transaction)
            }

            if
                let linkPreviewAttachmentId = imageAttachmentUniqueId,
                let correspondingAttachments = state.correspondingAttachmentIds[attachmentToUploadIdentifier]
            {
                // Map the unique ID of the attachment we intend to actually upload to the unique IDs
                // of all the independent attachments that won't be uploaded, so we know to update their
                // metadata down the road.
                state.attachmentIdMap[linkPreviewAttachmentId] = correspondingAttachments
            }
        }

        return PreparedMultisend(
            attachmentIdMap: state.attachmentIdMap,
            messages: state.messages,
            storyMessagesToSend: state.storyMessagesToSend,
            threads: state.threads
        )
    }

    // MARK: - Helpers

    private class func validateLinkPreviewAndBuildUnownedTextAttachment(
        _ textAttachment: UnsentTextAttachment.ForSending,
        transaction: SDSAnyWriteTransaction
    ) -> (TextAttachment, imageAttachmentUniqueId: String?)? {
        var validatedLinkPreview: OWSLinkPreview?
        var imageAttachmentUniqueId: String?
        if let linkPreview = textAttachment.linkPreviewDraft {
            do {
                (validatedLinkPreview, imageAttachmentUniqueId) = try Self.buildValidatedUnownedLinkPreview(
                    fromInfo: linkPreview,
                    ownerType: .story,
                    transaction: transaction
                )
            } catch LinkPreviewError.featureDisabled {
                validatedLinkPreview = .withoutImage(urlString: linkPreview.metadata.urlString, ownerType: .story)
            } catch {
                Logger.error("Failed to generate link preview.")
            }
        }

        guard validatedLinkPreview != nil || !(textAttachment.body?.isEmpty ?? true) else {
            owsFailDebug("Empty content")
            return nil
        }
        return (TextAttachment(
            body: textAttachment.body,
            textStyle: textAttachment.textStyle,
            textForegroundColor: textAttachment.textForegroundColor,
            textBackgroundColor: textAttachment.textBackgroundColor,
            background: textAttachment.background,
            linkPreview: validatedLinkPreview
        ), imageAttachmentUniqueId)
    }

    private class func buildValidatedUnownedLinkPreview(
        fromInfo info: LinkPreviewTSResourceDataSource,
        ownerType: TSResourceOwnerType,
        transaction: SDSAnyWriteTransaction
    ) throws -> (OWSLinkPreview, attachmentUniqueId: String?) {
        guard DependenciesBridge.shared.linkPreviewSettingStore.areLinkPreviewsEnabled(tx: transaction.asV2Read) else {
            throw LinkPreviewError.featureDisabled
        }
        let attachmentUniqueId: String?
        do {
            if
                let attachmentDataSource = info.imageLegacyDataSource
            {
                attachmentUniqueId = try TSAttachmentManager().createAttachmentStream(
                    from: attachmentDataSource,
                    tx: transaction
                )
            } else {
                attachmentUniqueId = nil
            }
        } catch {
            owsFailDebug("Failed to build attachment, error: \(error)")
            attachmentUniqueId = nil
        }
        let linkPreview = attachmentUniqueId.map {
            OWSLinkPreview.withLegacyImageAttachment(
                urlString: info.metadata.urlString,
                title: info.metadata.title,
                attachmentId: $0
            )
        } ?? OWSLinkPreview.withoutImage(
            urlString: info.metadata.urlString,
            title: info.metadata.title,
            ownerType: ownerType
        )
        linkPreview.previewDescription = info.metadata.previewDescription
        linkPreview.date = info.metadata.date
        return (linkPreview, attachmentUniqueId: attachmentUniqueId)
    }

    private class func sendAttachment(preparedSend: Promise<PreparedMultisend>) -> AttachmentMultisend.Result {
        let (enqueuedPromise, enqueuedFuture) = Promise<[TSThread]>.pending()
        let (sentPromise, sentFuture) = Promise<[TSThread]>.pending()

        preparedSend.done(on: ThreadUtil.enqueueSendQueue) { preparedSend in
            return SSKEnvironment.shared.databaseStorageRef.write { transaction in
                // This will upload the TSAttachments whose IDs are the keys of attachmentIdMap
                // and propagate their upload state to each of the TSAttachment unique IDs in the values.
                // Each outgoing destination gets its own TSAttachment per attached media, but we upload only one,
                // and propagate its upload state to each of these independent clones.
                let jobResult = SSKEnvironment.shared.smJobQueuesRef.tsAttachmentMultisendJobQueue.add(
                    attachmentIdMap: preparedSend.attachmentIdMap,
                    storyMessagesToSend: preparedSend.storyMessagesToSend,
                    transaction: transaction
                )
                transaction.addAsyncCompletionOffMain {
                    enqueuedFuture.resolve(preparedSend.threads)
                }
                sentFuture.resolve(
                    on: SyncScheduler(),
                    with: jobResult.sentPromise.map(on: SyncScheduler(), {
                        return preparedSend.threads
                    })
                )
            }

        }.cauterize()

        return .init(
            preparedPromise: preparedSend.map(on: SyncScheduler(), \.messages),
            enqueuedPromise: enqueuedPromise,
            sentPromise: sentPromise
        )
    }
}

class Identified<T> {
    let id: UUID
    let value: T

    init(_ value: T, id: UUID = UUID()) {
        self.id = id
        self.value = value
    }

    func mapValue<V>(_ mapFn: (T) -> V) -> Identified<V> {
        return .init(mapFn(value), id: id)
    }

    func mapValue<V>(_ mapFn: (T) throws -> V) throws -> Identified<V> {
        return .init(try mapFn(value), id: id)
    }
}

enum MultisendContent {
    case media([Identified<SignalAttachment>])
    case text(Identified<UnsentTextAttachment.ForSending>)
}

class MultisendDestination: NSObject {
    let thread: TSThread
    let content: MultisendContent

    init(thread: TSThread, content: MultisendContent) {
        self.thread = thread
        self.content = content
    }
}

class MultisendState: NSObject {
    let approvalMessageBody: MessageBody?
    var messages: [PreparedOutgoingMessage] = []
    var storyMessagesToSend: [OutgoingStoryMessage] = []
    var threads: [TSThread] = []
    var correspondingAttachmentIds: [UUID: [String]] = [:]
    var attachmentIdMap: [String: [String]] = [:]

    init(approvalMessageBody: MessageBody?) {
        self.approvalMessageBody = approvalMessageBody
    }
}

extension ConversationItemMessageType {

    func prepareForMultisending(
        destinations: [MultisendDestination],
        state: MultisendState,
        transaction: SDSAnyWriteTransaction
    ) throws {
        switch self {
        case .message:
            return try TSOutgoingMessage.prepareForMultisending(
                destinations: destinations,
                state: state,
                transaction: transaction
            )
        case .storyMessage:
            return try OutgoingStoryMessage.prepareForMultisending(
                destinations: destinations,
                state: state,
                transaction: transaction
            )
        }
    }
}
