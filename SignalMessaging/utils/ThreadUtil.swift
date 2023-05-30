//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// MARK: - Enqueue messages

public final class ThreadUtil: Dependencies {

    public typealias PersistenceCompletion = () -> Void

    // A serial queue that ensures that messages are sent in the
    // same order in which they are enqueued.
    public static var enqueueSendQueue: DispatchQueue { .sharedUserInitiated }

    public static func enqueueSendAsyncWrite(_ block: @escaping (SDSAnyWriteTransaction) -> Void) {
        enqueueSendQueue.async {
            Self.databaseStorage.write { transaction in
                block(transaction)
            }
        }
    }

    @discardableResult
    class func enqueueMessage(outgoingMessageBuilder builder: TSOutgoingMessageBuilder,
                              thread: TSThread) -> TSOutgoingMessage {

        let message: TSOutgoingMessage = databaseStorage.read { transaction in
            builder.expiresInSeconds = thread.disappearingMessagesDuration(with: transaction)
            return builder.build(transaction: transaction)
        }

        Self.enqueueSendAsyncWrite { transaction in
            message.anyInsert(transaction: transaction)
            self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
            if message.hasRenderableContent() { thread.donateSendMessageIntent(for: message, transaction: transaction) }
        }

        return message
    }

    @discardableResult
    class func enqueueMessage(outgoingMessageBuilder builder: TSOutgoingMessageBuilder,
                              thread: TSThread,
                              transaction: SDSAnyWriteTransaction) -> TSOutgoingMessage {

        builder.expiresInSeconds = thread.disappearingMessagesDuration(with: transaction)

        let message = builder.build(transaction: transaction)
        message.anyInsert(transaction: transaction)
        self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)

        if message.hasRenderableContent() { thread.donateSendMessageIntent(for: message, transaction: transaction) }

        return message
    }

    public class func enqueueMessagePromise(
        message: TSOutgoingMessage,
        limitToCurrentProcessLifetime: Bool = false,
        isHighPriority: Bool = false,
        transaction: SDSAnyWriteTransaction
    ) -> Promise<Void> {
        let promise = sskJobQueues.messageSenderJobQueue.add(
            .promise,
            message: message.asPreparer,
            limitToCurrentProcessLifetime: limitToCurrentProcessLifetime,
            isHighPriority: isHighPriority,
            transaction: transaction
        )
        if message.hasRenderableContent() {
            message
                .thread(transaction: transaction)
                .donateSendMessageIntent(for: message, transaction: transaction)
        }
        return promise
    }
}

// MARK: - Contact Shares

public extension ThreadUtil {

    @discardableResult
    class func enqueueMessage(withContactShare contactShare: OWSContact, thread: TSThread) -> TSOutgoingMessage {
        AssertIsOnMainThread()
        assert(contactShare.ows_isValid())

        let builder = TSOutgoingMessageBuilder(thread: thread)
        builder.contactShare = contactShare

        return enqueueMessage(outgoingMessageBuilder: builder, thread: thread)
    }
}

// MARK: - Stickers

public extension ThreadUtil {

    @discardableResult
    class func enqueueMessage(withInstalledSticker stickerInfo: StickerInfo, thread: TSThread) -> TSOutgoingMessage {
        AssertIsOnMainThread()

        let message = buildOutgoingMessageForSticker(stickerInfo, thread: thread)
        DispatchQueue.global().async {
            guard let stickerMetadata = StickerManager.installedStickerMetadataWithSneakyTransaction(stickerInfo: stickerInfo) else {
                owsFailDebug("Could not find sticker file.")
                return
            }

            guard let stickerData = try? Data(contentsOf: stickerMetadata.stickerDataUrl) else {
                owsFailDebug("Couldn't load sticker data.")
                return
            }

            let stickerDraft = MessageStickerDraft(
                info: stickerInfo,
                stickerData: stickerData,
                stickerType: stickerMetadata.stickerType,
                emoji: stickerMetadata.firstEmoji
            )
            enqueueMessage(message, stickerDraft: stickerDraft, thread: thread)
        }
        return message
    }

    @discardableResult
    class func enqueueMessage(
        withUninstalledSticker stickerMetadata: StickerMetadata,
        stickerData: Data,
        thread: TSThread
    ) -> TSOutgoingMessage {
        AssertIsOnMainThread()

        let message = buildOutgoingMessageForSticker(stickerMetadata.stickerInfo, thread: thread)
        let stickerDraft = MessageStickerDraft(
            info: stickerMetadata.stickerInfo,
            stickerData: stickerData,
            stickerType: stickerMetadata.stickerType,
            emoji: stickerMetadata.firstEmoji
        )

        enqueueMessage(message, stickerDraft: stickerDraft, thread: thread)

        return message
   }

