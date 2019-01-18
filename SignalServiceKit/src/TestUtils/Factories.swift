//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

/// Factories for creating some default TSYapDatabaseObjects.
///
/// To customize properties applied by the factory (e.g. `someProperty`)
/// the factory needs a `public var somePropertyBuilder: () -> (SomePropertyType)`
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
public protocol Factory {
    associatedtype ObjectType: TSYapDatabaseObject

    var dbConnection: YapDatabaseConnection { get }

    func readWrite(block: @escaping (YapDatabaseReadWriteTransaction) -> Void)

    // MARK: Factory Methods
    func create() -> ObjectType
    func create(transaction: YapDatabaseReadWriteTransaction) -> ObjectType

    func create(count: UInt) -> [ObjectType]
    func create(count: UInt, transaction: YapDatabaseReadWriteTransaction) -> [ObjectType]
}

public extension Factory {

    static public var dbConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadWriteConnection
    }

    public var dbConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadWriteConnection
    }

    static public func readWrite(block: @escaping (YapDatabaseReadWriteTransaction) -> Void) {
        dbConnection.readWrite(block)
    }

    public func readWrite(block: @escaping (YapDatabaseReadWriteTransaction) -> Void) {
        dbConnection.readWrite(block)
    }

    // MARK: Factory Methods

    public func create() -> ObjectType {
        var item: ObjectType!
        self.readWrite { transaction in
            item = self.create(transaction: transaction)
        }
        return item
    }

    public func create(count: UInt) -> [ObjectType] {
        var items: [ObjectType] = []
        self.readWrite { transaction in
            items = self.create(count: count, transaction: transaction)
        }
        return items
    }

    public func create(count: UInt, transaction: YapDatabaseReadWriteTransaction) -> [ObjectType] {
        return (0..<count).map { _ in return create(transaction: transaction) }
    }
}

@objc
public class ContactThreadFactory: NSObject, Factory {

    var messageCount: UInt = 0

    // MARK: Factory

    @objc
    public func create(transaction: YapDatabaseReadWriteTransaction) -> TSContactThread {
        let threadId = generateContactThreadId()
        let thread = TSContactThread.getOrCreateThread(withContactId: threadId, transaction: transaction)

        let incomingMessageFactory = IncomingMessageFactory()
        incomingMessageFactory.threadCreator = { _ in return thread }

        let outgoingMessageFactory = OutgoingMessageFactory()
        outgoingMessageFactory.threadCreator = { _ in return thread }

        (0..<messageCount).forEach { _ in
            if [true, false].ows_randomElement()! {
                _ = incomingMessageFactory.create(transaction: transaction)
            } else {
                _ = outgoingMessageFactory.create(transaction: transaction)
            }
        }

        return thread
    }

    // MARK: Generators

    public func generateContactThreadId() -> String {
        return CommonGenerator.contactId
    }
}

@objc
public class OutgoingMessageFactory: NSObject, Factory {

    // MARK: Factory

    @objc
    public func build(transaction: YapDatabaseReadWriteTransaction) -> TSOutgoingMessage {
        let item = TSOutgoingMessage(outgoingMessageWithTimestamp: timestampBuilder(),
                                     in: threadCreator(transaction),
                                     messageBody: messageBodyBuilder(),
                                     attachmentIds: attachmentIdsBuilder(),
                                     expiresInSeconds: expiresInSecondsBuilder(),
                                     expireStartedAt: expireStartedAtBuilder(),
                                     isVoiceMessage: isVoiceMessageBuilder(),
                                     groupMetaMessage: groupMetaMessageBuilder(),
                                     quotedMessage: quotedMessageBuilder(),
                                     contactShare: contactShareBuilder(),
                                     linkPreview: linkPreviewBuilder())

        return item
    }

    @objc
    public func create(transaction: YapDatabaseReadWriteTransaction) -> TSOutgoingMessage {
        let item = self.build(transaction: transaction)
        item.save(with: transaction)

        return item
    }

    // MARK: Dependent Factories

    @objc
    public var threadCreator: (YapDatabaseReadWriteTransaction) -> TSThread = { transaction in
        ContactThreadFactory().create(transaction: transaction)
    }

    // MARK: Generators

    @objc
    public var timestampBuilder: () -> UInt64 = {
        return NSDate.ows_millisecondTimeStamp()
    }

    @objc
    public var messageBodyBuilder: () -> String = {
        return CommonGenerator.paragraph
    }

    @objc
    var attachmentIdsBuilder: () -> NSMutableArray = {
        return []
    }

    @objc
    public var expiresInSecondsBuilder: () -> UInt32 = {
        return 0
    }

