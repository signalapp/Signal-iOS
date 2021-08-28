//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

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
    class func enqueueMessage(body messageBody: MessageBody?,
                              mediaAttachments: [SignalAttachment],
                              thread: TSThread,
                              quotedReplyModel: OWSQuotedReplyModel?,
                              linkPreviewDraft: OWSLinkPreviewDraft?,
                              persistenceCompletionHandler persistenceCompletion: PersistenceCompletion?,
                              transaction readTransaction: SDSAnyReadTransaction) -> TSOutgoingMessage {
        AssertIsOnMainThread()

        let outgoingMessagePreparer = OutgoingMessagePreparer(messageBody: messageBody,
                                                              mediaAttachments: mediaAttachments,
                                                              thread: thread,
                                                              quotedReplyModel: quotedReplyModel,
                                                              transaction: readTransaction)
        let message: TSOutgoingMessage = outgoingMessagePreparer.unpreparedMessage

        BenchManager.startEvent(
            title: "Send Message Milestone: Sending (\(message.timestamp))",
            eventId: "sendMessageSending-\(message.timestamp)"
        )
        BenchManager.startEvent(
            title: "Send Message Milestone: Sent (\(message.timestamp))",
            eventId: "sendMessageSent-\(message.timestamp)"
        )
        BenchManager.benchAsync(title: "Send Message Milestone: Enqueue \(message.timestamp)") { benchmarkCompletion in
            Self.enqueueSendAsyncWrite { writeTransaction in
                outgoingMessagePreparer.insertMessage(linkPreviewDraft: linkPreviewDraft,
                                                      transaction: writeTransaction)
                Self.messageSenderJobQueue.add(message: outgoingMessagePreparer,
                                               transaction: writeTransaction)
                writeTransaction.addSyncCompletion {
                    benchmarkCompletion()
                }
                writeTransaction.addAsyncCompletionOnMain {
                    persistenceCompletion?()
                }
            }
        }

        if message.hasRenderableContent() {
            thread.donateSendMessageIntent(transaction: readTransaction)
        }
        return message
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
            if message.hasRenderableContent() { thread.donateSendMessageIntent(transaction: transaction) }
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

        if message.hasRenderableContent() { thread.donateSendMessageIntent(transaction: transaction) }

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
                .donateSendMessageIntent(transaction: transaction)
        }
        return promise
    }
}

// MARK: - Sharing Suggestions

import Intents
import SignalServiceKit

extension TSThread {

    @objc
    public func donateSendMessageIntentWithSneakyTransaction() {
        databaseStorage.read { self.donateSendMessageIntent(transaction: $0) }
    }

    /// This function should be called every time the user
    /// initiates message sending via the UI. It should *not*
    /// be called for messages we send automatically, like
    /// receipts.
    @objc
    public func donateSendMessageIntent(transaction: SDSAnyReadTransaction) {
        // We never need to do this pre-iOS 13, because sharing
        // suggestions aren't support in previous iOS versions.
        guard #available(iOS 13, *) else { return }

        guard SSKPreferences.areIntentDonationsEnabled(transaction: transaction) else { return }

        guard let sendMessageIntent = generateSendMessageIntent(transaction: transaction, sender: nil) else { return }

        let interaction = INInteraction(intent: sendMessageIntent, response: nil)
        interaction.groupIdentifier = uniqueId
        interaction.direction = .outgoing
        interaction.donate(completion: { error in
            guard let error = error else { return }
            owsFailDebug("Failed to donate message intent for \(self.uniqueId) \(error)")
        })
    }

    public func generateSendMessageIntent(transaction: SDSAnyReadTransaction, sender: SignalServiceAddress?) -> INSendMessageIntent? {
        // We never need to do this pre-iOS 13, because sharing
        // suggestions aren't support in previous iOS versions.
        guard #available(iOS 13, *) else { return nil }

        guard SSKPreferences.areIntentDonationsEnabled(transaction: transaction) else { return nil }

        let sendMessageIntent: INSendMessageIntent

        #if swift(>=5.5) // TODO Temporary for Xcode 12 support.
        if #available(iOS 15, *), FeatureFlags.communicationStyleNotifications {
            sendMessageIntent = generateRichCommunicationNotificationSendMessageIntent(transaction: transaction, sender: sender)
        } else {
            sendMessageIntent = generateChatSuggestionSendMessageIntent(transaction: transaction)
        }
        #else
            sendMessageIntent = generateChatSuggestionSendMessageIntent(transaction: transaction)
        #endif

