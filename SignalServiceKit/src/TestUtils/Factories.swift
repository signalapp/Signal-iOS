//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

#if TESTABLE_BUILD

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
public protocol Factory: Dependencies {
    associatedtype ObjectType: TSYapDatabaseObject

    static func write(block: @escaping (SDSAnyWriteTransaction) -> Void)
    func write(block: @escaping (SDSAnyWriteTransaction) -> Void)

    // MARK: Factory Methods
    func create() -> ObjectType
    func create(transaction: SDSAnyWriteTransaction) -> ObjectType

    func create(count: UInt) -> [ObjectType]
    func create(count: UInt, transaction: SDSAnyWriteTransaction) -> [ObjectType]
}

public extension Factory {

    static func write(block: @escaping (SDSAnyWriteTransaction) -> Void) {
        databaseStorage.write(block: block)
    }

    func write(block: @escaping (SDSAnyWriteTransaction) -> Void) {
        databaseStorage.write(block: block)
    }

    // MARK: Factory Methods

    func create() -> ObjectType {
        var item: ObjectType!
        write { transaction in
            item = self.create(transaction: transaction)
        }
        return item
    }

    func create(count: UInt) -> [ObjectType] {
        var items: [ObjectType] = []
        write { transaction in
            items = self.create(count: count, transaction: transaction)
        }
        return items
    }

    func create(count: UInt, transaction: SDSAnyWriteTransaction) -> [ObjectType] {
        return (0..<count).map { _ in return create(transaction: transaction) }
    }
}

@objc
public class ContactThreadFactory: NSObject, Factory {

    public var messageCount: UInt = 0

    // MARK: Factory

    @objc
    public func create(transaction: SDSAnyWriteTransaction) -> TSContactThread {
        let thread = TSContactThread.getOrCreateThread(withContactAddress: contactAddressBuilder(),
                                                       transaction: transaction)

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

    // MARK: Dependent Factories

    @objc
    public var contactAddressBuilder: () -> SignalServiceAddress = {
        return CommonGenerator.address()
    }
}

@objc
public class OutgoingMessageFactory: NSObject, Factory {

    // MARK: Factory

    @objc
    public func build(transaction: SDSAnyWriteTransaction) -> TSOutgoingMessage {
        // The builder() factory method requires us to specify every
        // property so that this will break if we add any new properties.
        return TSOutgoingMessageBuilder.builder(thread: threadCreator(transaction),
                                                timestamp: timestampBuilder(),
                                                messageBody: messageBodyBuilder(),
                                                bodyRanges: bodyRangesBuilder(),
                                                attachmentIds: attachmentIdsBuilder(),
                                                expiresInSeconds: expiresInSecondsBuilder(),
                                                expireStartedAt: expireStartedAtBuilder(),
                                                isVoiceMessage: isVoiceMessageBuilder(),
                                                groupMetaMessage: groupMetaMessageBuilder(),
                                                quotedMessage: quotedMessageBuilder(),
                                                contactShare: contactShareBuilder(),
                                                linkPreview: linkPreviewBuilder(),
                                                messageSticker: messageStickerBuilder(),
                                                isViewOnceMessage: isViewOnceMessageBuilder(),
                                                changeActionsProtoData: changeActionsProtoDataBuilder(),
                                                additionalRecipients: additionalRecipientsBuilder(),
                                                skippedRecipients: skippedRecipientsBuilder(),
                                                storyAuthorAddress: storyAuthorAddressBuilder(),
                                                storyTimestamp: storyTimestampBuilder(),
                                                storyReactionEmoji: storyReactionEmojiBuilder(),
                                                giftBadge: giftBadgeBuilder()).build(transaction: transaction)
    }

    @objc
    public func create(transaction: SDSAnyWriteTransaction) -> TSOutgoingMessage {
        let item = self.build(transaction: transaction)
        item.anyInsert(transaction: transaction)

        return item
    }

    // MARK: Dependent Factories

