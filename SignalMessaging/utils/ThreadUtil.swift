//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public extension ThreadUtil {

    typealias PersistenceCompletion = () -> Void

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

        BenchManager.benchAsync(title: "Saving outgoing message") { benchmarkCompletion in
            Self.databaseStorage.asyncWrite { writeTransaction in
                outgoingMessagePreparer.insertMessage(linkPreviewDraft: linkPreviewDraft,
                                                      transaction: writeTransaction)
                Self.messageSenderJobQueue.add(message: outgoingMessagePreparer,
                                               transaction: writeTransaction)
                writeTransaction.addAsyncCompletionOnMain {
                    benchmarkCompletion()
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

        databaseStorage.asyncWrite { transaction in
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

        guard SSKPreferences.areSharingSuggestionsEnabled(transaction: transaction) else { return }

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

        guard SSKPreferences.areSharingSuggestionsEnabled(transaction: transaction) else { return nil }

        let threadName = contactsManager.displayName(for: self, transaction: transaction)

        var image: INImage?
        if let threadAvatar = Self.avatarBuilder.avatarImage(forThread: self,
                                                             diameterPoints: 400,
                                                             localUserDisplayMode: .noteToSelf,
                                                             transaction: transaction),
        let threadAvatarPng = threadAvatar.pngData() {
            image = INImage(imageData: threadAvatarPng)
        }

        var recipients: [INPerson] = []
        var inSender: INPerson?
        // Recipients are required for iOS 15 Communication style notifications
        if #available(iOS 15, *), FeatureFlags.communicationStyleNotifications {
            for recipient in self.recipientAddresses {
                let contactName = contactsManager.displayName(for: recipient, transaction: transaction)
                let nameComponents = contactsManager.nameComponents(for: recipient, transaction: transaction)
                let handle = INPersonHandle(value: recipient.phoneNumber, type: .phoneNumber, label: nil)
                let person = INPerson(personHandle: handle, nameComponents: nameComponents, displayName: contactName, image: image, contactIdentifier: nil, customIdentifier: nil, isMe: false)

                if recipient == sender {
                    inSender = person
                } else {
                    recipients.append(person)
                }
            }
        }

        let sendMessageIntent = INSendMessageIntent(
            recipients: recipients,
            content: nil,
            speakableGroupName: INSpeakableString(spokenPhrase: threadName),
            conversationIdentifier: uniqueId,
            serviceName: nil,
            sender: inSender
        )

        if let image = image {
            sendMessageIntent.setImage(image, forParameterNamed: \.speakableGroupName)
        }

        return sendMessageIntent
    }
}