    @objc
    public var expireStartedAtBuilder: () -> UInt64 = {
        return 0
    }

    @objc
    public var isVoiceMessageBuilder: () -> Bool = {
        return false
    }

    @objc
    public var groupMetaMessageBuilder: () -> TSGroupMetaMessage = {
        return .unspecified
    }

    @objc
    public var quotedMessageBuilder: () -> TSQuotedMessage? = {
        return nil
    }

    @objc
    public var contactShareBuilder: () -> OWSContact? = {
        return nil
    }

    @objc
    public var linkPreviewBuilder: () -> OWSLinkPreview? = {
        return nil
    }

    // MARK: Delivery Receipts

    @objc
    public func buildDeliveryReceipt() -> OWSReceiptsForSenderMessage {
        var item: OWSReceiptsForSenderMessage!
        self.readWrite { transaction in
            item = self.buildDeliveryReceipt(transaction: transaction)
        }
        return item
    }

    @objc
    public func buildDeliveryReceipt(transaction: YapDatabaseReadWriteTransaction) -> OWSReceiptsForSenderMessage {
        let item = OWSReceiptsForSenderMessage.deliveryReceiptsForSenderMessage(with: threadCreator(transaction),
                                                                                messageTimestamps: messageTimestampsBuilder())
        return item
    }

    @objc
    public var messageTimestampsBuilder: () -> [NSNumber] = {
        return [1]
    }
}

@objc
public class IncomingMessageFactory: NSObject, Factory {

    // MARK: Factory

    @objc
    public func create(transaction: YapDatabaseReadWriteTransaction) -> TSIncomingMessage {
        let item = TSIncomingMessage(incomingMessageWithTimestamp: timestampBuilder(),
                                     in: threadCreator(transaction),
                                     authorId: authorIdBuilder(),
                                     sourceDeviceId: sourceDeviceIdBuilder(),
                                     messageBody: messageBodyBuilder(),
                                     attachmentIds: attachmentIdsBuilder(),
                                     expiresInSeconds: expiresInSecondsBuilder(),
                                     quotedMessage: quotedMessageBuilder(),
                                     contactShare: contactShareBuilder(),
                                     linkPreview: linkPreviewBuilder(),
                                     serverTimestamp: serverTimestampBuilder(),
                                     wasReceivedByUD: wasReceivedByUDBuilder())

        item.save(with: transaction)

        return item
    }

    // MARK: Dependent Factories

    @objc
    public var threadCreator: (YapDatabaseReadWriteTransaction) -> TSThread = { transaction in
        ContactThreadFactory().create(transaction: transaction)
    }

    // MARK: Generators

    @objc
    public var timestampBuilder: () -> UInt64 = {
        return NSDate.ows_millisecondTimeStamp()
    }

    @objc
    public var messageBodyBuilder: () -> String = {
        return CommonGenerator.paragraph
    }

    @objc
    public var authorIdBuilder: () -> String = {
        return CommonGenerator.contactId
    }

    @objc
    public var sourceDeviceIdBuilder: () -> UInt32 = {
        return 1
    }

    @objc
    public var attachmentIdsBuilder: () -> [String] = {
        return []
    }

    @objc
    public var expiresInSecondsBuilder: () -> UInt32 = {
        return 0
    }

    @objc
    public var quotedMessageBuilder: () -> TSQuotedMessage? = {
        return nil
    }

    @objc
    public var contactShareBuilder: () -> OWSContact? = {
        return nil
    }

    @objc
    public var linkPreviewBuilder: () -> OWSLinkPreview? = {
        return nil
    }

    @objc
    public var serverTimestampBuilder: () -> NSNumber? = {
        return nil
    }

    @objc
    public var wasReceivedByUDBuilder: () -> Bool = {
        return false
    }
}

@objc
class GroupThreadFactory: NSObject, Factory {

    @objc
    public var messageCount: UInt = 0

    @objc
    public func create(transaction: YapDatabaseReadWriteTransaction) -> TSGroupThread {
        let thread = TSGroupThread.getOrCreateThread(with: groupModelBuilder(self),
                                                     transaction: transaction)
        thread.save(with: transaction)

        let incomingMessageFactory = IncomingMessageFactory()
        incomingMessageFactory.threadCreator = { _ in return thread }

        let outgoingMessageFactory = OutgoingMessageFactory()
        outgoingMessageFactory.threadCreator = { _ in return thread }

        (0..<messageCount).forEach { _ in
            if [true, false].ows_randomElement()! {
                incomingMessageFactory.authorIdBuilder = { thread.recipientIdentifiers.ows_randomElement()!  }
                _ = incomingMessageFactory.create(transaction: transaction)
            } else {
                _ = outgoingMessageFactory.create(transaction: transaction)
            }
        }

        return thread
    }

