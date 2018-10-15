//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

/// Factories for creating some default TSYapDatabaseObjects.
///
/// To customize properties applied by the factory (e.g. `someProperty`)
/// the factory needs a `var somePropertyBuilder: () -> (SomePropertyType)`
/// which is then used in the `create` method.
///
/// Examples:
///
/// Create one empty thread:
///
///     let oneThread = ContactThreadFactory().create()
///
/// Create 12 thread's with 100 messages each
///
///     let factory = ContractThreadFactory()
///     factory.messageCount = 100
///     factory.create(count: 12)
///
/// Create 100 messages in an existing thread
///
///     let existingThread: TSThread = getSomeExistingThread()
///     let messageFactory = TSIncomingMessageFactory()
///     messageFactory.threadCreator = { _ in return existingThread }
///     messageFactory.create(count: 100)
///
protocol Factory {
    associatedtype ObjectType: TSYapDatabaseObject

    var dbConnection: YapDatabaseConnection { get }

    func readWrite(block: @escaping (YapDatabaseReadWriteTransaction) -> Void)

    // MARK: Factory Methods
    func create() -> ObjectType
    func create(transaction: YapDatabaseReadWriteTransaction) -> ObjectType

    func create(count: UInt) -> [ObjectType]
    func create(count: UInt, transaction: YapDatabaseReadWriteTransaction) -> [ObjectType]
}

extension Factory {
    var dbConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadWriteConnection
    }

    func readWrite(block: @escaping (YapDatabaseReadWriteTransaction) -> Void) {
        dbConnection.readWrite(block)
    }

    // MARK: Factory Methods

    func create() -> ObjectType {
        var item: ObjectType!
        self.readWrite { transaction in
            item = self.create(transaction: transaction)
        }
        return item
    }

    func create(count: UInt) -> [ObjectType] {
        var items: [ObjectType] = []
        self.readWrite { transaction in
            items = self.create(count: count, transaction: transaction)
        }
        return items
    }

    func create(count: UInt, transaction: YapDatabaseReadWriteTransaction) -> [ObjectType] {
        return (0..<count).map { _ in return create(transaction: transaction) }
    }
}

class ContactThreadFactory: Factory {

    var messageCount: UInt = 0

    // MARK: Factory

    func create(transaction: YapDatabaseReadWriteTransaction) -> TSContactThread {
        let threadId = generateContactThreadId()
        let thread = TSContactThread.getOrCreateThread(withContactId: threadId, transaction: transaction)

        let incomingMessageFactory = IncomingMessageFactory()
        incomingMessageFactory.threadCreator = { _ in return thread }

        let outgoingMessageFactory = OutgoingMessageFactory()
        outgoingMessageFactory.threadCreator = { _ in return thread }

        (0..<messageCount).forEach { _ in
            if Bool.random() {
                _ = incomingMessageFactory.create(transaction: transaction)
            } else {
                _ = outgoingMessageFactory.create(transaction: transaction)
            }
        }

        return thread
    }

    // MARK: Generators

    func generateContactThreadId() -> String {
        return CommonGenerator.contactId
    }
}

class OutgoingMessageFactory: Factory {

    // MARK: Factory

    func create(transaction: YapDatabaseReadWriteTransaction) -> TSOutgoingMessage {
        let item = TSOutgoingMessage(outgoingMessageWithTimestamp: timestampBuilder(),
                                     in: threadCreator(transaction),
                                     messageBody: messageBodyBuilder(),
                                     attachmentIds: [],
                                     expiresInSeconds: 0,
                                     expireStartedAt: 0,
                                     isVoiceMessage: false,
                                     groupMetaMessage: .unspecified,
                                     quotedMessage: nil,
                                     contactShare: nil)
        item.save(with: transaction)

        return item
    }

    // MARK: Dependent Factories

    var threadCreator: (YapDatabaseReadWriteTransaction) -> TSThread = { transaction in
        ContactThreadFactory().create(transaction: transaction)
    }

    // MARK: Generators

    var timestampBuilder: () -> UInt64 = {
        return NSDate.ows_millisecondTimeStamp()
    }

    var messageBodyBuilder: () -> String = {
        return CommonGenerator.paragraph
    }
}

class IncomingMessageFactory: Factory {

    // MARK: Factory

    func create(transaction: YapDatabaseReadWriteTransaction) -> TSIncomingMessage {
        let item = TSIncomingMessage(incomingMessageWithTimestamp: timestampBuilder(),
                                     in: threadCreator(transaction),
                                     authorId: authorIdBuilder(),
                                     sourceDeviceId: 1,
                                     messageBody: messageBodyBuilder(),
                                     attachmentIds: [],
                                     expiresInSeconds: 0,
                                     quotedMessage: nil,
                                     contactShare: nil,
                                     serverTimestamp: nil,
                                     wasReceivedByUD: false)

        item.save(with: transaction)

        return item
    }

    // MARK: Dependent Factories

    var threadCreator: (YapDatabaseReadWriteTransaction) -> TSThread = { transaction in
        ContactThreadFactory().create(transaction: transaction)
    }

