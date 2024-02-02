//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient
import UIKit

@objc
public final class StoryMessage: NSObject, SDSCodableModel, Decodable {
    public static var recordType: UInt { 0 }

    public static let databaseTableName = "model_StoryMessage"

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case timestamp
        case authorAci = "authorUuid"
        case groupId
        case direction
        case manifest
        case attachment
        case replyCount
    }

    public var id: Int64?
    @objc
    public let uniqueId: String
    @objc
    public let timestamp: UInt64

    public let authorAci: Aci

    @objc
    public var authorAddress: SignalServiceAddress { SignalServiceAddress(authorAci) }

    public let groupId: Data?

    public enum Direction: Int, Codable { case incoming = 0, outgoing = 1 }
    public let direction: Direction

    public private(set) var manifest: StoryManifest
    private let _attachment: SerializedStoryMessageAttachment
    public var attachment: StoryMessageAttachment {
        return _attachment.asPublicAttachment
    }

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

    public var hasSentToAnyRecipients: Bool {
        switch manifest {
        case .incoming: return true
        case .outgoing(let recipientStates):
            return recipientStates.values.contains { $0.sendingState == .sent }
        }
    }

    public var localUserReadTimestamp: UInt64? {
        switch manifest {
        case .incoming(let receivedState):
            return receivedState.readTimestamp
        case .outgoing:
            return timestamp
        }
    }

    public var isRead: Bool {
        return localUserReadTimestamp != nil
    }

    public var localUserViewedTimestamp: UInt64? {
        switch manifest {
        case .incoming(let receivedState):
            return receivedState.viewedTimestamp
        case .outgoing:
            return timestamp
        }
    }

    public var isViewed: Bool {
        return localUserViewedTimestamp != nil
    }

    public func remoteViewCount(in context: StoryContext) -> Int {
        switch manifest {
        case .incoming:
            return 0
        case .outgoing(let recipientStates):
            return recipientStates.values
                .lazy
                .filter { $0.isValidForContext(context) }
                .filter { $0.viewedTimestamp != nil }
                .count
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
    public func attachmentUniqueId(tx: SDSAnyReadTransaction) -> String? {
        switch attachment {
        case .file(let file):
            return file.attachmentId
        case .text(let attachment):
            if let preview = attachment.preview, let imageAttachmentId = preview.imageAttachmentId {
                return imageAttachmentId
            } else {
                return nil
            }
        case .foreignReferenceAttachment:
            guard
                let resource = StoryMessageResource.fetch(storyMessage: self, tx: tx),
                let attachment = resource.fetchAttachment(tx: tx)
            else {
                owsFailDebug("Missing attachment for story message \(timestamp)")
                return nil
            }
            return attachment.uniqueId
        }
    }

    public func fileAttachment(tx: SDSAnyReadTransaction) -> TSAttachment? {
        return attachment.fileAttachment(storyMessage: self, tx: tx)
    }

    public var replyCount: UInt64

    public var hasReplies: Bool { replyCount > 0 }

    public var context: StoryContext { groupId.map { .groupId($0) } ?? .authorAci(authorAci) }

    public init(
        timestamp: UInt64,
        authorAci: Aci,
        groupId: Data?,
        manifest: StoryManifest,
        attachment: StoryMessageAttachment,
        replyCount: UInt64
    ) {
        self.uniqueId = UUID().uuidString
        self.timestamp = timestamp
        self.authorAci = authorAci
        self.groupId = groupId
        switch manifest {
        case .incoming:
            self.direction = .incoming
        case .outgoing:
            self.direction = .outgoing
        }
        self.manifest = manifest
        self._attachment = attachment.asSerializable
        self.replyCount = replyCount
    }

    @discardableResult
    public static func create(
        withIncomingStoryMessage storyMessage: SSKProtoStoryMessage,
        timestamp: UInt64,
        receivedTimestamp: UInt64,
        author: Aci,
        transaction: SDSAnyWriteTransaction
    ) throws -> StoryMessage? {
        Logger.info("Processing StoryMessage from \(author) with timestamp \(timestamp)")

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
        } else {
            if blockingManager.isAddressBlocked(SignalServiceAddress(author), transaction: transaction) {
                Logger.warn("Ignoring StoryMessage from blocked author.")
                return nil
            }
            if DependenciesBridge.shared.recipientHidingManager.isHiddenAddress(SignalServiceAddress(author), tx: transaction.asV2Read) {
                Logger.warn("Ignoring StoryMessage from hidden author.")
                return nil
            }
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
            attachment = .file(StoryMessageFileAttachment(
                attachmentId: attachmentPointer.uniqueId,
                storyBodyRangeProtos: storyMessage.bodyRanges
            ))
        } else if let textAttachmentProto = storyMessage.textAttachment {
            attachment = .text(try TextAttachment(
                from: textAttachmentProto,
                bodyRanges: storyMessage.bodyRanges,
                transaction: transaction
            ))
        } else {
            throw OWSAssertionError("Missing attachment for StoryMessage.")
        }

        // Count replies in case any came in out of order (e.g. from a recipient
        // who got the story and replied before we even got it.
        let replyCount = Self.countReplies(
            authorAci: author,
            timestamp: timestamp,
            isGroupStory: groupId != nil,
            transaction
        )

        let record = StoryMessage(
            timestamp: timestamp,
            authorAci: author,
            groupId: groupId,
            manifest: manifest,
            attachment: attachment,
            replyCount: replyCount
        )
        record.anyInsert(transaction: transaction)

        // Nil associated datas are for outgoing contexts, where we don't need to keep track of received timestamp.
        record.context.associatedData(transaction: transaction)?.update(lastReceivedTimestamp: timestamp, transaction: transaction)

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
            guard
                let serviceIdString = recipient.destinationServiceID,
                let serviceId = try? ServiceId.parseFrom(serviceIdString: serviceIdString)
            else {
                throw OWSAssertionError("Invalid ServiceId on story recipient \(String(describing: recipient.destinationServiceID))")
            }

            return (
                key: serviceId,
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
            attachment = .file(StoryMessageFileAttachment(
                attachmentId: attachmentPointer.uniqueId,
                storyBodyRangeProtos: storyMessage.bodyRanges
            ))
        } else if let textAttachmentProto = storyMessage.textAttachment {
            attachment = .text(try TextAttachment(
                from: textAttachmentProto,
                bodyRanges: storyMessage.bodyRanges,
                transaction: transaction
            ))
        } else {
            throw OWSAssertionError("Missing attachment for StoryMessage.")
        }

        let authorAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aci

        // Count replies in some recipient replied and sent us the reply
        // before our linked device sent us the transcript.
        let replyCount = Self.countReplies(
            authorAci: authorAci,
            timestamp: proto.timestamp,
            isGroupStory: groupId != nil,
            transaction
        )

        let record = StoryMessage(
            timestamp: proto.timestamp,
            authorAci: authorAci,
            groupId: groupId,
            manifest: manifest,
            attachment: attachment,
            replyCount: replyCount
        )
        record.anyInsert(transaction: transaction)

        for thread in record.threads(transaction: transaction) {
            thread.updateWithLastSentStoryTimestamp(NSNumber(value: record.timestamp), transaction: transaction)

            // If story sending for a group was implicitly enabled, explicitly enable it
            if let thread = thread as? TSGroupThread, !thread.isStorySendExplicitlyEnabled {
                thread.updateWithStorySendEnabled(true, transaction: transaction)
            }
        }

        return record
    }

    // The "Signal account" used for e.g. the onboarding story has a fixed UUID
    // we can use to prevent trying to actually reply, send a message, etc.
    public static let systemStoryAuthor = Aci(fromUUID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)

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
                readTimestamp: nil,
                viewedTimestamp: nil
            )
        )

        attachment.anyInsert(transaction: transaction)
        let attachment: StoryMessageAttachment = .file(StoryMessageFileAttachment(
            attachmentId: attachment.uniqueId,
            captionStyles: [] /* If someday a system story caption has styles, they'd go here. */
        ))

        let record = StoryMessage(
            // NOTE: As of now these only get created for the onboarding story, and that happens
            // when you first launch the app. That's probably okay, but if we need something more
            // sophisticated for future stories this is where we'd change it, maybe make this
            // a null timestamp and interpret that different when we read it back out.
            timestamp: timestamp,
            authorAci: Self.systemStoryAuthor,
            groupId: nil,
            manifest: manifest,
            attachment: attachment,
            replyCount: 0
        )
        record.anyInsert(transaction: transaction)

        return record
    }

    // MARK: - Marking Read

    @objc
    public func markAsRead(at timestamp: UInt64, circumstance: OWSReceiptCircumstance, transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { record in
            guard case .incoming(let receivedState) = record.manifest else {
                return owsFailDebug("Unexpectedly tried to mark outgoing message as read with wrong method.")
            }
            record.manifest = .incoming(receivedState: .init(
                allowsReplies: receivedState.allowsReplies,
                receivedTimestamp: receivedState.receivedTimestamp,
                readTimestamp: timestamp,
                viewedTimestamp: receivedState.viewedTimestamp
            ))
        }

        // Don't send receipts for system stories or outgoing stories.
        guard !authorAddress.isSystemStoryAddress, direction == .incoming else {
            return
        }

        switch context {
        case .groupId, .authorAci, .privateStory:
            // Record on the context when the local user last read the story for this context
            if let associatedData = context.associatedData(transaction: transaction) {
                associatedData.update(lastReadTimestamp: timestamp, transaction: transaction)
            } else {
                owsFailDebug("Missing associated data for story context \(context)")
            }
        case .none:
            owsFailDebug("Reading invalid story context")
        }

        receiptManager.storyWasRead(self, circumstance: circumstance, transaction: transaction)
    }

    // MARK: - Marking Viewed

    @objc
    public func markAsViewed(at timestamp: UInt64, circumstance: OWSReceiptCircumstance, transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { record in
            guard case .incoming(let receivedState) = record.manifest else {
                return owsFailDebug("Unexpectedly tried to mark outgoing message as viewed with wrong method.")
            }
            record.manifest = .incoming(receivedState: .init(
                allowsReplies: receivedState.allowsReplies,
                receivedTimestamp: receivedState.receivedTimestamp,
                readTimestamp: receivedState.readTimestamp,
                viewedTimestamp: timestamp
            ))
        }

        // Don't perform thread operations, make downloads, or send receipts for system stories.
        guard !authorAddress.isSystemStoryAddress else {
            return
        }

        switch context {
        case .groupId, .authorAci, .privateStory:
            // Record on the context when the local user last viewed the story for this context
            if let associatedData = context.associatedData(transaction: transaction) {
                associatedData.update(lastViewedTimestamp: timestamp, transaction: transaction)
            } else {
                owsFailDebug("Missing associated data for story context \(context)")
            }
        case .none:
            owsFailDebug("Viewing invalid story context")
        }

        // If we viewed this story (perhaps from a linked device), we should always make sure it's downloaded if it's not already.
        downloadIfNecessary(transaction: transaction)

        receiptManager.storyWasViewed(self, circumstance: circumstance, transaction: transaction)
    }

    public func markAsViewed(at timestamp: UInt64, by recipient: Aci, transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { record in
            guard case .outgoing(var recipientStates) = record.manifest else {
                return owsFailDebug("Unexpectedly tried to mark incoming message as viewed with wrong method.")
            }

            // PNI TODO: We need to merge `recipientStates` during Pni/Aci merges.
            guard var recipientState = recipientStates[recipient] else {
                return owsFailDebug("missing recipient for viewed update")
            }

            recipientState.viewedTimestamp = timestamp
            recipientStates[recipient] = recipientState

            record.manifest = .outgoing(recipientStates: recipientStates)
        }
    }

    // MARK: - Reply Counts

    public func incrementReplyCount(_ tx: SDSAnyWriteTransaction) {
        anyUpdate(transaction: tx) { record in
            record.replyCount += 1
        }
    }

    public func decrementReplyCount(_ tx: SDSAnyWriteTransaction) {
        anyUpdate(transaction: tx) { record in
            record.replyCount = max(0, record.replyCount - 1)
        }
    }

    private static func countReplies(
        authorAci: Aci,
        timestamp: UInt64,
        isGroupStory: Bool,
        _ tx: SDSAnyReadTransaction
    ) -> UInt64 {
        if authorAci == StoryMessage.systemStoryAuthor {
            // No replies on system stories.
            return 0
        }
        do {
            let sql: String = """
                SELECT COUNT(*)
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .storyTimestamp) = ?
                AND \(interactionColumn: .storyAuthorUuidString) = ?
                AND \(interactionColumn: .isGroupStoryReply) = ?
            """
            guard let count = try UInt64.fetchOne(
                tx.unwrapGrdbRead.database,
                sql: sql,
                arguments: [timestamp, authorAci.serviceIdUppercaseString, isGroupStory]
            ) else {
                throw OWSAssertionError("count was unexpectedly nil")
            }
            return count
        } catch {
            owsFail("error: \(error)")
        }
    }

    // MARK: -

    public func updateRecipients(_ recipients: [SSKProtoSyncMessageSentStoryMessageRecipient], transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { message in
            guard case .outgoing(let recipientStates) = message.manifest else {
                return owsFailDebug("Unexpectedly tried to mark incoming message as viewed with wrong method.")
            }

            var newRecipientStates = [ServiceId: StoryRecipientState]()

            for recipient in recipients {
                guard
                    let serviceIdString = recipient.destinationServiceID,
                    let serviceId = try? ServiceId.parseFrom(serviceIdString: serviceIdString)
                else {
                    owsFailDebug("Missing UUID for story recipient")
                    continue
                }

                let newContexts = recipient.distributionListIds.compactMap { UUID(uuidString: $0) }

                if var recipientState = recipientStates[serviceId] {
                    recipientState.contexts = newContexts
                    newRecipientStates[serviceId] = recipientState
                } else {
                    newRecipientStates[serviceId] = .init(
                        allowsReplies: recipient.isAllowedToReply,
                        contexts: newContexts,
                        sendingState: .sent // This was sent by our linked device
                    )
                }
            }

            message.manifest = .outgoing(recipientStates: newRecipientStates)
        }
    }

    public func updateRecipientStates(_ recipientStates: [ServiceId: StoryRecipientState], transaction: SDSAnyWriteTransaction) {
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

        notifyingOfFailureIfNeeded(transaction: transaction) { firstFailedThread in
            anyUpdate(transaction: transaction) { message in
                guard case .outgoing(var recipientStates) = message.manifest else {
                    return owsFailDebug("Unexpectedly tried to update recipient states on message of wrong type.")
                }

                for (address, outgoingMessageState) in outgoingMessageStates {
                    guard let serviceId = address.serviceId else { continue }
                    guard var recipientState = recipientStates[serviceId] else { continue }

                    // Only take the sending state from the message if we're in a transient state
                    if recipientState.sendingState != .sent {
                        recipientState.sendingState = outgoingMessageState.state
                    }
                    if outgoingMessageState.state == .failed, firstFailedThread == nil {
                        if let context = recipientState.firstValidContext() {
                            firstFailedThread = context.thread(transaction: transaction)
                        } else if let groupId {
                            // Group recipient.
                            firstFailedThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction)
                        }
                    }

                    recipientState.sendingErrorCode = outgoingMessageState.errorCode?.intValue
                    recipientStates[serviceId] = recipientState
                }

                message.manifest = .outgoing(recipientStates: recipientStates)
            }
        }
    }

    public func updateWithAllSendingRecipientsMarkedAsFailed(transaction: SDSAnyWriteTransaction) {
        notifyingOfFailureIfNeeded(transaction: transaction) { firstFailedThread in
            anyUpdate(transaction: transaction) { message in
                guard case .outgoing(var recipientStates) = message.manifest else {
                    return owsFailDebug("Unexpectedly tried to recipient states as failed on message of wrong type.")
                }

                for (uuid, var recipientState) in recipientStates {
                    guard recipientState.sendingState == .sending else { continue }

                    if firstFailedThread == nil {
                        if let context = recipientState.firstValidContext() {
                            firstFailedThread = context.thread(transaction: transaction)
                        } else if let groupId {
                            // Group recipient.
                            firstFailedThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction)
                        }
                    }

                    recipientState.sendingState = .failed
                    recipientStates[uuid] = recipientState
                }

                message.manifest = .outgoing(recipientStates: recipientStates)
            }
        }
    }

    private func notifyingOfFailureIfNeeded(
        transaction: SDSAnyWriteTransaction,
        _ block: (_ firstFailedThread: inout TSThread?) -> Void
    ) {
        let wasFailedSendBeforeUpdate = sendingState == .failed
        var firstFailedThread: TSThread?

        block(&firstFailedThread)

        if !wasFailedSendBeforeUpdate, sendingState == .failed, let firstFailedThread {
            // If we are newly failing, fire a notification.
            notificationPresenter.notifyUser(
                forFailedStorySend: self,
                to: firstFailedThread,
                transaction: transaction
            )
        } else if wasFailedSendBeforeUpdate, sendingState != .failed {
            notificationPresenter.cancelNotifications(for: self)
        }
    }

    /// If the story is incoming, returns a single-element array with the TSContactThread for the author if the
    /// story was sent as a private story, or the TSGroupThread if the story was sent to a group.
    /// If the story is outgoing, returns either a single-element array with the TSGroupThread if the story was sent
    /// to a group, or an array of TSPrivateStoryThreads for all the private threads the story was sent to.
    public func threads(transaction: SDSAnyReadTransaction) -> [TSThread] {
        switch manifest {
        case .incoming:
            if let groupId = groupId, let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
                return [groupThread]
            } else if let contactThread = TSContactThread.getWithContactAddress(SignalServiceAddress(authorAci), transaction: transaction) {
                return [contactThread]
            } else {
                owsFailDebug("No thread found for an incoming story message")
                return []
            }
        case .outgoing(let recipientStates):
            if let groupId = groupId, let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
                return [groupThread]
            }
            return Set(recipientStates.values.flatMap({ $0.contexts })).compactMap { context in
                guard let thread = TSPrivateStoryThread.anyFetch(uniqueId: context.uuidString, transaction: transaction) else {
                    owsFailDebug("Missing thread for story context \(context)")
                    return nil
                }
                return thread
            }
        }
    }

    public func downloadIfNecessary(transaction: SDSAnyWriteTransaction) {
        switch attachment {
        case .file(let file):
            guard
                let pointer = TSAttachment.anyFetch(
                    uniqueId: file.attachmentId,
                    transaction: transaction
                ) as? TSAttachmentPointer,
                ![.enqueued, .downloading].contains(pointer.state)
            else {
                return
            }
            attachmentDownloads.enqueueDownloadOfAttachmentsForNewStoryMessage(self, transaction: transaction)
        case .foreignReferenceAttachment:
            guard
                let resource = StoryMessageResource.fetch(storyMessage: self, tx: transaction),
                let pointer = resource.fetchAttachment(tx: transaction) as? TSAttachmentPointer,
                ![.enqueued, .downloading].contains(pointer.state)
            else {
                owsFailDebug("Missing attachment for story message \(timestamp)")
                return
            }
            attachmentDownloads.enqueueDownloadOfAttachmentsForNewStoryMessage(self, transaction: transaction)
        case .text:
            return
        }
    }

    public func remotelyDeleteForAllRecipients(transaction: SDSAnyWriteTransaction) {
        for thread in threads(transaction: transaction) {
            remotelyDelete(for: thread, transaction: transaction)
        }
    }

    public func remotelyDelete(for thread: TSThread, transaction: SDSAnyWriteTransaction) {
        guard case .outgoing(var recipientStates) = manifest else {
            return owsFailDebug("Cannot remotely delete incoming story.")
        }

        switch thread {
        case thread as TSGroupThread:
            Logger.info("Remotely deleting group story with timestamp \(timestamp)")

            // Group story deletes are simple, just delete for everyone in the group
            let deleteMessage = TSOutgoingDeleteMessage(
                thread: thread,
                storyMessage: self,
                skippedRecipients: nil,
                transaction: transaction
            )
            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: deleteMessage.asPreparer, transaction: transaction)
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

            Logger.info("Remotely deleting private story with timestamp \(timestamp) from dList \(thread.uniqueId)")

            for (serviceId, var state) in recipientStates {
                if state.contexts.contains(threadUuid) {
                    state.contexts = state.contexts.filter { $0 != threadUuid }

                    // This recipient still has access via other contexts, so
                    // don't send them the delete message yet!
                    if !state.contexts.isEmpty {
                        skippedRecipients.insert(SignalServiceAddress(serviceId))
                    }
                }

                hasRemainingRecipients = hasRemainingRecipients || !state.contexts.isEmpty
                recipientStates[serviceId] = state
            }

            let deleteMessage = TSOutgoingDeleteMessage(
                thread: thread,
                storyMessage: self,
                skippedRecipients: skippedRecipients,
                transaction: transaction
            )
            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: deleteMessage.asPreparer, transaction: transaction)

            if hasRemainingRecipients {
                // Record the updated contexts, so we no longer render it for the one we deleted for.
                updateRecipientStates(recipientStates, transaction: transaction)
            } else {
                // Nobody can see this story anymore, so it can go away entirely.
                anyRemove(transaction: transaction)
            }

            // Send a sent transcript update notifying our linked devices of any context changes.
            let sentTranscriptUpdate = OutgoingStorySentMessageTranscript(
                localThread: TSContactThread.getOrCreateLocalThread(transaction: transaction)!,
                timestamp: timestamp,
                recipientStates: recipientStates,
                transaction: transaction
            )
            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: sentTranscriptUpdate.asPreparer, transaction: transaction)
        default:
            owsFailDebug("Cannot remotely delete unexpected thread type \(type(of: thread))")
        }
    }

    public func failedRecipientAddresses(errorCode: Int) -> [SignalServiceAddress] {
        guard case .outgoing(let recipientStates) = manifest else { return [] }

        return recipientStates.filter { _, state in
            return state.sendingState == .failed && errorCode == state.sendingErrorCode
        }.map { SignalServiceAddress($0.key) }
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
        for (serviceId, state) in recipientStates {
            guard state.sendingState != .failed else { continue }
            messages.forEach { $0.update(withSkippedRecipient: SignalServiceAddress(serviceId), transaction: transaction) }
        }

        messages.forEach { message in
            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: message.asPreparer, transaction: transaction)
        }
    }

    // MARK: -

    public func anyDidRemove(transaction: SDSAnyWriteTransaction) {
        // Delete all group replies for the message.
        InteractionFinder.enumerateGroupReplies(for: self, transaction: transaction) { reply, _ in
            reply.anyRemove(transaction: transaction)
        }

        // Delete all attachments for the message.
        if let id = attachmentUniqueId(tx: transaction) {
            if let attachment = TSAttachment.anyFetch(uniqueId: id, transaction: transaction) {
                attachment.anyRemove(transaction: transaction)
            } else {
                owsFailDebug("Missing attachment for StoryMessage \(id)")
            }
        }

        // Reload latest unexpired timestamp for the context.
        self.context.associatedData(transaction: transaction)?.recomputeLatestUnexpiredTimestamp(transaction: transaction)

        notificationPresenter.cancelNotifications(for: self)
    }

    @objc
    public static func anyEnumerateObjc(
        transaction: SDSAnyReadTransaction,
        batched: Bool,
        block: @escaping (StoryMessage, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let batchingPreference: BatchingPreference = batched ? .batched() : .unbatched
        anyEnumerate(transaction: transaction, batchingPreference: batchingPreference, block: block)
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(Int.self, forKey: .recordType)
        owsAssertDebug(decodedRecordType == Self.recordType, "Unexpectedly decoded record with wrong type.")

        id = try container.decodeIfPresent(RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)
        timestamp = try container.decode(UInt64.self, forKey: .timestamp)
        authorAci = Aci(fromUUID: try container.decode(UUID.self, forKey: .authorAci))
        groupId = try container.decodeIfPresent(Data.self, forKey: .groupId)
        direction = try container.decode(Direction.self, forKey: .direction)
        manifest = StoryManifest(try container.decode(CodableStoryManifest.self, forKey: .manifest))
        _attachment = try container.decode(SerializedStoryMessageAttachment.self, forKey: .attachment)
        replyCount = try container.decode(UInt64.self, forKey: .replyCount)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if let id = id { try container.encode(id, forKey: .id) }
        try container.encode(Self.recordType, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(authorAci.rawUUID, forKey: .authorAci)
        if let groupId = groupId { try container.encode(groupId, forKey: .groupId) }
        try container.encode(direction, forKey: .direction)
        try container.encode(CodableStoryManifest(manifest), forKey: .manifest)
        try container.encode(_attachment, forKey: .attachment)
        try container.encode(replyCount, forKey: .replyCount)
    }
}

public enum StoryManifest {
    case incoming(receivedState: StoryReceivedState)
    case outgoing(recipientStates: [ServiceId: StoryRecipientState])

    fileprivate init(_ codableStoryManifest: CodableStoryManifest) {
        switch codableStoryManifest {
        case .incoming(let receivedState):
            self = .incoming(receivedState: receivedState)
        case .outgoing(let recipientStates):
            self = .outgoing(recipientStates: recipientStates.mapKeys(injectiveTransform: { $0.wrappedValue }))
        }
    }
}

private enum CodableStoryManifest: Codable {
    case incoming(receivedState: StoryReceivedState)
    case outgoing(recipientStates: [ServiceIdUppercaseString: StoryRecipientState])

    init(_ storyManifest: StoryManifest) {
        switch storyManifest {
        case .incoming(let receivedState):
            self = .incoming(receivedState: receivedState)
        case .outgoing(let recipientStates):
            self = .outgoing(recipientStates: recipientStates.mapKeys(injectiveTransform: { $0.codableUppercaseString }))
        }
    }
}

public struct StoryReceivedState: Codable {
    public let allowsReplies: Bool
    public var receivedTimestamp: UInt64?
    // All current stories are "read" when the user goes to the stories tab.
    public var readTimestamp: UInt64?
    // Stories are "viewed" when the user opens them up individually for viewing.
    public var viewedTimestamp: UInt64?

    init(
        allowsReplies: Bool,
        receivedTimestamp: UInt64?,
        readTimestamp: UInt64? = nil,
        viewedTimestamp: UInt64? = nil
    ) {
        self.allowsReplies = allowsReplies
        self.receivedTimestamp = receivedTimestamp
        self.readTimestamp = readTimestamp
        self.viewedTimestamp = viewedTimestamp
    }
}

public struct StoryRecipientState: Codable {
    public var allowsReplies: Bool
    public var contexts: [UUID]
    @DecodableDefault.OutgoingMessageSending public var sendingState: OWSOutgoingMessageRecipientState
    public var sendingErrorCode: Int?
    public var viewedTimestamp: UInt64?

    init(allowsReplies: Bool, contexts: [UUID], sendingState: OWSOutgoingMessageRecipientState = .sending) {
        self.allowsReplies = allowsReplies
        self.contexts = contexts
        self.sendingState = sendingState
    }
}

extension StoryRecipientState {
    public func isValidForContext(_ context: StoryContext) -> Bool {
        switch context {
        case .privateStory(let uuidString):
            guard let uuid = UUID(uuidString: uuidString) else {
                owsFailDebug("Invalid UUID for private story")
                return false
            }
            return contexts.contains(uuid)
        case .groupId, .authorAci:
            return true
        case .none:
            return false
        }
    }

    /// If this recipient is present on multiple private story threads that the same
    /// story message was sent to, there isn't really a sense in which they received
    /// the story "on" any given one of those threads, its kind of on all of them.
    /// Just pick the first valid one, preferring My Story if present.
    public func firstValidContext() -> StoryContext? {
        var firstValidContext: StoryContext?
        for threadId in contexts {
            // Prefer my story as the "first" valid context, if present.
            if threadId.uuidString == TSPrivateStoryThread.myStoryUniqueId {
                return .privateStory(threadId.uuidString)

            }
            guard firstValidContext == nil else {
                continue
            }
            firstValidContext = .privateStory(threadId.uuidString)
        }
        return firstValidContext
    }
}

extension OWSOutgoingMessageRecipientState: Codable {}

extension SignalServiceAddress {

    public var isSystemStoryAddress: Bool {
        return self.serviceId == StoryMessage.systemStoryAuthor
    }
}

// MARK: - Video Duration Limiting

extension StoryMessage {

    // Android rounds _down_ video length for display, so 30.999 seconds
    // is rendered as "30s". If we didn't allow that length, users might be
    // confused as to why if all it says is "30s" and we say "up to 30s".
    public static let videoAttachmentDurationLimit: TimeInterval = 30.999

    public static var videoSegmentationTooltip: String {
        return String(
            format: OWSLocalizedString(
                "STORY_VIDEO_SEGMENTATION_TOOLTIP_FORMAT",
                comment: "Tooltip text shown when the user selects a story as a destination for a long duration video that will be split into shorter segments. Embeds {{ segment duration in seconds }}"
            ),
            Int(videoAttachmentDurationLimit)
        )
    }
}