    @objc
    public var threadCreator: (SDSAnyWriteTransaction) -> TSThread = { transaction in
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
    public var bodyRangesBuilder: () -> MessageBodyRanges = {
        return MessageBodyRanges.empty
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

    @objc
    public var messageStickerBuilder: () -> MessageSticker? = {
        return nil
    }

    @objc
    public var isViewOnceMessageBuilder: () -> Bool = {
        return false
    }

    @objc
    public var changeActionsProtoDataBuilder: () -> Data? = {
        return nil
    }

    @objc
    public var additionalRecipientsBuilder: () -> [SignalServiceAddress]? = {
        return nil
    }

    @objc
    public var skippedRecipientsBuilder: () -> Set<SignalServiceAddress>? = {
        return nil
    }

    @objc
    public var storyAuthorAddressBuilder: () -> SignalServiceAddress? = {
        return nil
    }

    @objc
    public var storyTimestampBuilder: () -> NSNumber? = {
        return nil
    }

    @objc
    public var storyReactionEmojiBuilder: () -> String? = {
        return nil
    }

    @objc
    public var giftBadgeBuilder: () -> OWSGiftBadge? = {
        return nil
    }

    // MARK: Delivery Receipts

    @objc
    public func buildDeliveryReceipt() -> OWSReceiptsForSenderMessage {
        var item: OWSReceiptsForSenderMessage!
        write { transaction in
            item = self.buildDeliveryReceipt(transaction: transaction)
        }
        return item
    }

    @objc
    public func buildDeliveryReceipt(transaction: SDSAnyWriteTransaction) -> OWSReceiptsForSenderMessage {
        let item = OWSReceiptsForSenderMessage.deliveryReceiptsForSenderMessage(with: threadCreator(transaction),
                                                                                receiptSet: receiptSetBuilder(), transaction: transaction)
        return item
    }

    @objc
    var receiptSetBuilder: () -> MessageReceiptSet = {
        let set = MessageReceiptSet()
        set.insert(timestamp: 1, messageUniqueId: "hello")
        return set
    }
}

@objc
public class IncomingMessageFactory: NSObject, Factory {

    // MARK: Factory

    @objc
    public func create(transaction: SDSAnyWriteTransaction) -> TSIncomingMessage {

        let thread = threadCreator(transaction)

        // The builder() factory method requires us to specify every
        // property so that this will break if we add any new properties.
        let builder = TSIncomingMessageBuilder.builder(thread: thread,
                                                       timestamp: timestampBuilder(),
                                                       authorAddress: authorAddressBuilder(thread),
                                                       sourceDeviceId: sourceDeviceIdBuilder(),
                                                       messageBody: messageBodyBuilder(),
                                                       bodyRanges: bodyRangesBuilder(),
                                                       attachmentIds: attachmentIdsBuilder(),
                                                       expiresInSeconds: expiresInSecondsBuilder(),
                                                       quotedMessage: quotedMessageBuilder(),
                                                       contactShare: contactShareBuilder(),
                                                       linkPreview: linkPreviewBuilder(),
                                                       messageSticker: messageStickerBuilder(),
                                                       serverTimestamp: serverTimestampBuilder(),
                                                       serverDeliveryTimestamp: serverDeliveryTimestampBuilder(),
                                                       serverGuid: serverGuidBuilder(),
                                                       wasReceivedByUD: wasReceivedByUDBuilder(),
                                                       isViewOnceMessage: isViewOnceMessageBuilder(),
                                                       storyAuthorAddress: storyAuthorAddressBuilder(),
                                                       storyTimestamp: storyTimestampBuilder(),
                                                       storyReactionEmoji: storyReactionEmojiBuilder(),
                                                       giftBadge: giftBadgeBuilder())
        let item = builder.build()
        item.anyInsert(transaction: transaction)
        return item
    }

    // MARK: Dependent Factories

    @objc
    public var threadCreator: (SDSAnyWriteTransaction) -> TSThread = { transaction in
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
    public var bodyRangesBuilder: () -> MessageBodyRanges = {
        return MessageBodyRanges.empty
    }

    @objc
    public var authorAddressBuilder: (TSThread) -> SignalServiceAddress = { thread in
        switch thread {
        case let contactThread as TSContactThread:
            return contactThread.contactAddress
        case let groupThread as TSGroupThread:
            let randomAddress = groupThread.recipientAddressesWithSneakyTransaction.randomElement() ?? CommonGenerator.address()
            return randomAddress
        default:
            owsFailDebug("unexpected thread type")
            return CommonGenerator.address()
        }
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
    public var messageStickerBuilder: () -> MessageSticker? = {
        return nil
    }

    @objc
    public var serverTimestampBuilder: () -> NSNumber? = {
        return nil
    }

    @objc
    public var serverDeliveryTimestampBuilder: () -> UInt64 = {
        return 0
    }

    @objc
    public var serverGuidBuilder: () -> String? = {
        return nil
    }

    @objc
    public var wasReceivedByUDBuilder: () -> Bool = {
        return false
    }

    @objc
    public var isViewOnceMessageBuilder: () -> Bool = {
        return false
    }

    @objc
    public var storyAuthorAddressBuilder: () -> SignalServiceAddress? = {
        nil
    }

    @objc
    public var storyTimestampBuilder: () -> NSNumber? = {
        nil
    }

    @objc
    public var storyReactionEmojiBuilder: () -> String? = {
        return nil
    }

    @objc
    public var giftBadgeBuilder: () -> OWSGiftBadge? = {
        return nil
    }
}

@objc
public class GroupThreadFactory: NSObject, Factory {

    @objc
    public var messageCount: UInt = 0

    @objc
    public func create(transaction: SDSAnyWriteTransaction) -> TSGroupThread {
        let thread = try! GroupManager.createGroupForTests(members: memberAddressesBuilder(),
                                                           name: titleBuilder(),
                                                           avatarData: groupAvatarDataBuilder(),
                                                           groupsVersion: groupsVersionBuilder(),
                                                           transaction: transaction)

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

    @objc
    public var titleBuilder: () -> String? = {
        return CommonGenerator.words(count: 3)
    }

    @objc
    public var groupsVersionBuilder: () -> GroupsVersion = {
        // TODO: Make this .V2.
        return .V1
    }

    @objc
    public var groupAvatarDataBuilder: () -> Data? = {
        return nil
    }

    @objc
    public var memberAddressesBuilder: () -> [SignalServiceAddress] = {
        let groupSize = Int.random(in: 1...10)
        return (0..<groupSize).map { _ in  CommonGenerator.address(hasPhoneNumber: Bool.random()) }
    }
}

@objc
public class ConversationFactory: NSObject {

    @objc
    public var attachmentCount: Int = 0

    @objc
    @discardableResult
    public func createSentMessage(transaction: SDSAnyWriteTransaction) -> TSOutgoingMessage {
        let outgoingFactory = OutgoingMessageFactory()
        outgoingFactory.threadCreator = threadCreator
        let message = outgoingFactory.create(transaction: transaction)

        let attachmentInfos: [OutgoingAttachmentInfo] = (0..<attachmentCount).map { albumIndex in
            let caption = Bool.random() ? "(\(albumIndex)) \(CommonGenerator.sentence)" : nil
            return attachmentInfoBuilder(message, caption)
        }

        databaseStorage.asyncWrite { asyncTransaction in
            let messagePreparer = OutgoingMessagePreparer(message, unsavedAttachmentInfos: attachmentInfos)
            _ = try! messagePreparer.prepareMessage(transaction: asyncTransaction)

            for attachment in message.allAttachments(with: asyncTransaction.unwrapGrdbRead) as! [TSAttachmentStream] {
                attachment.updateAsUploaded(withEncryptionKey: Randomness.generateRandomBytes(16),
                                            digest: Randomness.generateRandomBytes(16),
                                            serverId: 1,
                                            cdnKey: "",
                                            cdnNumber: 0,
                                            uploadTimestamp: 1,
                                            transaction: asyncTransaction)
            }

            message.update(withFakeMessageState: .sent, transaction: asyncTransaction)
        }

        return message
    }

    @objc
    public var threadCreator: (SDSAnyWriteTransaction) -> TSThread = { transaction in
        ContactThreadFactory().create(transaction: transaction)
    }

    @objc
    public var attachmentInfoBuilder: (TSOutgoingMessage, String?) -> OutgoingAttachmentInfo = { outgoingMessage, caption in
        let dataSource = DataSourceValue.dataSource(with: ImageFactory().buildPNGData(), fileExtension: "png")!
        return OutgoingAttachmentInfo(dataSource: dataSource,
                                      contentType: "image/png",
                                      sourceFilename: nil,
                                      caption: caption,
                                      albumMessageId: outgoingMessage.uniqueId,
                                      isBorderless: false,
                                      isLoopingVideo: false)
    }

}

@objc
public class AttachmentStreamFactory: NSObject, Factory {

    @objc
    class public func create(contentType: String, dataSource: DataSource) -> TSAttachmentStream {
        var item: TSAttachmentStream!
        write { transaction in
            item = create(contentType: contentType, dataSource: dataSource, transaction: transaction)
        }
        return item
    }

    @objc
    class public func create(contentType: String, dataSource: DataSource, transaction: SDSAnyWriteTransaction) -> TSAttachmentStream {
        let factory = AttachmentStreamFactory()
        factory.contentTypeBuilder = { return contentType }
        factory.byteCountBuilder = { return UInt32(dataSource.dataLength) }
        factory.sourceFilenameBuilder = { return dataSource.sourceFilename ?? "fake-filename.dat" }

        let attachmentStream = factory.build(transaction: transaction)
        try! dataSource.write(to: attachmentStream.originalMediaURL!)

        attachmentStream.anyInsert(transaction: transaction)

        return attachmentStream
    }

    // MARK: Factory

    @objc
    public func create(transaction: SDSAnyWriteTransaction) -> TSAttachmentStream {
        let attachmentStream = build(transaction: transaction)
        attachmentStream.anyInsert(transaction: transaction)

        return attachmentStream
    }

    @objc
    public func build(transaction: SDSAnyReadTransaction) -> TSAttachmentStream {
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

public class ContactFactory {
    public init() { }

    public func build() throws -> Contact {

        var userTextPhoneNumbers: [String] = []
        var phoneNumberNameMap: [String: String] = [:]
        var parsedPhoneNumbers: [PhoneNumber] = []
        for (userText, label) in userTextPhoneNumberAndLabelBuilder() {
            for parsedPhoneNumber in PhoneNumber.tryParsePhoneNumbers(fromUserSpecifiedText: userText, clientPhoneNumber: localClientPhonenumber) {
                parsedPhoneNumbers.append(parsedPhoneNumber)
                phoneNumberNameMap[parsedPhoneNumber.toE164()] = label
                userTextPhoneNumbers.append(userText)
            }
        }

        return Contact(uniqueId: uniqueIdBuilder(),
                       cnContactId: cnContactIdBuilder(),
                       firstName: firstNameBuilder(),
                       lastName: lastNameBuilder(),
                       nickname: nicknameBuilder(),
                       fullName: fullNameBuilder(),
                       userTextPhoneNumbers: userTextPhoneNumbers,
                       phoneNumberNameMap: phoneNumberNameMap,
                       parsedPhoneNumbers: parsedPhoneNumbers,
                       emails: emailsBuilder())
    }

    public var localClientPhonenumber: String = "+13235551234"

    public var uniqueIdBuilder: () -> String = {
        return UUID().uuidString
    }

    public var cnContactIdBuilder: () -> String? = {
        return nil
    }

    public var firstNameBuilder: () -> String? = {
        return CommonGenerator.firstName()
    }

    public var lastNameBuilder: () -> String? = {
        return CommonGenerator.lastName()
    }

    public var nicknameBuilder: () -> String? = {
        return CommonGenerator.nickname()
    }

    public var fullNameBuilder: () -> String = {
        return CommonGenerator.fullName()
    }

    public var userTextPhoneNumberAndLabelBuilder: () -> [(String, String)] = {
        return [(CommonGenerator.e164(), "Main")]
    }

    public var emailsBuilder: () -> [String] = {
        return [CommonGenerator.email()]
    }
}

@objc
public class CommonGenerator: NSObject {

    @objc
    static public func e164() -> String {
        // note 4 zeros in the last group to mimic the spacing of a phone number
        return String(format: "+1%010ld", Int.random(in: 0..<1_000_000_0000))
    }

    @objc
    static public func address() -> SignalServiceAddress {
        return address(hasPhoneNumber: true)
    }

    @objc
    static public func email() -> String {
        return "\(word)@\(word).\(word)"
    }

    @objc
    static public func address(hasUUID: Bool = true, hasPhoneNumber: Bool = true) -> SignalServiceAddress {
        return SignalServiceAddress(uuid: hasUUID ? UUID() : nil, phoneNumber: hasPhoneNumber ? e164() : nil)
    }

    @objc
    static public let firstNames = [
        "Alan",
        "Alex",
        "Alice",
        "Amy",
        "Arthur",
        "Aruna",
        "Bertha",
        "Bob",
        "Brian",
        "Carlos",
        "Carol",
        "Carole",
        "Charlie",
        "Chuck",
        "Cody",
        "Craig",
        "Curt",
        "Dan",
        "Dave",
        "David",
        "Ehren",
        "Erin",
        "Eve",
        "Faythe",
        "Frank",
        "Gerardo",
        "Grace",
        "Gregg",
        "Greyson",
        "Heidi",
        "Jack",
        "Jeff",
        "Jim",
        "Jon",
        "Josh",
        "Jun",
        "Ken",
        "Lilia",
        "Mallet",
        "Mallory",
        "Matthew",
        "Merlin",
        "Michael",
        "Michelle",
        "Moxie",
        "Myles",
        "Nancy",
        "Nolan",
        "Nora",
        "Oscar",
        "Pat",
        "Paul",
        "Peggy",
        "Peter",
        "Randall",
        "Riya",
        "Scott",
        "Sybil",
        "Ted",
        "Trent",
        "Trevor",
        "Trudy",
        "Vanna",
        "Victor",
        "Walter",
        "Wendy"
    ]

    @objc
    static public var lastNames = [
        "Abbott",
        "Acevedo",
        "Acosta",
        "Adams",
        "Adkins",
        "Aguilar",
        "Aguirre",
        "Albert",
        "Alexander",
        "Alford",
        "Allen",
        "Allison",
        "Alston",
        "Alvarado",
        "Alvarez",
        "Anderson",
        "Andrews",
        "Anthony",
        "Armstrong",
        "Arnold",
        "Ashley",
        "Atkins",
        "Atkinson",
        "Austin",
        "Avery",
        "Avila",
        "Ayala",
        "Ayers",
        "Bailey",
        "Baird",
        "Baker",
        "Baldwin",
        "Ball",
        "Ballard",
        "Banks",
        "Barber",
        "Barker",
        "Barlow",
        "Barnes",
        "Barnett",
        "Barr",
        "Barrera",
        "Barrett",
        "Barron",
        "Barry",
        "Bartlett",
        "Barton",
        "Bass",
        "Bates",
        "Battle",
        "Bauer",
        "Baxter",
        "Beach",
        "Bean",
        "Beard",
        "Beasley",
        "Beck",
        "Becker",
        "Bell",
        "Bender",
        "Benjamin",
        "Bennett",
        "Benson",
        "Bentley",
        "Benton",
        "Berg",
        "Berger",
        "Bernard",
        "Berry",
        "Best",
        "Bird",
        "Bishop",
        "Black",
        "Blackburn",
        "Blackwell",
        "Blair",
        "Blake",
        "Blanchard",
        "Blankenship",
        "Blevins",
        "Bolton",
        "Bond",
        "Bonner",
        "Booker",
        "Boone",
        "Booth",
        "Bowen",
        "Bowers",
        "Bowman",
        "Boyd",
        "Boyer",
        "Boyle",
        "Bradford",
        "Bradley",
        "Bradshaw",
        "Brady",
        "Branch",
        "Bray",
        "Brennan",
        "Brewer",
        "Bridges",
        "Briggs",
        "Bright",
        "Britt",
        "Brock",
        "Brooks",
        "Brown",
        "Browning",
        "Bruce",
        "Bryan",
        "Bryant",
        "Buchanan",
        "Buck",
        "Buckley",
        "Buckner",
        "Bullock",
        "Burch",
        "Burgess",
        "Burke",
        "Burks",
        "Burnett",
        "Burns",
        "Burris",
        "Burt",
        "Burton",
        "Bush",
        "Butler",
        "Byers",
        "Byrd",
        "Cabrera",
        "Cain",
        "Calderon",
        "Caldwell",
        "Calhoun",
        "Callahan",
        "Camacho",
        "Cameron",
        "Campbell",
        "Campos",
        "Cannon",
        "Cantrell",
        "Cantu",
        "Cardenas",
        "Carey",
        "Carlson",
        "Carney",
        "Carpenter",
        "Carr",
        "Carrillo",
        "Carroll",
        "Carson",
        "Carter",
        "Carver",
        "Case",
        "Casey",
        "Cash",
        "Castaneda",
        "Castillo",
        "Castro",
        "Cervantes",
        "Chambers",
        "Chan",
        "Chandler",
        "Chaney",
        "Chang",
        "Chapman",
        "Charles",
        "Chase",
        "Chavez",
        "Chen",
        "Cherry",
        "Christensen",
        "Christian",
        "Church",
        "Clark",
        "Clarke",
        "Clay",
        "Clayton",
        "Clements",
        "Clemons",
        "Cleveland",
        "Cline",
        "Cobb",
        "Cochran",
        "Coffey",
        "Cohen",
        "Cole",
        "Coleman",
        "Collier",
        "Collins",
        "Colon",
        "Combs",
        "Compton",
        "Conley",
        "Conner",
        "Conrad",
        "Contreras",
        "Conway",
        "Cook",
        "Cooke",
        "Cooley",
        "Cooper",
        "Copeland",
        "Cortez",
        "Cote",
        "Cotton",
        "Cox",
        "Craft",
        "Craig",
        "Crane",
        "Crawford",
        "Crosby",
        "Cross",
        "Cruz",
        "Cummings",
        "Cunningham",
        "Curry",
        "Curtis",
        "Dale",
        "Dalton",
        "Daniel",
        "Daniels",
        "Daugherty",
        "Davenport",
        "David",
        "Davidson",
        "Davis",
        "Dawson",
        "Day",
        "Dean",
        "Decker",
        "Dejesus",
        "Delacruz",
        "Delaney",
        "Deleon",
        "Delgado",
        "Dennis",
        "Diaz",
        "Dickerson",
        "Dickson",
        "Dillard",
        "Dillon",
        "Dixon",
        "Dodson",
        "Dominguez",
        "Donaldson",
        "Donovan",
        "Dorsey",
        "Dotson",
        "Douglas",
        "Downs",
        "Doyle",
        "Drake",
        "Dudley",
        "Duffy",
        "Duke",
        "Duncan",
        "Dunlap",
        "Dunn",
        "Duran",
        "Durham",
        "Dyer",
        "Eaton",
        "Edwards",
        "Elliott",
        "Ellis",
        "Ellison",
        "Emerson",
        "England",
        "English",
        "Erickson",
        "Espinoza",
        "Estes",
        "Estrada",
        "Evans",
        "Everett",
        "Ewing",
        "Farley",
        "Farmer",
        "Farrell",
        "Faulkner",
        "Ferguson",
        "Fernandez",
        "Ferrell",
        "Fields",
        "Figueroa",
        "Finch",
        "Finley",
        "Fischer",
        "Fisher",
        "Fitzgerald",
        "Fitzpatrick",
        "Fleming",
        "Fletcher",
        "Flores",
        "Flowers",
        "Floyd",
        "Flynn",
        "Foley",
        "Forbes",
        "Ford",
        "Foreman",
        "Foster",
        "Fowler",
        "Fox",
        "Francis",
        "Franco",
        "Frank",
        "Franklin",
        "Franks",
        "Frazier",
        "Frederick",
        "Freeman",
        "French",
        "Frost",
        "Fry",
        "Frye",
        "Fuentes",
        "Fuller",
        "Fulton",
        "Gaines",
        "Gallagher",
        "Gallegos",
        "Galloway",
        "Gamble",
        "Garcia",
        "Gardner",
        "Garner",
        "Garrett",
        "Garrison",
        "Garza",
        "Gates",
        "Gay",
        "Gentry",
        "George",
        "Gibbs",
        "Gibson",
        "Gilbert",
        "Giles",
        "Gill",
        "Gillespie",
        "Gilliam",
        "Gilmore",
        "Glass",
        "Glenn",
        "Glover",
        "Goff",
        "Golden",
        "Gomez",
        "Gonzales",
        "Gonzalez",
        "Good",
        "Goodman",
        "Goodwin",
        "Gordon",
        "Gould",
        "Graham",
        "Grant",
        "Graves",
        "Gray",
        "Green",
        "Greene",
        "Greer",
        "Gregory",
        "Griffin",
        "Griffith",
        "Grimes",
        "Gross",
        "Guerra",
        "Guerrero",
        "Guthrie",
        "Gutierrez",
        "Guy",
        "Guzman",
        "Hahn",
        "Hale",
        "Haley",
        "Hall",
        "Hamilton",
        "Hammond",
        "Hampton",
        "Hancock",
        "Haney",
        "Hansen",
        "Hanson",
        "Hardin",
        "Harding",
        "Hardy",
        "Harmon",
        "Harper",
        "Harrell",
        "Harrington",
        "Harris",
        "Harrison",
        "Hart",
        "Hartman",
        "Harvey",
        "Hatfield",
        "Hawkins",
        "Hayden",
        "Hayes",
        "Haynes",
        "Hays",
        "Head",
        "Heath",
        "Hebert",
        "Henderson",
        "Hendricks",
        "Hendrix",
        "Henry",
        "Hensley",
        "Henson",
        "Herman",
        "Hernandez",
        "Herrera",
        "Herring",
        "Hess",
        "Hester",
        "Hewitt",
        "Hickman",
        "Hicks",
        "Higgins",
        "Hill",
        "Hines",
        "Hinton",
        "Hobbs",
        "Hodge",
        "Hodges",
        "Hoffman",
        "Hogan",
        "Holcomb",
        "Holden",
        "Holder",
        "Holland",
        "Holloway",
        "Holman",
        "Holmes",
        "Holt",
        "Hood",
        "Hooper",
        "Hoover",
        "Hopkins",
        "Hopper",
        "Horn",
        "Horne",
        "Horton",
        "House",
        "Houston",
        "Howard",
        "Howe",
        "Howell",
        "Hubbard",
        "Huber",
        "Hudson",
        "Huff",
        "Huffman",
        "Hughes",
        "Hull",
        "Humphrey",
        "Hunt",
        "Hunter",
        "Hurley",
        "Hurst",
        "Hutchinson",
        "Hyde",
        "Ingram",
        "Irwin",
        "Jackson",
        "Jacobs",
        "Jacobson",
        "James",
        "Jarvis",
        "Jefferson",
        "Jenkins",
        "Jennings",
        "Jensen",
        "Jimenez",
        "Johns",
        "Johnson",
        "Johnston",
        "Jones",
        "Jordan",
        "Joseph",
        "Joyce",
        "Joyner",
        "Juarez",
        "Justice",
        "Kane",
        "Kaufman",
        "Keith",
        "Keller",
        "Kelley",
        "Kelly",
        "Kemp",
        "Kennedy",
        "Kent",
        "Kerr",
        "Key",
        "Kidd",
        "Kim",
        "King",
        "Kinney",
        "Kirby",
        "Kirk",
        "Kirkland",
        "Klein",
        "Kline",
        "Knapp",
        "Knight",
        "Knowles",
        "Knox",
        "Koch",
        "Kramer",
        "Lamb",
        "Lambert",
        "Lancaster",
        "Landry",
        "Lane",
        "Lang",
        "Langley",
        "Lara",
        "Larsen",
        "Larson",
        "Lawrence",
        "Lawson",
        "Le",
        "Leach",
        "Leblanc",
        "Lee",
        "Leon",
        "Leonard",
        "Lester",
        "Levine",
        "Levy",
        "Lewis",
        "Lindsay",
        "Lindsey",
        "Little",
        "Livingston",
        "Lloyd",
        "Logan",
        "Long",
        "Lopez",
        "Lott",
        "Love",
        "Lowe",
        "Lowery",
        "Lucas",
        "Luna",
        "Lynch",
        "Lynn",
        "Lyons",
        "Macdonald",
        "Macias",
        "Mack",
        "Madden",
        "Maddox",
        "Maldonado",
        "Malone",
        "Mann",
        "Manning",
        "Marks",
        "Marquez",
        "Marsh",
        "Marshall",
        "Martin",
        "Martinez",
        "Mason",
        "Massey",
        "Mathews",
        "Mathis",
        "Matthews",
        "Maxwell",
        "May",
        "Mayer",
        "Maynard",
        "Mayo",
        "Mays",
        "Mcbride",
        "Mccall",
        "Mccarthy",
        "Mccarty",
        "Mcclain",
        "Mcclure",
        "Mcconnell",
        "Mccormick",
        "Mccoy",
        "Mccray",
        "Mccullough",
        "Mcdaniel",
        "Mcdonald",
        "Mcdowell",
        "Mcfadden",
        "Mcfarland",
        "Mcgee",
        "Mcgowan",
        "Mcguire",
        "Mcintosh",
        "Mcintyre",
        "Mckay",
        "Mckee",
        "Mckenzie",
        "Mckinney",
        "Mcknight",
        "Mclaughlin",
        "Mclean",
        "Mcleod",
        "Mcmahon",
        "Mcmillan",
        "Mcneil",
        "Mcpherson",
        "Meadows",
        "Medina",
        "Mejia",
        "Melendez",
        "Melton",
        "Mendez",
        "Mendoza",
        "Mercado",
        "Mercer",
        "Merrill",
        "Merritt",
        "Meyer",
        "Meyers",
        "Michael",
        "Middleton",
        "Miles",
        "Miller",
        "Mills",
        "Miranda",
        "Mitchell",
        "Molina",
        "Monroe",
        "Montgomery",
        "Montoya",
        "Moody",
        "Moon",
        "Mooney",
        "Moore",
        "Morales",
        "Moran",
        "Moreno",
        "Morgan",
        "Morin",
        "Morris",
        "Morrison",
        "Morrow",
        "Morse",
        "Morton",
        "Moses",
        "Mosley",
        "Moss",
        "Mueller",
        "Mullen",
        "Mullins",
        "Munoz",
        "Murphy",
        "Murray",
        "Myers",
        "Nash",
        "Navarro",
        "Neal",
        "Nelson",
        "Newman",
        "Newton",
        "Nguyen",
        "Nichols",
        "Nicholson",
        "Nielsen",
        "Nieves",
        "Nixon",
        "Noble",
        "Noel",
        "Nolan",
        "Norman",
        "Norris",
        "Norton",
        "Nunez",
        "O'brien",
        "O'connor",
        "O'donnell",
        "O'neal",
        "O'neil",
        "O'neill",
        "Ochoa",
        "Odom",
        "Oliver",
        "Olsen",
        "Olson",
        "Orr",
        "Ortega",
        "Ortiz",
        "Osborn",
        "Osborne",
        "Owen",
        "Owens",
        "Pace",
        "Pacheco",
        "Padilla",
        "Page",
        "Palmer",
        "Park",
        "Parker",
        "Parks",
        "Parrish",
        "Parsons",
        "Pate",
        "Patel",
        "Patrick",
        "Patterson",
        "Patton",
        "Paul",
        "Payne",
        "Pearson",
        "Peck",
        "Pena",
        "Pennington",
        "Perez",
        "Perkins",
        "Perry",
        "Peters",
        "Petersen",
        "Peterson",
        "Petty",
        "Phelps",
        "Phillips",
        "Pickett",
        "Pierce",
        "Pittman",
        "Pitts",
        "Pollard",
        "Poole",
        "Pope",
        "Porter",
        "Potter",
        "Potts",
        "Powell",
        "Powers",
        "Pratt",
        "Preston",
        "Price",
        "Prince",
        "Pruitt",
        "Puckett",
        "Pugh",
        "Quinn",
        "Ramirez",
        "Ramos",
        "Ramsey",
        "Randall",
        "Randolph",
        "Rasmussen",
        "Ratliff",
        "Ray",
        "Raymond",
        "Reed",
        "Reese",
        "Reeves",
        "Reid",
        "Reilly",
        "Reyes",
        "Reynolds",
        "Rhodes",
        "Rice",
        "Rich",
        "Richard",
        "Richards",
        "Richardson",
        "Richmond",
        "Riddle",
        "Riggs",
        "Riley",
        "Rios",
        "Rivas",
        "Rivera",
        "Rivers",
        "Roach",
        "Robbins",
        "Roberson",
        "Roberts",
        "Robertson",
        "Robinson",
        "Robles",
        "Rocha",
        "Rodgers",
        "Rodriguez",
        "Rodriquez",
        "Rogers",
        "Rojas",
        "Rollins",
        "Roman",
        "Romero",
        "Rosa",
        "Rosales",
        "Rosario",
        "Rose",
        "Ross",
        "Roth",
        "Rowe",
        "Rowland",
        "Roy",
        "Ruiz",
        "Rush",
        "Russell",
        "Russo",
        "Rutledge",
        "Ryan",
        "Salas",
        "Salazar",
        "Salinas",
        "Sampson",
        "Sanchez",
        "Sanders",
        "Sandoval",
        "Sanford",
        "Santana",
        "Santiago",
        "Santos",
        "Sargent",
        "Saunders",
        "Savage",
        "Sawyer",
        "Schmidt",
        "Schneider",
        "Schroeder",
        "Schultz",
        "Schwartz",
        "Scott",
        "Sears",
        "Sellers",
        "Serrano",
        "Sexton",
        "Shaffer",
        "Shannon",
        "Sharp",
        "Sharpe",
        "Shaw",
        "Shelton",
        "Shepard",
        "Shepherd",
        "Sheppard",
        "Sherman",
        "Shields",
        "Short",
        "Silva",
        "Simmons",
        "Simon",
        "Simpson",
        "Sims",
        "Singleton",
        "Skinner",
        "Slater",
        "Sloan",
        "Small",
        "Smith",
        "Snider",
        "Snow",
        "Snyder",
        "Solis",
        "Solomon",
        "Sosa",
        "Soto",
        "Sparks",
        "Spears",
        "Spence",
        "Spencer",
        "Stafford",
        "Stanley",
        "Stanton",
        "Stark",
        "Steele",
        "Stein",
        "Stephens",
        "Stephenson",
        "Stevens",
        "Stevenson",
        "Stewart",
        "Stokes",
        "Stone",
        "Stout",
        "Strickland",
        "Strong",
        "Stuart",
        "Suarez",
        "Sullivan",
        "Summers",
        "Sutton",
        "Swanson",
        "Sweeney",
        "Sweet",
        "Sykes",
        "Talley",
        "Tanner",
        "Tate",
        "Taylor",
        "Terrell",
        "Terry",
        "Thomas",
        "Thompson",
        "Thornton",
        "Tillman",
        "Todd",
        "Torres",
        "Townsend",
        "Tran",
        "Travis",
        "Trevino",
        "Trujillo",
        "Tucker",
        "Turner",
        "Tyler",
        "Tyson",
        "Underwood",
        "Valdez",
        "Valencia",
        "Valentine",
        "Valenzuela",
        "Vance",
        "Vang",
        "Vargas",
        "Vasquez",
        "Vaughan",
        "Vaughn",
        "Vazquez",
        "Vega",
        "Velasquez",
        "Velazquez",
        "Velez",
        "Villarreal",
        "Vincent",
        "Vinson",
        "Wade",
        "Wagner",
        "Walker",
        "Wall",
        "Wallace",
        "Waller",
        "Walls",
        "Walsh",
        "Walter",
        "Walters",
        "Walton",
        "Ward",
        "Ware",
        "Warner",
        "Warren",
        "Washington",
        "Waters",
        "Watkins",
        "Watson",
        "Watts",
        "Weaver",
        "Webb",
        "Weber",
        "Webster",
        "Weeks",
        "Weiss",
        "Welch",
        "Wells",
        "West",
        "Wheeler",
        "Whitaker",
        "White",
        "Whitehead",
        "Whitfield",
        "Whitley",
        "Whitney",
        "Wiggins",
        "Wilcox",
        "Wilder",
        "Wiley",
        "Wilkerson",
        "Wilkins",
        "Wilkinson",
        "William",
        "Williams",
        "Williamson",
        "Willis",
        "Wilson",
        "Winters",
        "Wise",
        "Witt",
        "Wolf",
        "Wolfe",
        "Wong",
        "Wood",
        "Woodard",
        "Woods",
        "Woodward",
        "Wooten",
        "Workman",
        "Wright",
        "Wyatt",
        "Wynn",
        "Yang",
        "Yates",
        "York",
        "Young",
        "Zamora",
        "Zimmerman"
    ]

    @objc
    static public let nicknames = [
        "AAAA",
        "BBBB"
    ]

    @objc
    static public func nickname() -> String {
        return nicknames.randomElement()!
    }

    @objc
    static public func firstName() -> String {
        return firstNames.randomElement()!
    }

    @objc
    static public func lastName() -> String {
        return lastNames.randomElement()!
    }

    @objc
    static public func fullName() -> String {
        if Bool.random() {
            // sometimes only a first name is stored as the full name
            return firstName()
        } else {
            return "\(firstName()) \(lastName())"
        }
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

    @objc
    static public var sentence: String {
        return sentences.randomElement()!
    }

    @objc
    static public func sentences(count: UInt) -> [String] {
        return (0..<count).map { _ in sentence }
    }

    @objc
    static public var paragraph: String {
        paragraph(sentenceCount: UInt.random(in: 2...8))
    }

    @objc
    static public func paragraph(sentenceCount: UInt) -> String {
        return sentences(count: sentenceCount).joined(separator: " ")
    }
}

@objc
public class ImageFactory: NSObject {

    @objc
    public func build() -> UIImage {
        return type(of: self).buildImage(size: sizeBuilder(),
                                         backgroundColor: backgroundColorBuilder(),
                                         textColor: textColorBuilder(),
                                         text: textBuilder())
    }

    @objc
    public func buildPNGData() -> Data {
        guard let data = build().pngData() else {
            owsFailDebug("data was unexpectedly nil")
            return Data()
        }
        return data
    }

    @objc
    public func buildJPGData() -> Data {
        guard let data = build().jpegData(compressionQuality: 0.9) else {
            owsFailDebug("data was unexpectedly nil")
            return Data()
        }
        return data
    }

    public var sizeBuilder: () -> CGSize = { return CGSize(width: (50..<1000).randomElement()!, height: (50..<1000).randomElement()!) }
    public var backgroundColorBuilder: () -> UIColor = { return [UIColor.purple, UIColor.yellow, UIColor.green, UIColor.blue, UIColor.red, UIColor.orange].randomElement()! }
    public var textColorBuilder: () -> UIColor = { return [UIColor.black, UIColor.white].randomElement()! }
    public var textBuilder: () -> String = { return "\(CommonGenerator.word)\n\(CommonGenerator.word)" }

    public class func buildImage(size: CGSize, backgroundColor: UIColor, textColor: UIColor, text: String) -> UIImage {
        return autoreleasepool {
            let imageSize = CGSize(width: size.width / UIScreen.main.scale,
                                   height: size.height / UIScreen.main.scale)

            let imageFrame = CGRect(origin: .zero, size: imageSize)
            let font = UIFont.boldSystemFont(ofSize: imageSize.width * 0.1)

            let textAttributes: [NSAttributedString.Key: Any] = [.font: font,
                                                                 .foregroundColor: textColor]

            let textFrame = text.boundingRect(with: imageFrame.size,
                                              options: [.usesLineFragmentOrigin, .usesFontLeading],
                                              attributes: textAttributes,
                                              context: nil)

            UIGraphicsBeginImageContextWithOptions(imageFrame.size, false, UIScreen.main.scale)
            guard let context = UIGraphicsGetCurrentContext() else {
                owsFailDebug("context was unexpectedly nil")
                return UIImage()
            }

            context.setFillColor(backgroundColor.cgColor)
            context.fill(imageFrame)

            text.draw(at: CGPoint(x: imageFrame.midX - textFrame.midX,
                                  y: imageFrame.midY - textFrame.midY),
                      withAttributes: textAttributes)

            guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
                owsFailDebug("image was unexpectedly nil")
                return UIImage()
            }
            UIGraphicsEndImageContext()

            return image
        }
    }
}

#endif