    // MARK: Generators

    var timestampBuilder: () -> UInt64 = {
        return NSDate.ows_millisecondTimeStamp()
    }

    var messageBodyBuilder: () -> String = {
        return CommonGenerator.paragraph
    }

    var authorIdBuilder: () -> String = {
        return CommonGenerator.contactId
    }
}

class GroupThreadFactory: Factory {

    var messageCount: UInt = 0

    func create(transaction: YapDatabaseReadWriteTransaction) -> TSGroupThread {
        let thread = TSGroupThread.getOrCreateThread(with: groupModelBuilder(self),
                                                     transaction: transaction)
        thread.save(with: transaction)

        let incomingMessageFactory = IncomingMessageFactory()
        incomingMessageFactory.threadCreator = { _ in return thread }

        let outgoingMessageFactory = OutgoingMessageFactory()
        outgoingMessageFactory.threadCreator = { _ in return thread }

        (0..<messageCount).forEach { _ in
            if Bool.random() {
                incomingMessageFactory.authorIdBuilder = { thread.recipientIdentifiers.randomElement()!  }
                _ = incomingMessageFactory.create(transaction: transaction)
            } else {
                _ = outgoingMessageFactory.create(transaction: transaction)
            }
        }

        return thread
    }

    // MARK: Generators

    var groupModelBuilder: (GroupThreadFactory) -> TSGroupModel = { groupThreadFactory in
        return TSGroupModel(title: groupThreadFactory.titleBuilder(),
                            memberIds: groupThreadFactory.memberIdsBuilder(),
                            image: groupThreadFactory.imageBuilder(),
                            groupId: groupThreadFactory.groupIdBuilder())
    }

    var titleBuilder: () -> String? = {
        return CommonGenerator.words(count: 3)
    }

    var groupIdBuilder: () -> Data = {
        return Randomness.generateRandomBytes(Int32(kGroupIdLength))!
    }

    var imageBuilder: () -> UIImage? = {
        return nil
    }

    var memberIdsBuilder: () -> [RecipientIdentifier] = {
        let groupSize = (1..<10).randomElement()!
        return (0..<groupSize).map { _ in CommonGenerator.contactId }
    }
}

struct CommonGenerator {

    static var contactId: String {
        let digits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]

        let randomDigits = (0..<10).map { _ in return digits.randomElement()! }

        return "+1".appending(randomDigits.joined())
    }

    // Body Content

    static let sentences = [
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ",
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse rutrum, nulla vitae pretium hendrerit, tellus turpis pharetra libero, vitae sodales tortor ante vel sem.",
        "In a time of universal deceit - telling the truth is a revolutionary act.",
        "If you want a vision of the future, imagine a boot stamping on a human face - forever.",
        "Who controls the past controls the future. Who controls the present controls the past.",
        "All animals are equal, but some animals are more equal than others.",
        "War is peace. Freedom is slavery. Ignorance is strength.",
        "All the war-propaganda, all the screaming and lies and hatred, comes invariably from people who are not fighting.",
        "Political language. . . is designed to make lies sound truthful and murder respectable, and to give an appearance of solidity to pure wind.",
        "The nationalist not only does not disapprove of atrocities committed by his own side, but he has a remarkable capacity for not even hearing about them.",
        "Every generation imagines itself to be more intelligent than the one that went before it, and wiser than the one that comes after it.",
        "War against a foreign country only happens when the moneyed classes think they are going to profit from it.",
        "People have only as much liberty as they have the intelligence to want and the courage to take.",
        "You cannot buy the revolution. You cannot make the revolution. You can only be the revolution. It is in your spirit, or it is nowhere.",
        "That is what I have always understood to be the essence of anarchism: the conviction that the burden of proof has to be placed on authority, and that it should be dismantled if that burden cannot be met.",
        "Ask for work. If they don't give you work, ask for bread. If they do not give you work or bread, then take bread.",
        "Every society has the criminals it deserves.",
        "Anarchism is founded on the observation that since few men are wise enough to rule themselves, even fewer are wise enough to rule others.",
        "If you would know who controls you see who you may not criticise.",
        "At one time in the world there were woods that no one owned."
    ]

    static var word: String {
        return String(sentence.split(separator: " ").first!)
    }

    static func words(count: Int) -> String {
        var result: [String] = []

        while result.count < count {
            let remaining = count - result.count
            result += sentence.split(separator: " ").prefix(remaining).map { String($0) }
        }

        return result.joined(separator: " ")
    }

    static var sentence: String {
        return sentences.randomElement()!
    }

    static func sentences(count: UInt) -> [String] {
        return (0..<count).map { _ in sentence }
    }

    static let sentenceCountInParagraph: Range<UInt> = (2..<9)
    static var paragraph: String {
        let sentenceCount = sentenceCountInParagraph.randomElement()!
        return paragraph(sentenceCount: sentenceCount)
    }

    static func paragraph(sentenceCount: UInt) -> String {
        return sentences(count: sentenceCount).joined(separator: " ")
    }
}