    private class func buildOutgoingMessageForSticker(_ stickerInfo: StickerInfo, thread: TSThread) -> TSOutgoingMessage {
        AssertIsOnMainThread()

        let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread)
        let message = databaseStorage.read { transaction in
            builder.expiresInSeconds = thread.disappearingMessagesDuration(with: transaction)
            return builder.build(transaction: transaction)
        }
        return message
    }

    private class func enqueueMessage(_ message: TSOutgoingMessage, stickerDraft: MessageStickerDraft, thread: TSThread) {
        AssertIsOnMainThread()

        enqueueSendAsyncWrite { transaction in
            guard let messageSticker = messageStickerForStickerDraft(stickerDraft, transaction: transaction) else {
                owsFailDebug("Couldn't send sticker.")
                return
            }

            message.anyInsert(transaction: transaction)
            message.update(with: messageSticker, transaction: transaction)

            self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)

            thread.donateSendMessageIntent(for: message, transaction: transaction)
        }

    }

    private class func messageStickerForStickerDraft(
        _ stickerDraft: MessageStickerDraft,
        transaction: SDSAnyWriteTransaction
    ) -> MessageSticker? {
        do {
            let messageSticker = try MessageSticker.buildValidatedMessageSticker(fromDraft: stickerDraft, transaction: transaction)
            return messageSticker
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }
}

// MARK: - Profile Whitelist

public extension ThreadUtil {

    @discardableResult
    class func addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(
        thread: TSThread
    ) -> Bool {

        let (hasPendingMessageRequest, needsDefaultTimerSet, defaultTimerToken) = databaseStorage.read { transaction in
            let hasPendingMessageRequest = thread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead)
            let needsDefaultTimerSet = GRDBThreadFinder.shouldSetDefaultDisappearingMessageTimer(thread: thread, transaction: transaction.unwrapGrdbRead)
            let defaultTimerToken = OWSDisappearingMessagesConfiguration.fetchOrBuildDefaultUniversalConfiguration(with: transaction).asToken

            return (hasPendingMessageRequest, needsDefaultTimerSet, defaultTimerToken)
        }

        if needsDefaultTimerSet {
            databaseStorage.write { transaction in
                let configuration = OWSDisappearingMessagesConfiguration.applyToken(
                    defaultTimerToken,
                    toThread: thread,
                    transaction: transaction
                )
                let infoMessage = OWSDisappearingConfigurationUpdateInfoMessage(
                    thread: thread,
                    configuration: configuration,
                    createdByRemoteName: nil,
                    createdInExistingGroup: false
                )
                infoMessage.anyInsert(transaction: transaction)
            }
        }

        // If we're creating this thread or we have a pending message request,
        // any action we trigger should share our profile.
        if !thread.shouldThreadBeVisible || hasPendingMessageRequest {
            OWSProfileManager.shared.addThread(toProfileWhitelist: thread)
            return true
        }

        return false
    }

    @discardableResult
    class func addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimer(
        thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) -> Bool {
        addThreadToProfileWhitelistIfEmptyOrPendingRequest(
            thread: thread,
            setDefaultTimerIfNecessary: true,
            transaction: transaction
        )
    }

    @discardableResult
    class func addThreadToProfileWhitelistIfEmptyOrPendingRequest(
        thread: TSThread,
        setDefaultTimerIfNecessary: Bool,
        transaction: SDSAnyWriteTransaction
    ) -> Bool {

        let defaultTimerToken = OWSDisappearingMessagesConfiguration.fetchOrBuildDefaultUniversalConfiguration(with: transaction).asToken
        let needsDefaultTimerSest = GRDBThreadFinder.shouldSetDefaultDisappearingMessageTimer(thread: thread, transaction: transaction.unwrapGrdbRead)

        if needsDefaultTimerSest && setDefaultTimerIfNecessary {
            let configuration = OWSDisappearingMessagesConfiguration.applyToken(
                defaultTimerToken,
                toThread: thread,
                transaction: transaction
            )
            let infoMessage = OWSDisappearingConfigurationUpdateInfoMessage(
                thread: thread,
                configuration: configuration,
                createdByRemoteName: nil,
                createdInExistingGroup: false
            )
            infoMessage.anyInsert(transaction: transaction)
        }

        let hasPendingMessageRequest = thread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead)
        // If we're creating this thread or we have a pending message request,
        // any action we trigger should share our profile.
        if !thread.shouldThreadBeVisible || hasPendingMessageRequest {
            OWSProfileManager.shared.addThread(toProfileWhitelist: thread, transaction: transaction)
            return true
        }

        return false
    }
}

// MARK: - Delete all content