        return sendMessageIntent
    }

#if swift(>=5.5) // TODO Temporary for Xcode 12 support.
    @available(iOS 15, *)
    private func generateRichCommunicationNotificationSendMessageIntent(transaction: SDSAnyReadTransaction, sender: SignalServiceAddress?) -> INSendMessageIntent {
        let threadName = contactsManager.displayName(for: self, transaction: transaction)
        let isGroupThread = self.isGroupThread

        var recipients: [INPerson] = []
        var inSender: INPerson?
        // Recipients are required for iOS 15 Communication style notifications
        for recipient in self.recipientAddresses {
            let generateAvatar = !isGroupThread || (isGroupThread && !CurrentAppContext().isNSE)
            let person = inPersonForRecipient(recipient, generateAvatar: generateAvatar, transaction: transaction)

            if recipient == sender {
                inSender = person
            } else {
                recipients.append(person)
            }
        }

        // NOTE A known issue in iOS 15 beta 5 currently prevents the sender’s image from displaying on a communication notification. This known issue is resolved in future software updates.
        let sendMessageIntent = INSendMessageIntent(recipients: recipients,
                                                    outgoingMessageType: .outgoingMessageText,
                                                    content: nil,
                                                    speakableGroupName: isGroupThread ? INSpeakableString(spokenPhrase: threadName) : nil,
                                                    conversationIdentifier: uniqueId,
                                                    serviceName: nil,
                                                    sender: inSender,
                                                    attachments: nil)

        if isGroupThread {
            if let image = intentThreadAvatarImage(transaction: transaction) {
                sendMessageIntent.setImage(image, forParameterNamed: \.speakableGroupName)
            }
        }

        return sendMessageIntent
    }
    #endif

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
    public func generateStartCallIntent() -> INStartCallIntent? {
        #if swift(>=5.5) // TODO Temporary for Xcode 12 support.
        databaseStorage.read { transaction in
            guard FeatureFlags.communicationStyleNotifications, SSKPreferences.areIntentDonationsEnabled(transaction: transaction) else { return nil }

            var recipients: [INPerson] = []
            for recipient in self.recipientAddresses {
                let generateAvatar = !isGroupThread || (isGroupThread && !CurrentAppContext().isNSE)
                let person = inPersonForRecipient(recipient, generateAvatar: generateAvatar, transaction: transaction)
                recipients.append(person)
            }

            let startCallIntent = INStartCallIntent(callRecordFilter: nil,
                                                    callRecordToCallBack: nil,
                                                    audioRoute: .unknown,
                                                    destinationType: .normal,
                                                    contacts: recipients,
                                                    callCapability: .unknown)

            if self.isGroupThread {
                if let image = intentThreadAvatarImage(transaction: transaction) {
                    startCallIntent.setImage(image, forParameterNamed: \.callRecordToCallBack)
                }
            }

            return startCallIntent
        }
        #else
            return nil
        #endif
    }

#if swift(>=5.5) // TODO Temporary for Xcode 12 support.
    @available(iOS 15, *)
    private func inPersonForRecipient(_ recipient: SignalServiceAddress, generateAvatar: Bool, transaction: SDSAnyReadTransaction) -> INPerson {

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
        var image: INImage?
        if generateAvatar {
            image = intentRecipientAvatarImage(recipient: recipient, transaction: transaction)
        }

        return INPerson(personHandle: handle, nameComponents: nameComponents, displayName: contactName, image: image, contactIdentifier: nil, customIdentifier: nil, isMe: false, suggestionType: suggestionType)
    }

    private func intentRecipientAvatarImage(recipient: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> INImage? {
        // Generate avatar
        var image: INImage?
        if let contactAvatar = avatarBuilder.avatarImage(forAddress: recipient,
                                                         diameterPoints: 40,
                                                         localUserDisplayMode: .asUser,
                                                         transaction: transaction), let contactAvatarPNG = contactAvatar.pngData() {
            image = INImage(imageData: contactAvatarPNG)
        }
        return image
    }
#endif

    private func intentThreadAvatarImage(transaction: SDSAnyReadTransaction) -> INImage? {
        var image: INImage?
        if let threadAvatar = avatarBuilder.avatarImage(forThread: self,
                                                        diameterPoints: 40,
                                                        localUserDisplayMode: .noteToSelf,
                                                        transaction: transaction),
        let threadAvatarPng = threadAvatar.pngData() {
            image = INImage(imageData: threadAvatarPng)
        }

        return image
    }
}
