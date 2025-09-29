//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

import Foundation
public import LibSignalClient

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
///     let factory = ContactThreadFactory()
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

    static func write(block: @escaping (DBWriteTransaction) -> Void)
    func write(block: @escaping (DBWriteTransaction) -> Void)

    // MARK: Factory Methods
    func create() -> ObjectType
    func create(transaction: DBWriteTransaction) -> ObjectType

    func create(count: UInt) -> [ObjectType]
    func create(count: UInt, transaction: DBWriteTransaction) -> [ObjectType]
}

public extension Factory {

    static func write(block: @escaping (DBWriteTransaction) -> Void) {
        SSKEnvironment.shared.databaseStorageRef.write(block: block)
    }

    func write(block: @escaping (DBWriteTransaction) -> Void) {
        SSKEnvironment.shared.databaseStorageRef.write(block: block)
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

    func create(count: UInt, transaction: DBWriteTransaction) -> [ObjectType] {
        return (0..<count).map { _ in return create(transaction: transaction) }
    }
}

final public class ContactThreadFactory: Factory {

    public var messageCount: UInt = 0

    // MARK: Factory

    public func create(transaction: DBWriteTransaction) -> TSContactThread {
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

    public var contactAddressBuilder: () -> SignalServiceAddress = {
        return CommonGenerator.address()
    }
}

final public class OutgoingMessageFactory: Factory {

    // MARK: Factory

    public func build(transaction: DBWriteTransaction) -> TSOutgoingMessage {
        let message: TSOutgoingMessage = TSOutgoingMessageBuilder(
            thread: threadCreator(transaction),
            timestamp: timestampBuilder(),
            receivedAtTimestamp: receivedAtTimestampBuilder(),
            messageBody: validatedMessageBodyBuilder(transaction),
            editState: editStateBuilder(),
            expiresInSeconds: expiresInSecondsBuilder(),
            expireTimerVersion: expireTimerVersionBuilder(),
            expireStartedAt: expireStartedAtBuilder(),
            isVoiceMessage: isVoiceMessageBuilder(),
            groupMetaMessage: groupMetaMessageBuilder(),
            isSmsMessageRestoredFromBackup: isSmsMessageRestoredFromBackupBuilder(),
            isViewOnceMessage: isViewOnceMessageBuilder(),
            isViewOnceComplete: false,
            wasRemotelyDeleted: false,
            wasNotCreatedLocally: false,
            groupChangeProtoData: groupChangeProtoDataBuilder(),
            storyAuthorAci: storyAuthorAciBuilder(),
            storyTimestamp: storyTimestampBuilder(),
            storyReactionEmoji: storyReactionEmojiBuilder(),
            quotedMessage: quotedMessageBuilder(),
            contactShare: contactShareBuilder(),
            linkPreview: linkPreviewBuilder(),
            messageSticker: messageStickerBuilder(),
            giftBadge: giftBadgeBuilder(),
            isPoll: isPollBuilder()
        ).build(transaction: transaction)
        return message
    }

    public func create(transaction: DBWriteTransaction) -> TSOutgoingMessage {
        let item = self.build(transaction: transaction)
        item.anyInsert(transaction: transaction)

        return item
    }

    // MARK: Dependent Factories

    public var threadCreator: (DBWriteTransaction) -> TSThread = { transaction in
        ContactThreadFactory().create(transaction: transaction)
    }

    // MARK: Generators

    public var timestampBuilder: () -> UInt64 = {
        return NSDate.ows_millisecondTimeStamp()
    }

    public var receivedAtTimestampBuilder: () -> UInt64 = {
        return NSDate.ows_millisecondTimeStamp()
    }

    public lazy var validatedMessageBodyBuilder: (_ tx: DBWriteTransaction) -> ValidatedInlineMessageBody = { tx in
        DependenciesBridge.shared.attachmentContentValidator.truncatedMessageBodyForInlining(
            MessageBody(text: self.messageBodyBuilder(), ranges: self.bodyRangesBuilder()),
            tx: tx
        )
    }

    public var messageBodyBuilder: () -> String = {
        return CommonGenerator.paragraph
    }

    public var bodyRangesBuilder: () -> MessageBodyRanges = {
        return MessageBodyRanges.empty
    }

    public var editStateBuilder: () -> TSEditState = {
        return .none
    }

    public var expiresInSecondsBuilder: () -> UInt32? = {
        return nil
    }

    public var expireTimerVersionBuilder: () -> UInt32? = {
        return nil
    }

    public var expireStartedAtBuilder: () -> UInt64? = {
        return nil
    }

    public var isVoiceMessageBuilder: () -> Bool = {
        return false
    }

    public var groupMetaMessageBuilder: () -> TSGroupMetaMessage = {
        return .unspecified
    }

    public var isSmsMessageRestoredFromBackupBuilder: () -> Bool = {
        return false
    }

    public var isViewOnceMessageBuilder: () -> Bool = {
        return false
    }

    public var groupChangeProtoDataBuilder: () -> Data? = {
        return nil
    }

    public var storyAuthorAciBuilder: () -> Aci? = {
        return nil
    }