extension ThreadUtil {
    public static func deleteAllContentWithSneakyTransaction() {
        Logger.info("")

        databaseStorage.write { transaction in
            TSThread.anyEnumerate(transaction: transaction, batched: true) { thread, _ in
                thread.softDelete(with: transaction)
            }

            TSInteraction.anyRemoveAllWithInstantation(transaction: transaction)
            StoryMessage.anyRemoveAllWithInstantiation(transaction: transaction)
            TSAttachment.anyRemoveAllWithInstantation(transaction: transaction)

            // Deleting attachments above should be enough to remove any gallery items, but
            // we redunantly clean up *all* gallery items to be safe.
            MediaGalleryManager.didRemoveAllContent(transaction: transaction)
        }

        TSAttachmentStream.deleteAttachmentsFromDisk()
    }
}

// MARK: - Sharing Suggestions

import Intents

extension TSThread {

    /// This function should be called every time the user
    /// initiates message sending via the UI. It should *not*
    /// be called for messages we send automatically, like
    /// receipts.
    public func donateSendMessageIntent(for outgoingMessage: TSOutgoingMessage, transaction: SDSAnyReadTransaction) {
        // We never need to do this pre-iOS 13, because sharing
        // suggestions aren't support in previous iOS versions.
        guard #available(iOS 13, *) else { return }

        // Never donate for story sends or replies, we don't want them as share suggestions
        guard
            !(outgoingMessage is OutgoingStoryMessage),
            !outgoingMessage.isGroupStoryReply
        else {
            return
        }

        guard SSKPreferences.areIntentDonationsEnabled(transaction: transaction) else { return }
        guard let sendMessageIntent = generateSendMessageIntent(context: .outgoingMessage(outgoingMessage), transaction: transaction) else { return }

        let interaction = INInteraction(intent: sendMessageIntent, response: nil)
        interaction.groupIdentifier = uniqueId
        interaction.direction = .outgoing
        interaction.donate(completion: { error in
            guard let error = error else { return }
            owsFailDebug("Failed to donate message intent for \(self.uniqueId) \(error)")
        })
    }

    public enum IntentContext {
        case senderAddress(SignalServiceAddress)
        case incomingMessage(TSIncomingMessage)
        case outgoingMessage(TSOutgoingMessage)
    }

    public func generateSendMessageIntent(context: IntentContext, transaction: SDSAnyReadTransaction) -> INSendMessageIntent? {
        // We never need to do this pre-iOS 13, because sharing
        // suggestions aren't support in previous iOS versions.
        guard #available(iOS 13, *) else { return nil }

        guard SSKPreferences.areIntentDonationsEnabled(transaction: transaction) else { return nil }

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing local address")
            return nil
        }

        let senderAddress: SignalServiceAddress
        let message: TSMessage?
        let recipients: [INPerson]?
        switch context {
        case .outgoingMessage(let outgoingMessage):
            senderAddress = localAddress
            message = outgoingMessage

            // For 1:1 outgoing messages, we must populate the recipient of the message,
            // otherwise sharing suggestions won't be populated correctly.
            if !isGroupThread {
                recipients = outgoingMessage.recipientAddresses().map { inPersonForRecipient($0, transaction: transaction) }
            } else {
                recipients = nil
            }
        case .incomingMessage(let incomingMessage):
            senderAddress = incomingMessage.authorAddress
            message = incomingMessage
            recipients = nil
        case .senderAddress(let address):
            senderAddress = address
            message = nil
            recipients = nil
        }

        var conversationIdentifier = uniqueId
        var threadName = contactsManager.displayName(for: self, transaction: transaction)
        if isGroupThread && message?.isGroupStoryReply == true {
            threadName = String(
                format: OWSLocalizedString(
                    "QUOTED_REPLY_STORY_AUTHOR_INDICATOR_FORMAT",
                    comment: "Message header when you are quoting a story. Embeds {{ story author name }}"
                ),
                threadName
            )

            // Uniquely namespace the notifications for group stories.
            conversationIdentifier += "_groupStory"
        }
        let inSender = inPersonForRecipient(senderAddress, transaction: transaction)

