//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class OutgoingStoryMessage: TSOutgoingMessage {
    public required init?(coder: NSCoder) {
        self._storyMessageRowId = coder.decodeObject(of: NSNumber.self, forKey: "_storyMessageRowId")
        self.isPrivateStorySend = coder.decodeObject(of: NSNumber.self, forKey: "isPrivateStorySend")
        self.skipSyncTranscript = coder.decodeObject(of: NSNumber.self, forKey: "skipSyncTranscript")
        self.storyAllowsReplies = coder.decodeObject(of: NSNumber.self, forKey: "storyAllowsReplies")
        self.storyMessageId = coder.decodeObject(of: NSString.self, forKey: "storyMessageId") as String?
        super.init(coder: coder)
    }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let _storyMessageRowId {
            coder.encode(_storyMessageRowId, forKey: "_storyMessageRowId")
        }
        if let isPrivateStorySend {
            coder.encode(isPrivateStorySend, forKey: "isPrivateStorySend")
        }
        if let skipSyncTranscript {
            coder.encode(skipSyncTranscript, forKey: "skipSyncTranscript")
        }
        if let storyAllowsReplies {
            coder.encode(storyAllowsReplies, forKey: "storyAllowsReplies")
        }
        if let storyMessageId {
            coder.encode(storyMessageId, forKey: "storyMessageId")
        }
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(_storyMessageRowId)
        hasher.combine(isPrivateStorySend)
        hasher.combine(skipSyncTranscript)
        hasher.combine(storyAllowsReplies)
        hasher.combine(storyMessageId)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self._storyMessageRowId == object._storyMessageRowId else { return false }
        guard self.isPrivateStorySend == object.isPrivateStorySend else { return false }
        guard self.skipSyncTranscript == object.skipSyncTranscript else { return false }
        guard self.storyAllowsReplies == object.storyAllowsReplies else { return false }
        guard self.storyMessageId == object.storyMessageId else { return false }
        return true
    }

    override public func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result._storyMessageRowId = self._storyMessageRowId
        result.isPrivateStorySend = self.isPrivateStorySend
        result.skipSyncTranscript = self.skipSyncTranscript
        result.storyAllowsReplies = self.storyAllowsReplies
        result.storyMessageId = self.storyMessageId
        return result
    }

    public private(set) var storyMessageId: String!
    public private(set) var _storyMessageRowId: NSNumber!
    public var storyMessageRowId: Int64! { _storyMessageRowId?.int64Value }
    public private(set) var storyAllowsReplies: NSNumber!
    public private(set) var isPrivateStorySend: NSNumber!
    public private(set) var skipSyncTranscript: NSNumber!

    public init(
        thread: TSThread,
        storyMessage: StoryMessage,
        storyMessageRowId: Int64,
        storyAllowsReplies: Bool,
        isPrivateStorySend: Bool,
        skipSyncTranscript: Bool,
        transaction: DBReadTransaction,
    ) {
        self.storyMessageId = storyMessage.uniqueId
        self._storyMessageRowId = NSNumber(value: storyMessageRowId)
        self.storyAllowsReplies = NSNumber(value: storyAllowsReplies)
        self.isPrivateStorySend = NSNumber(value: isPrivateStorySend)
        self.skipSyncTranscript = NSNumber(value: skipSyncTranscript)
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            timestamp: storyMessage.timestamp,
        )
        super.init(
            outgoingMessageWith: builder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: transaction,
        )
    }

    @objc
    public convenience init(
        thread: TSThread,
        storyMessage: StoryMessage,
        storyMessageRowId: Int64,
        skipSyncTranscript: Bool = false,
        transaction: DBReadTransaction,
    ) {
        let storyAllowsReplies = (thread as? TSPrivateStoryThread)?.allowsReplies ?? true
        let isPrivateStorySend = thread is TSPrivateStoryThread
        self.init(
            thread: thread,
            storyMessage: storyMessage,
            storyMessageRowId: storyMessageRowId,
            storyAllowsReplies: storyAllowsReplies,
            isPrivateStorySend: isPrivateStorySend,
            skipSyncTranscript: skipSyncTranscript,
            transaction: transaction,
        )
    }

    @objc
    override public var isUrgent: Bool { false }

    override public var isStorySend: Bool { true }

    override public func shouldSyncTranscript() -> Bool { !skipSyncTranscript.boolValue }

    override public func buildTranscriptSyncMessage(
        localThread: TSContactThread,
        transaction: DBWriteTransaction,
    ) -> OWSOutgoingSyncMessage? {
        guard let storyMessage = StoryMessage.anyFetch(uniqueId: storyMessageId, transaction: transaction) else {
            owsFailDebug("Missing story message")
            return nil
        }

        return OutgoingStorySentMessageTranscript(
            localThread: localThread,
            storyMessage: storyMessage,
            transaction: transaction,
        )
    }

    @objc
    override public var shouldBeSaved: Bool { false }
    override var contentHint: SealedSenderContentHint { .implicit }

    override public func contentBuilder(
        thread: TSThread,
        transaction: DBReadTransaction,
    ) -> SSKProtoContentBuilder? {
        guard let storyMessage = storyMessageProto(with: thread, transaction: transaction) else {
            owsFailDebug("Missing story message proto")
            return nil
        }
        let builder = SSKProtoContent.builder()
        builder.setStoryMessage(storyMessage)
        return builder
    }

    @objc
    public func storyMessageProto(with thread: TSThread, transaction: DBReadTransaction) -> SSKProtoStoryMessage? {
        guard
            let storyMessageId,
            let storyMessage = StoryMessage.anyFetch(uniqueId: storyMessageId, transaction: transaction)
        else {
            Logger.warn("Missing story message for outgoing story.")
            return nil
        }

        let builder = SSKProtoStoryMessage.builder()
        builder.setProfileKey(ProtoUtils.localProfileKey(tx: transaction).serialize())

        switch storyMessage.attachment {
        case .media:
            guard
                let storyMessageRowId = storyMessage.id,
                let attachment = DependenciesBridge.shared.attachmentStore.fetchAnyReferencedAttachment(
                    for: .storyMessageMedia(storyMessageRowId: storyMessageRowId),
                    tx: transaction,
                ),
                let pointer = attachment.attachment.asTransitTierPointer(),
                case let .digestSHA256Ciphertext(digestSHA256Ciphertext) = pointer.info.integrityCheck
            else {
                owsFailDebug("Missing attachment for outgoing story message")
                return nil
            }
            let attachmentProto = DependenciesBridge.shared.attachmentManager.buildProtoForSending(
                from: attachment.reference,
                pointer: pointer,
                digestSHA256Ciphertext: digestSHA256Ciphertext,
            )
            builder.setFileAttachment(attachmentProto)
            if let storyMediaCaption = attachment.reference.storyMediaCaption {
                builder.setBodyRanges(storyMediaCaption.toProtoBodyRanges())
            }
        case .text(let attachment):
            guard
                let attachmentProto = try? attachment.buildProto(
                    parentStoryMessage: storyMessage,
                    bodyRangeHandler: builder.setBodyRanges(_:),
                    transaction: transaction,
                )
            else {
                owsFailDebug("Missing attachment for outgoing story message")
                return nil
            }
            builder.setTextAttachment(attachmentProto)
        }

        builder.setAllowsReplies((thread as? TSPrivateStoryThread)?.allowsReplies ?? true)

        do {
            if let groupThread = thread as? TSGroupThread, let groupModel = groupThread.groupModel as? TSGroupModelV2 {
                builder.setGroup(try GroupsV2Protos.buildGroupContextProto(groupModel: groupModel, groupChangeProtoData: nil))
            }

            return try builder.build()
        } catch {
            owsFailDebug("failed to build protobuf: \(error)")
            return nil
        }
    }

    override public func anyUpdateOutgoingMessage(transaction: DBWriteTransaction, block: (TSOutgoingMessage) -> Void) {
        super.anyUpdateOutgoingMessage(transaction: transaction, block: block)

        guard
            let storyMessageId,
            let storyMessage = StoryMessage.anyFetch(
                uniqueId: storyMessageId,
                transaction: transaction,
            )
        else {
            owsFailDebug("Missing story message for outgoing story message")
            return
        }

        storyMessage.updateRecipientStatesWithOutgoingMessageStates(recipientAddressStates, transaction: transaction)
    }

    /// When sending to private stories, each private story list may have overlap in recipients. We want to
    /// dedupe sends such that we only send one copy of a given story to each recipient even though they
    /// are represented in multiple targeted lists.
    ///
    /// Additionally, each private story has different levels of permissions. Some may allow replies & reactions
    /// while others do not. Since we convey to the recipient if this is allowed in the sent proto, it's important that
    /// we send to a recipient only from the thread with the most privilege (or randomly select one with equal privilege)
    public static func createDedupedOutgoingMessages(
        for storyMessage: StoryMessage,
        sendingTo threads: [TSPrivateStoryThread],
        tx: DBWriteTransaction,
    ) -> [OutgoingStoryMessage] {

        class OutgoingMessageBuilder {
            let thread: TSPrivateStoryThread
            let allowsReplies: Bool
            var skippedRecipientIds = Set<SignalRecipient.RowId>()

            init(thread: TSPrivateStoryThread) {
                self.thread = thread
                self.allowsReplies = thread.allowsReplies
            }
        }

        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        let storyRecipientStore = DependenciesBridge.shared.storyRecipientStore

        var messageBuilders = [OutgoingMessageBuilder]()
        var perRecipientIdBuilders = [SignalRecipient.RowId: OutgoingMessageBuilder]()
        for thread in threads {
            let builderForCurrentThread = OutgoingMessageBuilder(thread: thread)
            let storyRecipientIds = failIfThrows {
                return try storyRecipientStore.fetchRecipientIds(forStoryThreadId: thread.sqliteRowId!, tx: tx)
            }
            for recipientId in storyRecipientIds {
                // We only want to send one message per recipient,
                // and it should be the thread with the most privileges.
                guard let existingBuilderForThisRecipient = perRecipientIdBuilders[recipientId] else {
                    // If this is the first time we see this recipient, do nothing.
                    perRecipientIdBuilders[recipientId] = builderForCurrentThread
                    continue
                }
                // Otherwise skip this recipient in the message with _fewer_ privileges.
                if
                    !existingBuilderForThisRecipient.allowsReplies,
                    builderForCurrentThread.allowsReplies
                {
                    // Current thread has more privileges, prefer it for this recipient.
                    existingBuilderForThisRecipient.skippedRecipientIds.insert(recipientId)
                    perRecipientIdBuilders[recipientId] = builderForCurrentThread
                } else {
                    // Existing has more privileges, skip the recipient for the current thread.
                    builderForCurrentThread.skippedRecipientIds.insert(recipientId)
                }
            }
            messageBuilders.append(builderForCurrentThread)
        }

        let outgoingMessages = messageBuilders.enumerated().map { index, builder in
            let message = OutgoingStoryMessage(
                thread: builder.thread,
                storyMessage: storyMessage,
                storyMessageRowId: storyMessage.id!,
                storyAllowsReplies: builder.allowsReplies,
                isPrivateStorySend: true,
                // Only send one sync transcript, even if we're sending to multiple threads
                skipSyncTranscript: index > 0,
                transaction: tx,
            )
            let skippedRecipients = builder.skippedRecipientIds.map {
                return recipientDatabaseTable.fetchRecipient(rowId: $0, tx: tx)!.address
            }
            message.updateWithSkippedRecipients(skippedRecipients, tx: tx)
            return message
        }

        return outgoingMessages
    }
}
