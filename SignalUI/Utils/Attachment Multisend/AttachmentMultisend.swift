//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit

public class AttachmentMultisend: Dependencies {

    public class func sendApprovedMedia(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment]
    ) -> Promise<[TSThread]> {
        return firstly(on: .sharedUserInitiated) { () -> Promise<PreparedMediaMultisend> in
            return self.prepareForSending(
                conversations: conversations,
                approvalMessageBody: approvalMessageBody,
                approvedAttachments: approvedAttachments,
                on: .sharedUserInitiated
            )
        }.map(on: ThreadUtil.enqueueSendQueue) { (preparedSend: PreparedMediaMultisend) -> [TSThread] in
            self.databaseStorage.write { transaction in
                self.broadcastMediaMessageJobQueue.add(
                    attachmentIdMap: preparedSend.attachmentIdMap,
                    unsavedMessagesToSend: preparedSend.unsavedMessages,
                    transaction: transaction
                )
            }

            return preparedSend.threads
        }
    }

    public class func sendApprovedMediaFromShareExtension(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment],
        messagesReadyToSend: (([TSOutgoingMessage]) -> Void)? = nil
    ) -> Promise<[TSThread]> {
        return firstly(on: .sharedUserInitiated) { () -> Promise<PreparedMediaMultisend> in
            return self.prepareForSending(
                conversations: conversations,
                approvalMessageBody: approvalMessageBody,
                approvedAttachments: approvedAttachments,
                on: .sharedUserInitiated
            )
        }
        .then(on: .sharedUserInitiated) { (preparedSend: PreparedMediaMultisend) -> Promise<[TSThread]> in

            messagesReadyToSend?(preparedSend.messages)

            let outgoingMessages = try BroadcastMediaUploader.upload(attachmentIdMap: preparedSend.attachmentIdMap) + preparedSend.unsavedMessages

            var messageSendPromises = [Promise<Void>]()
            databaseStorage.write { transaction in
                for message in outgoingMessages {
                    messageSendPromises.append(ThreadUtil.enqueueMessagePromise(
                        message: message,
                        isHighPriority: true,
                        transaction: transaction
                    ))
                }
            }

            return Promise.when(fulfilled: messageSendPromises).map { preparedSend.threads }
        }
    }

    private struct PreparedMediaMultisend {
        let attachmentIdMap: [String: [String]]
        let messages: [TSOutgoingMessage]
        let unsavedMessages: [TSOutgoingMessage]
        let threads: [TSThread]
    }

    // Used to allow a raw Type as the key of a dictionary
    private struct TypeWrapper: Hashable {
        let type: TSOutgoingMessage.Type

        static func == (lhs: TypeWrapper, rhs: TypeWrapper) -> Bool {
            lhs.type == rhs.type
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(type))
        }
    }

    private class func prepareForSending(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment],
        on queue: DispatchQueue
    ) -> Promise<PreparedMediaMultisend> {
        if let segmentDuration = conversations.lazy.compactMap(\.videoAttachmentDurationLimit).min() {
            let attachmentPromises = approvedAttachments.map {
                $0.preparedForOutput(qualityLevel: .standard)
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
    ) throws -> PreparedMediaMultisend {
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

        var attachmentsByMessageType = [TypeWrapper: [(ConversationItem, [Identified<SignalAttachment>])]]()

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

            let wrappedType = TypeWrapper(type: conversation.outgoingMessageClass)
            var messageTypeArray = attachmentsByMessageType[wrappedType] ?? []
            messageTypeArray.append((conversation, clonedAttachments))
            attachmentsByMessageType[wrappedType] = messageTypeArray
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
                        albumMessageId: nil,
                        isBorderless: attachment.isBorderless,
                        isLoopingVideo: attachment.isLoopingVideo
                    )
                }
            }

        let state = MultisendState(approvalMessageBody: approvalMessageBody)

        try self.databaseStorage.write { transaction in
            for (wrapper, values) in attachmentsByMessageType {
                let destinations = try values.lazy.map { conversation, attachments -> MultisendDestination in
                    guard let thread = conversation.getOrCreateThread(transaction: transaction) else {
                        throw OWSAssertionError("Missing thread for conversation")
                    }
                    return .init(thread: thread, content: .media(attachments))
                }

                try wrapper.type.prepareForMultisending(destinations: destinations, state: state, transaction: transaction)
            }

            // Every attachment we plan to upload should be accounted for, since at least one destination
            // should be using it and have added its UUID to correspondingAttachmentIds.
            owsAssertDebug(state.correspondingAttachmentIds.values.count == attachmentsToUpload.count)

            for attachmentInfo in attachmentsToUpload {
                do {
                    let attachmentToUpload = try attachmentInfo.value.asStreamConsumingDataSource(withIsVoiceMessage: false)
                    attachmentToUpload.anyInsert(transaction: transaction)

                    state.attachmentIdMap[attachmentToUpload.uniqueId] = state.correspondingAttachmentIds[attachmentInfo.id]
                } catch {
                    owsFailDebug("error: \(error)")
                }
            }
        }

        return PreparedMediaMultisend(
            attachmentIdMap: state.attachmentIdMap,
            messages: state.messages,
            unsavedMessages: state.unsavedMessages,
            threads: state.threads)
    }
}

public extension AttachmentMultisend {

    class func sendTextAttachment(
        _ textAttachment: TextAttachment,
        to conversations: [ConversationItem]
    ) -> Promise<[TSThread]> {
        return firstly(on: ThreadUtil.enqueueSendQueue) {
            let preparedSend = try self.prepareForSending(conversations: conversations, textAttachment: textAttachment)
            self.databaseStorage.write { transaction in
                for message in preparedSend.messages {
                    self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
                }
            }
            return preparedSend.threads
        }
    }

    private struct PreparedTextMultisend {
        let messages: [TSOutgoingMessage]
        let threads: [TSThread]
    }

    private class func prepareForSending(
        conversations: [ConversationItem],
        textAttachment: TextAttachment
    ) throws -> PreparedTextMultisend {

        let state = MultisendState(approvalMessageBody: nil)
        let conversationsByMessageType = Dictionary(grouping: conversations, by: { TypeWrapper(type: $0.outgoingMessageClass) })
        try self.databaseStorage.write { transaction in
            for (wrapper, conversations) in conversationsByMessageType {
                let destinations = try conversations.lazy.map { conversation -> MultisendDestination in
                    guard let thread = conversation.getOrCreateThread(transaction: transaction) else {
                        throw OWSAssertionError("Missing thread for conversation")
                    }
                    return .init(thread: thread, content: .text(textAttachment))
                }

                try wrapper.type.prepareForMultisending(destinations: destinations, state: state, transaction: transaction)
            }
        }

        return PreparedTextMultisend(
            messages: state.unsavedMessages,
            threads: state.threads)
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
    case text(TextAttachment)
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
    var messages: [TSOutgoingMessage] = []
    var unsavedMessages: [TSOutgoingMessage] = []
    var threads: [TSThread] = []
    var correspondingAttachmentIds: [UUID: [String]] = [:]
    var attachmentIdMap: [String: [String]] = [:]

    init(approvalMessageBody: MessageBody?) {
        self.approvalMessageBody = approvalMessageBody
    }
}