        let sendMessageIntent: INSendMessageIntent
        if #available(iOS 14, *) {
            sendMessageIntent = INSendMessageIntent(
                recipients: recipients,
                outgoingMessageType: .outgoingMessageText,
                content: nil,
                speakableGroupName: isGroupThread ? INSpeakableString(spokenPhrase: threadName) : nil,
                conversationIdentifier: conversationIdentifier,
                serviceName: nil,
                sender: inSender
            )
        } else {
            sendMessageIntent = INSendMessageIntent(
                recipients: recipients,
                content: nil,
                speakableGroupName: isGroupThread ? INSpeakableString(spokenPhrase: threadName) : nil,
                conversationIdentifier: conversationIdentifier,
                serviceName: nil,
                sender: inSender
            )
        }

        if isGroupThread {
            if #available(iOS 15, *) {
                let donationMetadata = INSendMessageIntentDonationMetadata()
                donationMetadata.recipientCount = recipientAddresses(with: transaction).count

                if let message = message {
                    let mentionedAddresses = MentionFinder.mentionedAddresses(for: message, transaction: transaction.unwrapGrdbRead)
                    donationMetadata.mentionsCurrentUser = mentionedAddresses.contains(localAddress)
                    donationMetadata.isReplyToCurrentUser = message.quotedMessage?.authorAddress.isEqualToAddress(localAddress) ?? false
                }

                sendMessageIntent.donationMetadata = donationMetadata
            }

            if let image = intentThreadAvatarImage(transaction: transaction) {
                sendMessageIntent.setImage(image, forParameterNamed: \.speakableGroupName)
            }
        }

        return sendMessageIntent
    }

    @available(iOS 13, *)
    public func generateIncomingCallIntent(callerAddress: SignalServiceAddress) -> INIntent? {
        databaseStorage.read { transaction in
            guard !self.isGroupThread else {
                // Fall back to a "send message" intent for group calls,
                // because the "start call" intent makes the notification look too much like a 1:1 call.
                return self.generateSendMessageIntent(context: .senderAddress(callerAddress),
                                                      transaction: transaction)
            }

            guard SSKPreferences.areIntentDonationsEnabled(transaction: transaction) else { return nil }

            let caller = inPersonForRecipient(callerAddress, transaction: transaction)

            let startCallIntent = INStartCallIntent(audioRoute: .unknown,
                                                    destinationType: .normal,
                                                    contacts: [caller],
                                                    recordTypeForRedialing: .unknown,
                                                    callCapability: .unknown)

            return startCallIntent
        }
    }

    private func inPersonForRecipient(_ recipient: SignalServiceAddress,
                                      transaction: SDSAnyReadTransaction) -> INPerson {

        // Generate recipient name
        let contactName = contactsManager.displayName(for: recipient, transaction: transaction)
        let nameComponents = contactsManager.nameComponents(for: recipient, transaction: transaction)

        // Generate contact handle
        let handle: INPersonHandle
        let suggestionType: INPersonSuggestionType
        if let phoneNumber = recipient.phoneNumber {
            handle = INPersonHandle(value: phoneNumber, type: .phoneNumber, label: nil)
            suggestionType = .none
        } else {
            handle = INPersonHandle(value: recipient.uuidString, type: .unknown, label: nil)
            suggestionType = .instantMessageAddress
        }

        // Generate avatar
        let image = intentRecipientAvatarImage(recipient: recipient, transaction: transaction)
        if #available(iOS 15, *) {
            return INPerson(personHandle: handle, nameComponents: nameComponents, displayName: contactName, image: image, contactIdentifier: nil, customIdentifier: nil, isMe: false, suggestionType: suggestionType)
        } else {
            return INPerson(personHandle: handle, nameComponents: nameComponents, displayName: contactName, image: image, contactIdentifier: nil, customIdentifier: nil, isMe: false)
        }
    }

    // Use the same point size as chat list avatars, so it's likely cached and ready for the NSE.
    // The NSE cannot read the device scale, so we rely on a cached scale to correctly calculate
    // the appropriate pixel size for our avatars.
    private static let intentAvatarDiameterPixels: CGFloat = 56 * Environment.preferences.cachedDeviceScale

    private func intentRecipientAvatarImage(recipient: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> INImage? {
        // Generate avatar
        let image: INImage
        if let contactAvatar = avatarBuilder.avatarImage(
            forAddress: recipient,
            diameterPixels: Self.intentAvatarDiameterPixels,
            localUserDisplayMode: .asUser,
            transaction: transaction
        ),
           let contactAvatarPNG = contactAvatar.pngData() {
            image = INImage(imageData: contactAvatarPNG)
        } else {
            image = INImage(named: "profile-placeholder-56")
        }
        return image
    }

    private func intentThreadAvatarImage(transaction: SDSAnyReadTransaction) -> INImage? {
        let image: INImage
        if let threadAvatar = avatarBuilder.avatarImage(
            forThread: self,
            diameterPixels: Self.intentAvatarDiameterPixels,
            localUserDisplayMode: .noteToSelf,
            transaction: transaction
        ),
           let threadAvatarPng = threadAvatar.pngData() {
            image = INImage(imageData: threadAvatarPng)
        } else {
            image = INImage(named: isGroupThread ? "group-placeholder-56" : "profile-placeholder-56")
        }
        return image
    }
}
