//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import LibSignalClient
import UIKit

@objc
public final class StoryMessage: NSObject, SDSCodableModel {
    public static let databaseTableName = "model_StoryMessage"

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case timestamp
        case authorUuid
        case groupId
        case direction
        case manifest
        case attachment
    }

    public var id: Int64?
    @objc
    public let uniqueId: String
    @objc
    public let timestamp: UInt64

    public let authorUuid: UUID

    @objc
    public var authorAddress: SignalServiceAddress { authorUuid.asSignalServiceAddress() }

    public let groupId: Data?

    public enum Direction: Int, Codable { case incoming = 0, outgoing = 1 }
    public let direction: Direction

    public private(set) var manifest: StoryManifest
    public let attachment: StoryMessageAttachment

    public var sendingState: TSOutgoingMessageState {
        switch manifest {
        case .incoming: return .sent
        case .outgoing(let recipientStates):
            if recipientStates.values.contains(where: { $0.sendingState == .pending }) {
                return .pending
            } else if recipientStates.values.contains(where: { $0.sendingState == .sending }) {
                return .sending
            } else if recipientStates.values.contains(where: { $0.sendingState == .failed }) {
                return .failed
            } else {
                return .sent
            }
        }
    }

    public var localUserViewedTimestamp: UInt64? {
        switch manifest {
        case .incoming(let receivedState):
            return receivedState.viewedTimestamp
        case .outgoing:
            return timestamp
        }
    }

    public var remoteViewCount: Int {
        switch manifest {
        case .incoming:
            return 0
        case .outgoing(let recipientStates):
            return recipientStates.values.lazy.filter { $0.viewedTimestamp != nil }.count
        }
    }

    public var localUserAllowedToReply: Bool {
        switch manifest {
        case .incoming(let receivedState):
            return receivedState.allowsReplies
        case .outgoing:
            return true
        }
    }

    @objc
    public var allAttachmentIds: [String] {
        switch attachment {
        case .file(let attachmentId):
            return [attachmentId]
        case .text(let attachment):
            if let preview = attachment.preview, let imageAttachmentId = preview.imageAttachmentId {
                return [imageAttachmentId]
            } else {
                return []
            }
        }
    }

    public var context: StoryContext { groupId.map { .groupId($0) } ?? .authorUuid(authorUuid) }

    public init(
        timestamp: UInt64,
        authorUuid: UUID,
        groupId: Data?,
        manifest: StoryManifest,
        attachment: StoryMessageAttachment
    ) {
        self.uniqueId = UUID().uuidString
        self.timestamp = timestamp
        self.authorUuid = authorUuid
        self.groupId = groupId
        switch manifest {
        case .incoming:
            self.direction = .incoming
        case .outgoing:
            self.direction = .outgoing
        }
        self.manifest = manifest
        self.attachment = attachment
    }

    @discardableResult
    public static func create(
        withIncomingStoryMessage storyMessage: SSKProtoStoryMessage,
        timestamp: UInt64,
        receivedTimestamp: UInt64,
        author: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) throws -> StoryMessage? {
        Logger.info("Processing StoryMessage from \(author) with timestamp \(timestamp)")

        guard let authorUuid = author.uuid else {
            throw OWSAssertionError("Author is missing UUID")
        }

        let groupId: Data?
        if let masterKey = storyMessage.group?.masterKey {
            let groupContext = try Self.groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
            groupId = groupContext.groupId
        } else {
            groupId = nil
        }

        if let groupId = groupId, blockingManager.isGroupIdBlocked(groupId, transaction: transaction) {
            Logger.warn("Ignoring StoryMessage in blocked group.")
            return nil
        } else if blockingManager.isAddressBlocked(author, transaction: transaction) {
            Logger.warn("Ignoring StoryMessage from blocked author.")
            return nil
        }

        let manifest = StoryManifest.incoming(receivedState: .init(
            allowsReplies: storyMessage.allowsReplies,
            receivedTimestamp: receivedTimestamp
        ))

        let attachment: StoryMessageAttachment
        if let fileAttachment = storyMessage.fileAttachment {
            guard let attachmentPointer = TSAttachmentPointer(fromProto: fileAttachment, albumMessage: nil) else {
                throw OWSAssertionError("Invalid file attachment for StoryMessage.")
            }
            attachmentPointer.anyInsert(transaction: transaction)
            attachment = .file(attachmentId: attachmentPointer.uniqueId)
        } else if let textAttachmentProto = storyMessage.textAttachment {
            attachment = .text(attachment: try TextAttachment(from: textAttachmentProto, transaction: transaction))
        } else {
            throw OWSAssertionError("Missing attachment for StoryMessage.")
        }

        let record = StoryMessage(
            timestamp: timestamp,
            authorUuid: authorUuid,
            groupId: groupId,
            manifest: manifest,
            attachment: attachment
        )
        record.anyInsert(transaction: transaction)

        return record
    }

    @discardableResult
    public static func create(
        withSentTranscript proto: SSKProtoSyncMessageSent,
        transaction: SDSAnyWriteTransaction
    ) throws -> StoryMessage {
        Logger.info("Processing StoryMessage from transcript with timestamp \(proto.timestamp)")

        guard let storyMessage = proto.storyMessage else {
            throw OWSAssertionError("Missing story message on transcript")
        }

        let groupId: Data?
        if let masterKey = storyMessage.group?.masterKey {
            let groupContext = try Self.groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
            groupId = groupContext.groupId
        } else {
            groupId = nil
        }

        let manifest = StoryManifest.outgoing(recipientStates: Dictionary(uniqueKeysWithValues: try proto.storyMessageRecipients.map { recipient in
            guard let uuidString = recipient.destinationUuid,
                  let uuid = UUID(uuidString: uuidString) else {
                throw OWSAssertionError("Invalid UUID on story recipient \(String(describing: recipient.destinationUuid))")
            }

            return (
                key: uuid,
                value: StoryRecipientState(
                    allowsReplies: recipient.isAllowedToReply,
                    contexts: recipient.distributionListIds.compactMap { UUID(uuidString: $0) },
                    sendingState: .sent // This was sent by our linked device
                )
            )
        }))

        let attachment: StoryMessageAttachment
        if let fileAttachment = storyMessage.fileAttachment {
            guard let attachmentPointer = TSAttachmentPointer(fromProto: fileAttachment, albumMessage: nil) else {
                throw OWSAssertionError("Invalid file attachment for StoryMessage.")
            }
            attachmentPointer.anyInsert(transaction: transaction)
            attachment = .file(attachmentId: attachmentPointer.uniqueId)
        } else if let textAttachmentProto = storyMessage.textAttachment {
            attachment = .text(attachment: try TextAttachment(from: textAttachmentProto, transaction: transaction))
        } else {
            throw OWSAssertionError("Missing attachment for StoryMessage.")
        }

        let record = StoryMessage(
            timestamp: proto.timestamp,
            authorUuid: tsAccountManager.localUuid!,
            groupId: groupId,
            manifest: manifest,
            attachment: attachment
        )
        record.anyInsert(transaction: transaction)

        return record
    }

    // The "Signal account" used for e.g. the onboarding story has a fixed UUID
    // we can use to prevent trying to actually reply, send a message, etc.
    public static let systemStoryAuthorUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @discardableResult
    public static func createFromSystemAuthor(
        attachment: TSAttachment,
        timestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) throws -> StoryMessage {
        Logger.info("Processing StoryMessage for system author")

        let manifest = StoryManifest.incoming(
            receivedState: StoryReceivedState(
                allowsReplies: false,
                receivedTimestamp: timestamp,
                viewedTimestamp: nil
            )
        )

        attachment.anyInsert(transaction: transaction)
        let attachment: StoryMessageAttachment = .file(attachmentId: attachment.uniqueId)

        let record = StoryMessage(
            // NOTE: As of now these only get created for the onboarding story, and that happens
            // when you first launch the app. That's probably okay, but if we need something more
            // sophisticated for future stories this is where we'd change it, maybe make this
            // a null timestamp and interpret that different when we read it back out.
            timestamp: timestamp,
            authorUuid: Self.systemStoryAuthorUUID,
            groupId: nil,
            manifest: manifest,
            attachment: attachment
        )
        record.anyInsert(transaction: transaction)

        return record
    }

    // MARK: -

    @objc
    public func markAsViewed(at timestamp: UInt64, circumstance: OWSReceiptCircumstance, transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { record in
            guard case .incoming(let receivedState) = record.manifest else {
                return owsFailDebug("Unexpectedly tried to mark outgoing message as viewed with wrong method.")
            }
            record.manifest = .incoming(receivedState: .init(
                allowsReplies: receivedState.allowsReplies,
                receivedTimestamp: receivedState.receivedTimestamp,
                viewedTimestamp: timestamp
            ))
        }

        // Don't perform thread operations, make downloads, or send receipts for system stories.
        guard !authorAddress.isSystemStoryAddress else {
            return
        }

        switch context {
        case .groupId, .authorUuid, .privateStory:
            // Record on the context when the local user last viewed the story for this context
            if let thread = context.thread(transaction: transaction) {
                thread.updateWithLastViewedStoryTimestamp(NSNumber(value: timestamp), transaction: transaction)
            } else {
                owsFailDebug("Missing thread for story context \(context)")
            }
        case .none:
            owsFailDebug("Viewing invalid story context")
        }

        // If we viewed this story (perhaps from a linked device), we should always make sure it's downloaded if it's not already.
        downloadIfNecessary(transaction: transaction)

        receiptManager.storyWasViewed(self, circumstance: circumstance, transaction: transaction)
    }

    @objc
    public func markAsViewed(at timestamp: UInt64, by recipient: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { record in
            guard case .outgoing(var recipientStates) = record.manifest else {
                return owsFailDebug("Unexpectedly tried to mark incoming message as viewed with wrong method.")
            }

            guard let recipientUuid = recipient.uuid, var recipientState = recipientStates[recipientUuid] else {
                return owsFailDebug("missing recipient for viewed update")
            }

            recipientState.viewedTimestamp = timestamp
            recipientStates[recipientUuid] = recipientState

            record.manifest = .outgoing(recipientStates: recipientStates)
        }
    }

    public func updateRecipients(_ recipients: [SSKProtoSyncMessageSentStoryMessageRecipient], transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { message in
            guard case .outgoing(let recipientStates) = message.manifest else {
                return owsFailDebug("Unexpectedly tried to mark incoming message as viewed with wrong method.")
            }

            var newRecipientStates = [UUID: StoryRecipientState]()

            for recipient in recipients {
                guard let uuidString = recipient.destinationUuid, let uuid = UUID(uuidString: uuidString) else {
                    owsFailDebug("Missing UUID for story recipient")
                    continue
                }

                let newContexts = recipient.distributionListIds.compactMap { UUID(uuidString: $0) }

                if var recipientState = recipientStates[uuid] {
                    recipientState.contexts = newContexts
                    newRecipientStates[uuid] = recipientState
                } else {
                    newRecipientStates[uuid] = .init(
                        allowsReplies: recipient.isAllowedToReply,
                        contexts: newContexts,
                        sendingState: .sent // This was sent by our linked device
                    )
                }
            }

            message.manifest = .outgoing(recipientStates: newRecipientStates)
        }
    }

    public func updateRecipientStates(_ recipientStates: [UUID: StoryRecipientState], transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { message in
            guard case .outgoing = message.manifest else {
                return owsFailDebug("Unexpectedly tried to update recipient states for a non-outgoing message.")
            }

            message.manifest = .outgoing(recipientStates: recipientStates)
        }
    }

    public func updateRecipientStatesWithOutgoingMessageStates(
        _ outgoingMessageStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]?,
        transaction: SDSAnyWriteTransaction
    ) {
        guard let outgoingMessageStates = outgoingMessageStates else { return }
        anyUpdate(transaction: transaction) { message in
            guard case .outgoing(var recipientStates) = message.manifest else {
                return owsFailDebug("Unexpectedly tried to update recipient states on message of wrong type.")
            }

            for (address, outgoingMessageState) in outgoingMessageStates {
                guard let uuid = address.uuid else { continue }
                guard var recipientState = recipientStates[uuid] else { continue }
                recipientState.sendingState = outgoingMessageState.state
                recipientState.sendingErrorCode = outgoingMessageState.errorCode?.intValue
                recipientStates[uuid] = recipientState
            }

            message.manifest = .outgoing(recipientStates: recipientStates)
        }
    }

    public func updateWithAllSendingRecipientsMarkedAsFailed(transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { message in
            guard case .outgoing(var recipientStates) = message.manifest else {
                return owsFailDebug("Unexpectedly tried to recipient states as failed on message of wrong type.")
            }

            for (uuid, var recipientState) in recipientStates {
                guard recipientState.sendingState == .sending else { continue }
                recipientState.sendingState = .failed
                recipientStates[uuid] = recipientState
            }

            message.manifest = .outgoing(recipientStates: recipientStates)
        }
    }

    public func threads(transaction: SDSAnyReadTransaction) -> [TSThread] {
        var threads = [TSThread]()

        if let groupId = groupId, let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
            threads.append(groupThread)
        }

        if case .outgoing(let recipientStates) = manifest {
            for context in Set(recipientStates.values.flatMap({ $0.contexts })) {
                guard let thread = TSPrivateStoryThread.anyFetch(uniqueId: context.uuidString, transaction: transaction) else {
                    owsFailDebug("Missing thread for story context \(context)")
                    continue
                }
                threads.append(thread)
            }
        }

        return threads
    }

    public func downloadIfNecessary(transaction: SDSAnyWriteTransaction) {
        guard
            case .file(let attachmentId) = attachment,
            let pointer = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) as? TSAttachmentPointer,
            ![.enqueued, .downloading].contains(pointer.state)
        else { return }

        attachmentDownloads.enqueueDownloadOfAttachmentsForNewStoryMessage(self, transaction: transaction)
    }

    public func remotelyDelete(for thread: TSThread, transaction: SDSAnyWriteTransaction) {
        guard case .outgoing(var recipientStates) = manifest else {
            return owsFailDebug("Cannot remotely delete incoming story.")
        }

        switch thread {
        case thread as TSGroupThread:
            // Group story deletes are simple, just delete for everyone in the group
            let deleteMessage = TSOutgoingDeleteMessage(
                thread: thread,
                storyMessage: self,
                skippedRecipients: nil,
                transaction: transaction
            )
            messageSenderJobQueue.add(message: deleteMessage.asPreparer, transaction: transaction)
            anyRemove(transaction: transaction)
        case thread as TSPrivateStoryThread:
            // Private story deletes are complicated. We may have sent the private
            // story to the same recipient from multiple contexts. We need to make
            // sure we only delete the story for a given recipient if they can no
            // longer access it from any contexts. We also need to make sure we
            // only delete it for ourselves if nobody has access remaining.
            var hasRemainingRecipients = false
            var skippedRecipients = Set<SignalServiceAddress>()

            guard let threadUuid = UUID(uuidString: thread.uniqueId) else {
                return owsFailDebug("Thread has invalid uniqueId \(thread.uniqueId)")
            }

            for (uuid, var state) in recipientStates {
                if state.contexts.contains(threadUuid) {
                    state.contexts = state.contexts.filter { $0 != threadUuid }

                    // This recipient still has access via other contexts, so
                    // don't send them the delete message yet!
                    if !state.contexts.isEmpty {
                        skippedRecipients.insert(SignalServiceAddress(uuid: uuid))
                    }
                }

                hasRemainingRecipients = hasRemainingRecipients || !state.contexts.isEmpty
                recipientStates[uuid] = state
            }

            let deleteMessage = TSOutgoingDeleteMessage(
                thread: thread,
                storyMessage: self,
                skippedRecipients: skippedRecipients,
                transaction: transaction
            )
            messageSenderJobQueue.add(message: deleteMessage.asPreparer, transaction: transaction)

            if hasRemainingRecipients {
                // Record the updated contexts, so we no longer render it for the one we deleted for.
                updateRecipientStates(recipientStates, transaction: transaction)
            } else {
                // Nobody can see this story anymore, so it can go away entirely.
                anyRemove(transaction: transaction)
            }

            // Send a sent transcript update notifying our linked devices of any context changes.
            let sentTranscriptUpdate = OutgoingStorySentMessageTranscript(
                localThread: TSAccountManager.getOrCreateLocalThread(transaction: transaction)!,
                timestamp: timestamp,
                recipientStates: recipientStates,
                transaction: transaction
            )
            messageSenderJobQueue.add(message: sentTranscriptUpdate.asPreparer, transaction: transaction)
        default:
            owsFailDebug("Cannot remotely delete unexpected thread type \(type(of: thread))")
        }
    }

    public func failedRecipientAddresses(errorCode: Int) -> [SignalServiceAddress] {
        guard case .outgoing(let recipientStates) = manifest else { return [] }

        return recipientStates.filter { _, state in
            return state.sendingState == .failed && errorCode == state.sendingErrorCode
        }.map { .init(uuid: $0.key) }
    }

    public func resendMessageToFailedRecipients(transaction: SDSAnyWriteTransaction) {
        guard case .outgoing(let recipientStates) = manifest else {
            return owsFailDebug("Cannot resend incoming story.")
        }

        Logger.info("Resending story message \(timestamp)")

        var messages = [OutgoingStoryMessage]()
        let threads = threads(transaction: transaction)
        for (idx, thread) in threads.enumerated() {
            let message = OutgoingStoryMessage(
                thread: thread,
                storyMessage: self,
                // Only send one sync transcript, even if we're sending to multiple threads
                skipSyncTranscript: idx > 0,
                transaction: transaction
            )
            messages.append(message)
        }

        // Ensure we only send once per recipient
        OutgoingStoryMessage.dedupePrivateStoryRecipients(for: messages, transaction: transaction)

        // Only send to recipients in the "failed" state
        for (uuid, state) in recipientStates {
            guard state.sendingState != .failed else { continue }
            messages.forEach { $0.update(withSkippedRecipient: .init(uuid: uuid), transaction: transaction) }
        }

        messages.forEach { message in
            messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
        }
    }

    // MARK: -

    public func anyDidRemove(transaction: SDSAnyWriteTransaction) {
        // Delete all group replies for the message.
        InteractionFinder.enumerateGroupReplies(for: self, transaction: transaction) { reply, _ in
            reply.anyRemove(transaction: transaction)
        }

        // Delete all attachments for the message.
        for id in allAttachmentIds {
            guard let attachment = TSAttachment.anyFetch(uniqueId: id, transaction: transaction) else {
                owsFailDebug("Missing attachment for StoryMessage \(id)")
                continue
            }
            attachment.anyRemove(transaction: transaction)
        }
    }

    @objc
    public class func anyEnumerate(
        transaction: SDSAnyReadTransaction,
        batched: Bool = false,
        block: @escaping (StoryMessage, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let batchSize = batched ? Batching.kDefaultBatchSize : 0
        anyEnumerate(transaction: transaction, batchSize: batchSize, block: block)
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(Int.self, forKey: .recordType)
        owsAssertDebug(decodedRecordType == Self.recordType, "Unexpectedly decoded record with wrong type.")

        id = try container.decodeIfPresent(RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)
        timestamp = try container.decode(UInt64.self, forKey: .timestamp)
        authorUuid = try container.decode(UUID.self, forKey: .authorUuid)
        groupId = try container.decodeIfPresent(Data.self, forKey: .groupId)
        direction = try container.decode(Direction.self, forKey: .direction)
        manifest = try container.decode(StoryManifest.self, forKey: .manifest)
        attachment = try container.decode(StoryMessageAttachment.self, forKey: .attachment)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if let id = id { try container.encode(id, forKey: .id) }
        try container.encode(recordType, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(authorUuid, forKey: .authorUuid)
        if let groupId = groupId { try container.encode(groupId, forKey: .groupId) }
        try container.encode(direction, forKey: .direction)
        try container.encode(manifest, forKey: .manifest)
        try container.encode(attachment, forKey: .attachment)
    }
}

public enum StoryManifest: Codable {
    case incoming(receivedState: StoryReceivedState)
    case outgoing(recipientStates: [UUID: StoryRecipientState])
}

public struct StoryReceivedState: Codable {
    public let allowsReplies: Bool
    public var viewedTimestamp: UInt64?
    public var receivedTimestamp: UInt64?

    init(allowsReplies: Bool, receivedTimestamp: UInt64?, viewedTimestamp: UInt64? = nil) {
        self.allowsReplies = allowsReplies
        self.receivedTimestamp = receivedTimestamp
        self.viewedTimestamp = viewedTimestamp
    }
}

public struct StoryRecipientState: Codable {
    public var allowsReplies: Bool
    public var contexts: [UUID]
    @DecodableDefault.OutgoingMessageSending
    public var sendingState: OWSOutgoingMessageRecipientState
    public var sendingErrorCode: Int?
    public var viewedTimestamp: UInt64?

    init(allowsReplies: Bool, contexts: [UUID], sendingState: OWSOutgoingMessageRecipientState = .sending) {
        self.allowsReplies = allowsReplies
        self.contexts = contexts
        self.sendingState = sendingState
    }
}

extension OWSOutgoingMessageRecipientState: Codable {}

public enum StoryMessageAttachment: Codable {
    case file(attachmentId: String)
    case text(attachment: TextAttachment)
}

public struct TextAttachment: Codable {
    public let text: String?

    public enum TextStyle: Int, Codable {
        case regular = 0
        case bold = 1
        case serif = 2
        case script = 3
        case condensed = 4
    }
    public let textStyle: TextStyle

    private let textForegroundColorHex: UInt32?
    public var textForegroundColor: UIColor? { textForegroundColorHex.map { UIColor(argbHex: $0) } }

    private let textBackgroundColorHex: UInt32?
    public var textBackgroundColor: UIColor? { textBackgroundColorHex.map { UIColor(argbHex: $0) } }

    private enum RawBackground: Codable {
        case color(hex: UInt32)
        case gradient(raw: RawGradient)
        struct RawGradient: Codable {
            let colors: [UInt32]
            let positions: [Float]
            let angle: UInt32

            init(colors: [UInt32], positions: [Float], angle: UInt32) {
                self.colors = colors
                self.positions = positions
                self.angle = angle
            }

            enum CodingKeysV1: String, CodingKey {
                case startColorHex, endColorHex, angle
            }

            init(from decoder: Decoder) throws {
                let containerV1: KeyedDecodingContainer<CodingKeysV1> = try decoder.container(keyedBy: CodingKeysV1.self)
                if
                    let startColorHex = try? containerV1.decode(UInt32.self, forKey: .startColorHex),
                    let endColorHex = try? containerV1.decode(UInt32.self, forKey: .endColorHex),
                    let angle = try? containerV1.decode(UInt32.self, forKey: .angle)
                {
                    self.colors = [ startColorHex, endColorHex ]
                    self.positions = [ 0, 1 ]
                    self.angle = angle
                    return
                }
                let containerV2: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
                self.colors = try containerV2.decode([UInt32].self, forKey: .colors)
                self.positions = try containerV2.decode([Float].self, forKey: .positions)
                self.angle = try containerV2.decode(UInt32.self, forKey: .angle)
            }

            func buildProto() throws -> SSKProtoTextAttachmentGradient {
                let builder = SSKProtoTextAttachmentGradient.builder()
                if let startColor = colors.first {
                    builder.setStartColor(startColor)
                }
                if let endColor = colors.last {
                    builder.setEndColor(endColor)
                }
                builder.setColors(colors)
                builder.setPositions(positions)
                builder.setAngle(angle)
                return try builder.build()
            }
        }
    }
    private let rawBackground: RawBackground

    public enum Background {
        case color(UIColor)
        case gradient(Gradient)
        public struct Gradient {
            public init(colors: [UIColor], locations: [CGFloat], angle: UInt32) {
                self.colors = colors
                self.locations = locations
                self.angle = angle
            }
            public init(colors: [UIColor]) {
                let locations: [CGFloat] = colors.enumerated().map { element in
                    return CGFloat(element.offset) / CGFloat(colors.count - 1)
                }
                self.init(colors: colors, locations: locations, angle: 180)
            }
            public let colors: [UIColor]
            public let locations: [CGFloat]
            public let angle: UInt32
        }
    }
    public var background: Background {
        switch rawBackground {
        case .color(let hex):
            return .color(.init(argbHex: hex))
        case .gradient(let rawGradient):
            return .gradient(.init(
                colors: rawGradient.colors.map { UIColor(argbHex: $0) },
                locations: rawGradient.positions.map { CGFloat($0) },
                angle: rawGradient.angle
            ))
        }
    }

    public private(set) var preview: OWSLinkPreview?

    init(from proto: SSKProtoTextAttachment, transaction: SDSAnyWriteTransaction) throws {
        self.text = proto.text?.nilIfEmpty

        guard let style = proto.textStyle else {
            throw OWSAssertionError("Missing style for attachment.")
        }

        switch style {
        case .default, .regular:
            self.textStyle = .regular
        case .bold:
            self.textStyle = .bold
        case .serif:
            self.textStyle = .serif
        case .script:
            self.textStyle = .script
        case .condensed:
            self.textStyle = .condensed
        }

        if proto.hasTextForegroundColor {
            textForegroundColorHex = proto.textForegroundColor
        } else {
            textForegroundColorHex = nil
        }

        if proto.hasTextBackgroundColor {
            textBackgroundColorHex = proto.textBackgroundColor
        } else {
            textBackgroundColorHex = nil
        }

        if let gradient = proto.gradient {
            let colors: [UInt32]
            let positions: [Float]
            if !gradient.colors.isEmpty && !gradient.positions.isEmpty {
                colors = gradient.colors
                positions = gradient.positions
            } else {
                colors = [ gradient.startColor, gradient.endColor ]
                positions = [ 0, 1 ]
            }
            rawBackground = .gradient(raw: .init(
                colors: colors,
                positions: positions,
                angle: gradient.angle
            ))
        } else if proto.hasColor {
            rawBackground = .color(hex: proto.color)
        } else {
            throw OWSAssertionError("Missing background for attachment.")
        }

        if let preview = proto.preview {
            self.preview = try OWSLinkPreview.buildValidatedLinkPreview(proto: preview, transaction: transaction)
        }
    }

    public func buildProto(transaction: SDSAnyReadTransaction) throws -> SSKProtoTextAttachment {
        let builder = SSKProtoTextAttachment.builder()

        if let text = text {
            builder.setText(text)
        }

        let textStyle: SSKProtoTextAttachmentStyle = {
            switch self.textStyle {
            case .regular: return .regular
            case .bold: return .bold
            case .serif: return .serif
            case .script: return .script
            case .condensed: return .condensed
            }
        }()
        builder.setTextStyle(textStyle)

        if let textForegroundColorHex = textForegroundColorHex {
            builder.setTextForegroundColor(textForegroundColorHex)
        }

        if let textBackgroundColorHex = textBackgroundColorHex {
            builder.setTextBackgroundColor(textBackgroundColorHex)
        }

        switch rawBackground {
        case .color(let hex):
            builder.setColor(hex)
        case .gradient(let raw):
            builder.setGradient(try raw.buildProto())
        }

        if let preview = preview {
            builder.setPreview(try preview.buildProto(transaction: transaction))
        }

        return try builder.build()
    }

    public init(text: String,
                textStyle: TextStyle,
                textForegroundColor: UIColor,
                textBackgroundColor: UIColor?,
                background: Background,
                linkPreview: OWSLinkPreview?) {
        self.text = text
        self.textStyle = textStyle
        self.textForegroundColorHex = textForegroundColor.argbHex
        self.textBackgroundColorHex = textBackgroundColor?.argbHex
        self.rawBackground = {
            switch background {
            case .color(let color):
                return .color(hex: color.argbHex)

            case .gradient(let gradient):
                return .gradient(raw: .init(colors: gradient.colors.map { $0.argbHex },
                                            positions: gradient.locations.map { Float($0) },
                                            angle: gradient.angle))
            }
        }()
        self.preview = linkPreview
    }
}

extension SignalServiceAddress {

    public var isSystemStoryAddress: Bool {
        return self.uuid == StoryMessage.systemStoryAuthorUUID
    }
}