    public var storyTimestampBuilder: () -> UInt64? = {
        return nil
    }

    public var storyReactionEmojiBuilder: () -> String? = {
        return nil
    }

    public var quotedMessageBuilder: () -> TSQuotedMessage? = {
        return nil
    }

    public var contactShareBuilder: () -> OWSContact? = {
        return nil
    }

    public var linkPreviewBuilder: () -> OWSLinkPreview? = {
        return nil
    }

    public var messageStickerBuilder: () -> MessageSticker? = {
        return nil
    }

    public var giftBadgeBuilder: () -> OWSGiftBadge? = {
        return nil
    }

    public var isPollBuilder: () -> Bool = {
        return false
    }

    // MARK: Delivery Receipts

    public func buildDeliveryReceipt() -> OWSReceiptsForSenderMessage {
        var item: OWSReceiptsForSenderMessage!
        write { transaction in
            item = self.buildDeliveryReceipt(transaction: transaction)
        }
        return item
    }

    public func buildDeliveryReceipt(transaction: DBWriteTransaction) -> OWSReceiptsForSenderMessage {
        let item = OWSReceiptsForSenderMessage.deliveryReceiptsForSenderMessage(with: threadCreator(transaction),
                                                                                receiptSet: receiptSetBuilder(), transaction: transaction)
        return item
    }

    var receiptSetBuilder: () -> MessageReceiptSet = {
        let set = MessageReceiptSet()
        set.insert(timestamp: 1, messageUniqueId: "hello")
        return set
    }
}

final public class IncomingMessageFactory: Factory {

    // MARK: Factory

    public func create(transaction: DBWriteTransaction) -> TSIncomingMessage {

        let thread = threadCreator(transaction)

        let builder = TSIncomingMessageBuilder(
            thread: thread,
            timestamp: timestampBuilder(),
            receivedAtTimestamp: receivedAtTimestampBuilder(),
            authorAci: authorAciBuilder(thread),
            authorE164: nil,
            messageBody: validatedMessageBodyBuilder(transaction),
            editState: editStateBuilder(),
            expiresInSeconds: expiresInSecondsBuilder(),
            expireTimerVersion: expireTimerVersionBuilder(),
            expireStartedAt: 0,
            read: false,
            serverTimestamp: serverTimestampBuilder(),
            serverDeliveryTimestamp: serverDeliveryTimestampBuilder(),
            serverGuid: serverGuidBuilder(),
            wasReceivedByUD: wasReceivedByUDBuilder(),
            isSmsMessageRestoredFromBackup: isSmsMessageRestoredFromBackupBuilder(),
            isViewOnceMessage: isViewOnceMessageBuilder(),
            isViewOnceComplete: false,
            wasRemotelyDeleted: false,
            storyAuthorAci: storyAuthorAciBuilder(),
            storyTimestamp: storyTimestampBuilder(),
            storyReactionEmoji: storyReactionEmojiBuilder(),
            quotedMessage: quotedMessageBuilder(),
            contactShare: contactShareBuilder(),
            linkPreview: linkPreviewBuilder(),
            messageSticker: messageStickerBuilder(),
            giftBadge: giftBadgeBuilder(),
            paymentNotification: paymentNotificationBuilder(),
            isPoll: isPollBuilder()
        )
        let item = builder.build()
        item.anyInsert(transaction: transaction)
        return item
    }

    // MARK: Dependent Factories

    public var threadCreator: (DBWriteTransaction) -> TSThread = { transaction in
        ContactThreadFactory().create(transaction: transaction)
    }

    // MARK: Generators

    public var timestampBuilder: () -> UInt64 = {
        return NSDate.ows_millisecondTimeStamp()
    }

    public var receivedAtTimestampBuilder: () -> UInt64 = {
        return NSDate.ows_millisecondTimeStamp()
    }

    public lazy var validatedMessageBodyBuilder: (_ tx: DBWriteTransaction) -> ValidatedInlineMessageBody = { tx in
        DependenciesBridge.shared.attachmentContentValidator.truncatedMessageBodyForInlining(
            MessageBody(text: self.messageBodyBuilder(), ranges: self.bodyRangesBuilder()),
            tx: tx
        )
    }

    public var messageBodyBuilder: () -> String = {
        return CommonGenerator.paragraph
    }

    public var bodyRangesBuilder: () -> MessageBodyRanges = {
        return MessageBodyRanges.empty
    }

    public var editStateBuilder: () -> TSEditState = {
        return .none
    }

    public var authorAciBuilder: (TSThread) -> Aci = { thread in
        return { () -> SignalServiceAddress in
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
        }().aci!
    }

    public var expiresInSecondsBuilder: () -> UInt32 = {
        return 0
    }

    public var expireTimerVersionBuilder: () -> UInt32? = {
        return nil
    }

    public var serverTimestampBuilder: () -> UInt64 = {
        return 0
    }

    public var serverDeliveryTimestampBuilder: () -> UInt64 = {
        return 0
    }

    public var serverGuidBuilder: () -> String? = {
        return nil
    }