    // MARK: Generators

    @objc
    public var groupModelBuilder: (GroupThreadFactory) -> TSGroupModel = { groupThreadFactory in
        return TSGroupModel(title: groupThreadFactory.titleBuilder(),
                            memberIds: groupThreadFactory.memberIdsBuilder(),
                            image: groupThreadFactory.imageBuilder(),
                            groupId: groupThreadFactory.groupIdBuilder())
    }

    @objc
    public var titleBuilder: () -> String? = {
        return CommonGenerator.words(count: 3)
    }

    @objc
    public var groupIdBuilder: () -> Data = {
        return Randomness.generateRandomBytes(Int32(kGroupIdLength))!
    }

    @objc
    public var imageBuilder: () -> UIImage? = {
        return nil
    }

    @objc
    public var memberIdsBuilder: () -> [RecipientIdentifier] = {
        let groupSize = arc4random_uniform(10)
        return (0..<groupSize).map { _ in CommonGenerator.contactId }
    }
}

@objc
class AttachmentStreamFactory: NSObject, Factory {

    @objc
    class public func create(contentType: String, dataSource: DataSource) -> TSAttachmentStream {
        var item: TSAttachmentStream!
        readWrite { transaction in
            item = create(contentType: contentType, dataSource: dataSource, transaction: transaction)
        }
        return item
    }

    @objc
    class public func create(contentType: String, dataSource: DataSource, transaction: YapDatabaseReadWriteTransaction) -> TSAttachmentStream {
        let factory = AttachmentStreamFactory()
        factory.contentTypeBuilder = { return contentType }
        factory.byteCountBuilder = { return UInt32(dataSource.dataLength()) }
        factory.sourceFilenameBuilder = { return dataSource.sourceFilename ?? "fake-filename.dat" }

        let attachmentStream = factory.build(transaction: transaction)
        dataSource.write(toPath: attachmentStream.originalFilePath!)

        attachmentStream.save(with: transaction)

        return attachmentStream
    }

    // MARK: Factory

    @objc
    public func create(transaction: YapDatabaseReadWriteTransaction) -> TSAttachmentStream {
        let attachmentStream = build(transaction: transaction)
        attachmentStream.save(with: transaction)

        return attachmentStream
    }

    @objc
    public func build(transaction: YapDatabaseReadTransaction) -> TSAttachmentStream {
        return build()
    }

    @objc
    public func build() -> TSAttachmentStream {
        let attachmentStream = TSAttachmentStream(contentType: contentTypeBuilder(),
                                                  byteCount: byteCountBuilder(),
                                                  sourceFilename: sourceFilenameBuilder(),
                                                  caption: captionBuilder(),
                                                  albumMessageId: albumMessageIdBuilder())

        return attachmentStream
    }

    // MARK: Properties

    @objc
    public var contentTypeBuilder: () -> String = {
        return OWSMimeTypeApplicationOctetStream
    }

    @objc
    public var byteCountBuilder: () -> UInt32 = {
        return 0
    }

    @objc
    public var sourceFilenameBuilder: () -> String? = {
        return "fake_file.dat"
    }

    @objc
    public var captionBuilder: () -> String? = {
        return nil
    }

    @objc
    public var albumMessageIdBuilder: () -> String? = {
        return nil
    }
}

extension Array {
    public func ows_randomElement() -> Element? {
        guard self.count > 0 else {
            return nil
        }
        let index = arc4random_uniform(UInt32(self.count))
        return self[Int(index)]
    }
}

struct CommonGenerator {

    static public var contactId: String {
        let digits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]

        let randomDigits = (0..<10).map { _ in return digits.ows_randomElement()! }

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

    static public var word: String {
        return String(sentence.split(separator: " ").first!)
    }

    static public func words(count: Int) -> String {
        var result: [String] = []

        while result.count < count {
            let remaining = count - result.count
            result += sentence.split(separator: " ").prefix(remaining).map { String($0) }
        }

        return result.joined(separator: " ")
    }

    static public var sentence: String {
        return sentences.ows_randomElement()!
    }

    static public func sentences(count: UInt) -> [String] {
        return (0..<count).map { _ in sentence }
    }

    static public var paragraph: String {
        let sentenceCount = UInt(arc4random_uniform(7) + 2)
        return paragraph(sentenceCount: sentenceCount)
    }

    static public func paragraph(sentenceCount: UInt) -> String {
        return sentences(count: sentenceCount).joined(separator: " ")
    }
}
