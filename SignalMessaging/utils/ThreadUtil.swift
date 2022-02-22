//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension ThreadUtil {

    typealias PersistenceCompletion = () -> Void

    // A serial queue that ensures that messages are sent in the
    // same order in which they are enqueued.
    static var enqueueSendQueue: DispatchQueue { .sharedUserInitiated }

    static func enqueueSendAsyncWrite(_ block: @escaping (SDSAnyWriteTransaction) -> Void) {
        enqueueSendQueue.async {
            Self.databaseStorage.write { transaction in
                block(transaction)
            }
        }
    }

    @discardableResult
    class func enqueueMessage(withContactShare contactShare: OWSContact,
                              thread: TSThread) -> TSOutgoingMessage {
        AssertIsOnMainThread()
        assert(contactShare.ows_isValid())

        let builder = TSOutgoingMessageBuilder(thread: thread)
        builder.contactShare = contactShare

        return enqueueMessage(outgoingMessageBuilder: builder, thread: thread)
    }

    @discardableResult
    class func enqueueMessage(outgoingMessageBuilder builder: TSOutgoingMessageBuilder,
                              thread: TSThread) -> TSOutgoingMessage {

        let dmConfiguration = databaseStorage.read { transaction in
            return thread.disappearingMessagesConfiguration(with: transaction)
        }
        builder.expiresInSeconds = dmConfiguration.isEnabled ? dmConfiguration.durationSeconds : 0

        let message = builder.build()

        Self.enqueueSendAsyncWrite { transaction in
            message.anyInsert(transaction: transaction)
            self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
            if message.hasRenderableContent() { thread.donateSendMessageIntent(for: message, transaction: transaction) }
        }

        return message
    }

    @discardableResult
    class func enqueueMessage(outgoingMessageBuilder builder: TSOutgoingMessageBuilder,
                              thread: TSThread,
                              transaction: SDSAnyWriteTransaction) -> TSOutgoingMessage {

        let dmConfiguration = thread.disappearingMessagesConfiguration(with: transaction)
        builder.expiresInSeconds = dmConfiguration.isEnabled ? dmConfiguration.durationSeconds : 0

        let message = builder.build()
        message.anyInsert(transaction: transaction)
        self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)

        if message.hasRenderableContent() { thread.donateSendMessageIntent(for: message, transaction: transaction) }

        return message
    }

    @nonobjc
    class func enqueueMessagePromise(
        message: TSOutgoingMessage,
        limitToCurrentProcessLifetime: Bool = false,
        isHighPriority: Bool = false,
        transaction: SDSAnyWriteTransaction
    ) -> Promise<Void> {
        let promise = messageSenderJobQueue.add(
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

// MARK: - Sharing Suggestions

import Intents
import SignalServiceKit

extension TSThread {

    /// This function should be called every time the user
    /// initiates message sending via the UI. It should *not*
    /// be called for messages we send automatically, like
    /// receipts.
    @objc(donateSendMessageIntentForOutgoingMessage:transaction:)
    public func donateSendMessageIntent(for outgoingMessage: TSOutgoingMessage, transaction: SDSAnyReadTransaction) {
        // We never need to do this pre-iOS 13, because sharing
        // suggestions aren't support in previous iOS versions.
        guard #available(iOS 13, *) else { return }

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

        let sendMessageIntent: INSendMessageIntent?

        if #available(iOS 15, *) {
            sendMessageIntent = generateRichCommunicationNotificationSendMessageIntent(context: context, transaction: transaction)
        } else {
            sendMessageIntent = generateChatSuggestionSendMessageIntent(transaction: transaction)
        }

        return sendMessageIntent
    }

    @available(iOS 15, *)
    private func generateRichCommunicationNotificationSendMessageIntent(
        context: IntentContext,
        transaction: SDSAnyReadTransaction
    ) -> INSendMessageIntent? {
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing local address")
            return nil
        }

        let senderAddress: SignalServiceAddress
        let message: TSMessage?
        switch context {
        case .outgoingMessage(let outgoingMessage):
            senderAddress = localAddress
            message = outgoingMessage
        case .incomingMessage(let incomingMessage):
            senderAddress = incomingMessage.authorAddress
            message = incomingMessage
        case .senderAddress(let address):
            senderAddress = address
            message = nil
        }

        let threadName = contactsManager.displayName(for: self, transaction: transaction)
        let inSender = inPersonForRecipient(senderAddress, transaction: transaction)

        let sendMessageIntent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: nil,
            speakableGroupName: isGroupThread ? INSpeakableString(spokenPhrase: threadName) : nil,
            conversationIdentifier: uniqueId,
            serviceName: nil,
            sender: inSender,
            attachments: nil
        )

        if isGroupThread {

            let donationMetadata = INSendMessageIntentDonationMetadata()
            donationMetadata.recipientCount = recipientAddresses.count

            if let message = message {
                let mentionedAddresses = MentionFinder.mentionedAddresses(for: message, transaction: transaction.unwrapGrdbRead)
                donationMetadata.mentionsCurrentUser = mentionedAddresses.contains(localAddress)
                donationMetadata.isReplyToCurrentUser = message.quotedMessage?.authorAddress.isEqualToAddress(localAddress) ?? false
            }

            sendMessageIntent.donationMetadata = donationMetadata

            if let image = intentThreadAvatarImage(transaction: transaction) {
                sendMessageIntent.setImage(image, forParameterNamed: \.speakableGroupName)
            }
        }

        return sendMessageIntent
    }

    @available(iOS 13, *)
    private func generateChatSuggestionSendMessageIntent(transaction: SDSAnyReadTransaction) -> INSendMessageIntent {
        let threadName = contactsManager.displayName(for: self, transaction: transaction)

        let sendMessageIntent = INSendMessageIntent(
            recipients: nil,
            content: nil,
            speakableGroupName: INSpeakableString(spokenPhrase: threadName),
            conversationIdentifier: uniqueId,
            serviceName: nil,
            sender: nil
        )

        if let image = intentThreadAvatarImage(transaction: transaction) {
            sendMessageIntent.setImage(image, forParameterNamed: \.speakableGroupName)
        }

        return sendMessageIntent
    }

    @available(iOS 15, *)
    public func generateStartCallIntent(callerAddress: SignalServiceAddress) -> INStartCallIntent? {
        databaseStorage.read { transaction in
            guard SSKPreferences.areIntentDonationsEnabled(transaction: transaction) else { return nil }

            let caller = inPersonForRecipient(callerAddress, transaction: transaction)

            let startCallIntent = INStartCallIntent(callRecordFilter: nil,
                                                    callRecordToCallBack: nil,
                                                    audioRoute: .unknown,
                                                    destinationType: .normal,
                                                    contacts: [caller],
                                                    callCapability: .unknown)

            if self.isGroupThread {
                if let image = intentThreadAvatarImage(transaction: transaction) {
                    startCallIntent.setImage(image, forParameterNamed: \.callRecordToCallBack)
                }
            }

            return startCallIntent
        }
    }

    @available(iOS 15, *)
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
        return INPerson(personHandle: handle, nameComponents: nameComponents, displayName: contactName, image: image, contactIdentifier: nil, customIdentifier: nil, isMe: false, suggestionType: suggestionType)
    }

    // Use the same point size as home view avatars, so it's likely cached and ready for the NSE.
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