    public var wasReceivedByUDBuilder: () -> Bool = {
        return false
    }

    public var isSmsMessageRestoredFromBackupBuilder: () -> Bool = {
        return false
    }

    public var isViewOnceMessageBuilder: () -> Bool = {
        return false
    }

    public var storyAuthorAciBuilder: () -> Aci? = {
        nil
    }

    public var storyTimestampBuilder: () -> UInt64? = {
        nil
    }

    public var storyReactionEmojiBuilder: () -> String? = {
        return nil
    }

    public var quotedMessageBuilder: () -> TSQuotedMessage? = {
        return nil
    }

    public var contactShareBuilder: () -> OWSContact? = {
        return nil
    }

    public var linkPreviewBuilder: () -> OWSLinkPreview? = {
        return nil
    }

    public var messageStickerBuilder: () -> MessageSticker? = {
        return nil
    }

    public var giftBadgeBuilder: () -> OWSGiftBadge? = {
        return nil
    }

    public var paymentNotificationBuilder: () -> TSPaymentNotification? = {
        return nil
    }

    public var isPollBuilder: () -> Bool = {
        return false
    }
}

final public class ConversationFactory {

    public init() {}

    @discardableResult
    public func createSentMessage(
        bodyAttachmentDataSources: [AttachmentDataSource],
        transaction: DBWriteTransaction
    ) -> TSOutgoingMessage {
        let outgoingFactory = OutgoingMessageFactory()
        outgoingFactory.threadCreator = threadCreator
        let message = outgoingFactory.create(transaction: transaction)

        Task {
            let messageBody = try! await DependenciesBridge.shared.attachmentContentValidator.prepareOversizeTextIfNeeded(
                MessageBody(text: outgoingFactory.messageBodyBuilder(), ranges: outgoingFactory.bodyRangesBuilder())
            )

            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { asyncTransaction in
                let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(
                    message,
                    body: messageBody,
                    unsavedBodyMediaAttachments: bodyAttachmentDataSources
                )
                _ = try! unpreparedMessage.prepare(tx: asyncTransaction)

                for attachment in message.allAttachments(transaction: asyncTransaction) {
                    guard let stream = attachment.asStream() else {
                        continue
                    }
                    let transitTierInfo = Attachment.TransitTierInfo(
                        cdnNumber: 3,
                        cdnKey: "1234",
                        uploadTimestamp: 1,
                        encryptionKey: Randomness.generateRandomBytes(16),
                        unencryptedByteCount: 16,
                        integrityCheck: .digestSHA256Ciphertext(Randomness.generateRandomBytes(16)),
                        // TODO: [Attachment Streaming] support incremental mac
                        incrementalMacInfo: nil,
                        lastDownloadAttemptTimestamp: nil
                    )
                    try! (DependenciesBridge.shared.attachmentStore as? AttachmentUploadStore)?.markUploadedToTransitTier(
                        attachmentStream: stream,
                        info: transitTierInfo,
                        tx: asyncTransaction
                    )
                }

                message.updateWithFakeMessageState(.sent, tx: asyncTransaction)
            }
        }

        return message
    }

    public var threadCreator: (DBWriteTransaction) -> TSThread = { transaction in
        ContactThreadFactory().create(transaction: transaction)
    }
}

final public class CommonGenerator {

    static public func e164() -> String {
        // note 4 zeros in the last group to mimic the spacing of a phone number
        return String(format: "+1%010ld", Int.random(in: 0..<1_000_000_0000))
    }

    static public func address() -> SignalServiceAddress {
        return address(hasPhoneNumber: true)
    }

    static public func email() -> String {
        return "\(word)@\(word).\(word)"
    }

    static public func address(hasAci: Bool = true, hasPhoneNumber: Bool = true) -> SignalServiceAddress {
        return SignalServiceAddress(
            serviceId: hasAci ? Aci.randomForTesting() : nil,
            phoneNumber: hasPhoneNumber ? e164() : nil
        )
    }

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

    static public let nicknames = [
        "AAAA",
        "BBBB"
    ]

    static public func nickname() -> String {
        return nicknames.randomElement()!
    }

    static public func firstName() -> String {
        return firstNames.randomElement()!
    }

    static public func lastName() -> String {
        return lastNames.randomElement()!
    }

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

    static public var sentence: String {
        return sentences.randomElement()!
    }

    static public func sentences(count: UInt) -> [String] {
        return (0..<count).map { _ in sentence }
    }

    static public var paragraph: String {
        paragraph(sentenceCount: UInt.random(in: 2...8))
    }

    static public func paragraph(sentenceCount: UInt) -> String {
        return sentences(count: sentenceCount).joined(separator: " ")
    }
}

final public class ImageFactory {

    public init() {}

    public func build() -> UIImage {
        return type(of: self).buildImage(size: sizeBuilder(),
                                         backgroundColor: backgroundColorBuilder(),
                                         textColor: textColorBuilder(),
                                         text: textBuilder())
    }

    public func buildPNGData() -> Data {
        guard let data = build().pngData() else {
            owsFailDebug("data was unexpectedly nil")
            return Data()
        }
        return data
    }

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
