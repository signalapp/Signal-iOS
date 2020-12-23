//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
import Contacts

class GroupAndContactStreamTest: SignalBaseTest {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        TSAccountManager.shared()
    }

    // MARK: - Test Life Cycle

    override func setUp() {
        super.setUp()

        // ensure local client has necessary "registered" state
        let localE164Identifier = "+13235551234"
        let localUUID = UUID()
        tsAccountManager.registerForTests(withLocalNumber: localE164Identifier, uuid: localUUID)
    }

    // MARK: -

    let outputContactSyncData = "IQoMKzEzMjMxMTExMTExEgdBbGljZS0xIgRibHVlQABYADkSB0FsaWNlLTIiBGJsdWVAAEokMzFDRTE0MTItOUEyOC00RTZGLUI0RUUtMjIyMjIyMjIyMjIyWABHCgwrMTMyMTMzMzMzMzMSB0FsaWNlLTMiBGJsdWVAAEokMUQ0QUIwNDUtODhGQi00QzRFLTlGNkEtMzMzMzMzMzMzMzMzWAA="

    func test_writeContactSync() throws {
        let signalAccounts = [
            SignalAccount(address: .init(phoneNumber: "+13231111111")),
            SignalAccount(address: .init(uuidString: "31ce1412-9a28-4e6f-b4ee-222222222222")),
            SignalAccount(address: .init(uuidString: "1d4ab045-88fb-4c4e-9f6a-333333333333", phoneNumber: "+13213333333"))
        ]

        let streamData = try buildContactSyncData(signalAccounts: signalAccounts)

        XCTAssertEqual(streamData.base64EncodedString(), outputContactSyncData)
    }

    func test_readContactSync() throws {
        var contacts: [ContactDetails] = []

        let data = Data(base64Encoded: outputContactSyncData)!
        try data.withUnsafeBytes { bufferPtr in
            if let baseAddress = bufferPtr.baseAddress, bufferPtr.count > 0 {
                let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                let inputStream = ChunkedInputStream(forReadingFrom: pointer, count: bufferPtr.count)
                let contactStream = ContactsInputStream(inputStream: inputStream)
                while let nextContact = try contactStream.decodeContact() {
                    contacts.append(nextContact)
                }
            }
        }

        guard contacts.count == 3 else {
            XCTFail("unexpected contact count: \(contacts.count)")
            return
        }

        do {
            let contact = contacts[0]
            XCTAssertEqual("+13231111111", contact.address.phoneNumber)
            XCTAssertNil(contact.address.uuid)
            XCTAssertEqual("Alice-1", contact.name)
            XCTAssertEqual("blue", contact.conversationColorName)
            XCTAssertNil(contact.verifiedProto)
            XCTAssertNil(contact.profileKey)
            XCTAssertEqual(false, contact.isBlocked)
            XCTAssertEqual(0, contact.expireTimer)
            XCTAssertNil(contact.avatarData)
            XCTAssertEqual(false, contact.isArchived)
            XCTAssertNil(contact.inboxSortOrder)
        }

        do {
            let contact = contacts[1]
            XCTAssertNil(contact.address.phoneNumber)
            XCTAssertEqual("31CE1412-9A28-4E6F-B4EE-222222222222", contact.address.uuid?.uuidString)
            XCTAssertEqual("Alice-2", contact.name)
            XCTAssertEqual("blue", contact.conversationColorName)
            XCTAssertNil(contact.verifiedProto)
            XCTAssertNil(contact.profileKey)
            XCTAssertEqual(false, contact.isBlocked)
            XCTAssertEqual(0, contact.expireTimer)
            XCTAssertNil(contact.avatarData)
            XCTAssertEqual(false, contact.isArchived)
            XCTAssertNil(contact.inboxSortOrder)
        }

        do {
            let contact = contacts[2]
            XCTAssertEqual("+13213333333", contact.address.phoneNumber)
            XCTAssertEqual("1D4AB045-88FB-4C4E-9F6A-333333333333", contact.address.uuid?.uuidString)
            XCTAssertEqual("Alice-3", contact.name)
            XCTAssertEqual("blue", contact.conversationColorName)
            XCTAssertNil(contact.verifiedProto)
            XCTAssertNil(contact.profileKey)
            XCTAssertEqual(false, contact.isBlocked)
            XCTAssertEqual(0, contact.expireTimer)
            XCTAssertNil(contact.avatarData)
            XCTAssertEqual(false, contact.isArchived)
            XCTAssertNil(contact.inboxSortOrder)
        }
    }

    let outputGroupSyncData = "awoQc111Fz2xlVb3YbtcfwN0SBoMKzEzMjEzMjE0MzIxGgwrMTMyMTMyMTQzMjMiDgoJaW1hZ2UvcG5nEKMBMAA6BWJyb3duSg4SDCsxMzIxMzIxNDMyMUoOEgwrMTMyMTMyMTQzMjNQAVgAiVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAAD5Ip3+AAAADUlEQVQIHWP4z8DwHwAFAAH/yA9iFgAAAABJRU5ErkJggnoKEHNtthc9sZVW92G7XH8DdEgSCUJvb2sgQ2x1YhoMKzEzMjEzMjE0MzIxGgwrMTU1NTMyMTQzMjMiDgoJaW1hZ2UvcG5nEKMBMAA6CWJsdWVfZ3JleUoOEgwrMTMyMTMyMTQzMjFKDhIMKzE1NTUzMjE0MzIzUAJYAYlQTkcNChoKAAAADUlIRFIAAAABAAAAAQgGAAAAHxXEiQAAAAFzUkdCAK7OHOkAAABEZVhJZk1NACoAAAAIAAGHaQAEAAAAAQAAABoAAAAAAAOgAQADAAAAAQABAACgAgAEAAAAAQAAAAGgAwAEAAAAAQAAAAEAAAAA+SKd/gAAAA1JREFUCB1jYGD4/x8AAwIB/6fhVKUAAAAASUVORK5CYIJ1ChBzffcXPbGVVvdhu1x/A3RIEglDb29rIEJsdWIaDCsxMzIxMzIxMzMzMxoMKzE1NTUzMjEyMjIyIg4KCWltYWdlL3BuZxCjATAAOgRibHVlSg4SDCsxMzIxMzIxMzMzM0oOEgwrMTU1NTMyMTIyMjJQAFgBiVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAAD5Ip3+AAAADUlEQVQIHWNg+M/wHwAEAQH/MH0Y7gAAAABJRU5ErkJggg=="

    let groupImageData1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAAD5Ip3+AAAADUlEQVQIHWP4z8DwHwAFAAH/yA9iFgAAAABJRU5ErkJggg=="
    let groupImageData2 =  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAAD5Ip3+AAAADUlEQVQIHWNgYPj/HwADAgH/p+FUpQAAAABJRU5ErkJggg=="
    let groupImageData3 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAAD5Ip3+AAAADUlEQVQIHWNg+M/wHwAEAQH/MH0Y7gAAAABJRU5ErkJggg=="

    func test_writeGroupSync() throws {
        let groupAvatarData1 = Data(base64Encoded: groupImageData1)!
        let groupAvatarData2 = Data(base64Encoded: groupImageData2)!
        let groupAvatarData3 = Data(base64Encoded: groupImageData3)!

        let group1: TSGroupThread = {
            let groupId = Data(base64Encoded: "c111Fz2xlVb3YbtcfwN0SA==")!
            let groupMembers: [SignalServiceAddress] = [
                .init(phoneNumber: "+13213214321"),
                .init(uuidString: "1d4ab045-88fb-4c4e-9f6a-f921124bd529", phoneNumber: "+13213214323")
            ]

            var thread: TSGroupThread!
            write { transaction in
                thread = try! GroupManager.createGroupForTests(members: groupMembers,
                                                               avatarData: groupAvatarData1,
                                                               groupId: groupId,
                                                               transaction: transaction)
                thread.updateConversationColorName(.burlap, transaction: transaction)
            }
            return thread
        }()

        let group2: TSGroupThread = {
            let groupId = Data(base64Encoded: "c222Fz2xlVb3YbtcfwN0SA==")!
            let groupMembers: [SignalServiceAddress] = [
                .init(phoneNumber: "+13213214321"),
                .init(uuidString: "55555555-88fb-4c4e-9f6a-f921124bd529", phoneNumber: "+15553214323")
            ]

            var thread: TSGroupThread!
            write {
                thread = try! GroupManager.createGroupForTests(members: groupMembers,
                                                               name: "Book Club",
                                                               avatarData: groupAvatarData2,
                                                               groupId: groupId,
                                                               transaction: $0)
                thread.shouldThreadBeVisible = true
                thread.anyOverwritingUpdate(transaction: $0)
                thread.updateConversationColorName(.taupe, transaction: $0)
                thread.archiveThread(updateStorageService: false, transaction: $0)
            }
            return thread
        }()

        let group3: TSGroupThread = {
            let groupId = Data(base64Encoded: "c333Fz2xlVb3YbtcfwN0SA==")!
            let groupMembers: [SignalServiceAddress] = [
                .init(phoneNumber: "+13213213333"),
                .init(uuidString: "55555555-88fb-4c4e-9f6a-222222222222", phoneNumber: "+15553212222")
            ]

            var thread: TSGroupThread!
            write { transaction in
                thread = try! GroupManager.createGroupForTests(members: groupMembers,
                                                               name: "Cook Blub",
                                                               avatarData: groupAvatarData3,
                                                               groupId: groupId,
                                                               transaction: transaction)
                thread.shouldThreadBeVisible = true
                thread.anyOverwritingUpdate(transaction: transaction)
                thread.updateConversationColorName(.blue, transaction: transaction)

                let messageFactory = OutgoingMessageFactory()
                messageFactory.threadCreator = { _ in thread }
                _ = messageFactory.create(transaction: transaction)

                thread.archiveThread(updateStorageService: false, transaction: transaction)
            }
            return thread
        }()

        let streamData = try buildGroupSyncData(groupThreads: [group1, group2, group3])

        XCTAssertEqual(streamData.base64EncodedString(), outputGroupSyncData)
    }

    func test_readGroupSync() throws {
        let groupAvatarData1 = Data(base64Encoded: groupImageData1)!
        let groupAvatarData2 = Data(base64Encoded: groupImageData2)!
        let groupAvatarData3 = Data(base64Encoded: groupImageData3)!

        var groups: [GroupDetails] = []

        let data = Data(base64Encoded: outputGroupSyncData)!
        try data.withUnsafeBytes { bufferPtr in
            if let baseAddress = bufferPtr.baseAddress, bufferPtr.count > 0 {
                let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                let inputStream = ChunkedInputStream(forReadingFrom: pointer, count: bufferPtr.count)
                let groupStream = GroupsInputStream(inputStream: inputStream)
                while let nextGroup = try groupStream.decodeGroup() {
                    groups.append(nextGroup)
                }
            }
        }

        guard groups.count == 3 else {
            XCTFail("unexpected group count: \(groups.count)")
            return
        }

        do {
            let group = groups[0]
            XCTAssertEqual(group.groupId, Data(base64Encoded: "c111Fz2xlVb3YbtcfwN0SA==")!)
            XCTAssertEqual(group.name, nil)
            XCTAssertEqual(group.memberAddresses, [
                SignalServiceAddress(phoneNumber: "+13213214321"),
                SignalServiceAddress(uuidString: "1d4ab045-88fb-4c4e-9f6a-f921124bd529", phoneNumber: "+13213214323")
            ])

            XCTAssertEqual(group.conversationColorName, ConversationColorName.burlap.rawValue)
            XCTAssertEqual(group.isBlocked, false)
            XCTAssertEqual(group.expireTimer, 0)
            XCTAssertEqual(group.avatarData, groupAvatarData1)
            XCTAssertEqual(false, group.isArchived)
            XCTAssertEqual(1, group.inboxSortOrder)
        }

        do {
            let group = groups[1]
            XCTAssertEqual(group.groupId, Data(base64Encoded: "c222Fz2xlVb3YbtcfwN0SA==")!)
            XCTAssertEqual(group.name, "Book Club")
            XCTAssertEqual(group.memberAddresses, [
                SignalServiceAddress(phoneNumber: "+13213214321"),
                SignalServiceAddress(uuidString: "55555555-88fb-4c4e-9f6a-f921124bd529", phoneNumber: "+15553214323")
            ])
            XCTAssertEqual(group.conversationColorName, ConversationColorName.taupe.rawValue)
            XCTAssertEqual(group.isBlocked, false)
            XCTAssertEqual(group.expireTimer, 0)
            XCTAssertEqual(group.avatarData, groupAvatarData2)
            XCTAssertEqual(true, group.isArchived)
            XCTAssertEqual(2, group.inboxSortOrder)
        }

        do {
            let group = groups[2]
            XCTAssertEqual(group.groupId, Data(base64Encoded: "c333Fz2xlVb3YbtcfwN0SA==")!)
            XCTAssertEqual(group.name, "Cook Blub")
            XCTAssertEqual(group.memberAddresses, [
                SignalServiceAddress(phoneNumber: "+13213213333"),
                SignalServiceAddress(uuidString: "55555555-88FB-4C4E-9F6A-222222222222", phoneNumber: "+15553212222")
            ])
            XCTAssertEqual(group.conversationColorName, ConversationColorName.blue.rawValue)
            XCTAssertEqual(group.isBlocked, false)
            XCTAssertEqual(group.expireTimer, 0)
            XCTAssertEqual(group.avatarData, groupAvatarData3)
            XCTAssertEqual(true, group.isArchived)
            XCTAssertEqual(0, group.inboxSortOrder)
        }
    }

    func buildContactSyncData(signalAccounts: [SignalAccount]) throws -> Data {
        let contactsManager = TestContactsManager()
        let dataOutputStream = OutputStream(toMemory: ())
        dataOutputStream.open()
        let contactsOutputStream = OWSContactsOutputStream(outputStream: dataOutputStream)

        for signalAccount in signalAccounts {
            let contactFactory = ContactFactory()
            contactFactory.fullNameBuilder = {
                "Alice-\(signalAccount.recipientAddress.serviceIdentifier!.suffix(1))"
            }
            contactFactory.cnContactIdBuilder = { "123" }
            contactFactory.uniqueIdBuilder = { "123" }

            signalAccount.replaceContactForTests(try contactFactory.build())

            contactsOutputStream.write(signalAccount,
                                       recipientIdentity: nil,
                                       profileKeyData: nil,
                                       contactsManager: contactsManager,
                                       conversationColorName: ConversationColorName.blue.rawValue,
                                       disappearingMessagesConfiguration: nil,
                                       isArchived: false,
                                       inboxPosition: nil)
        }

        dataOutputStream.close()
        guard !contactsOutputStream.hasError else {
            throw OWSAssertionError("contactsOutputStream.hasError")
        }

        return dataOutputStream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
    }

    func buildGroupSyncData(groupThreads: [TSGroupThread]) throws -> Data {
        let dataOutputStream = OutputStream(toMemory: ())
        dataOutputStream.open()
        let groupsOutputStream = OWSGroupsOutputStream(outputStream: dataOutputStream)

        read { transaction in
            for groupThread in groupThreads {
                groupsOutputStream.writeGroup(groupThread, transaction: transaction)
            }
        }

        dataOutputStream.close()
        guard !groupsOutputStream.hasError else {
            throw OWSAssertionError("contactsOutputStream.hasError")
        }

        return dataOutputStream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
    }
}

class TestContactsManager: NSObject, ContactsManagerProtocol {
    func hasNameInSystemContacts(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        false
    }

    func comparableName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        self.displayName(for: address)
    }

    func comparableName(for signalAccount: SignalAccount, transaction: SDSAnyReadTransaction) -> String {
        signalAccount.recipientAddress.stringForDisplay
    }

    func displayName(for address: SignalServiceAddress) -> String {
        address.stringForDisplay
    }

    func displayName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        address.stringForDisplay
    }

    func displayName(for signalAccount: SignalAccount) -> String {
        signalAccount.recipientAddress.stringForDisplay
    }

    func displayName(for thread: TSThread, transaction: SDSAnyReadTransaction) -> String {
        "Fake Name"
    }

    func displayNameWithSneakyTransaction(thread: TSThread) -> String {
        "Fake Name"
    }

    func shortDisplayName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        address.stringForDisplay
    }

    func conversationColorName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> ConversationColorName {
        ConversationColorName.taupe
    }

    func nameComponents(for address: SignalServiceAddress) -> PersonNameComponents? {
        PersonNameComponents()
    }

    func nameComponents(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> PersonNameComponents? {
        PersonNameComponents()
    }

    func signalAccounts() -> [SignalAccount] {
        []
    }

    func isSystemContact(phoneNumber: String) -> Bool {
        true
    }

    func isSystemContact(address: SignalServiceAddress) -> Bool {
        true
    }

    func isSystemContact(withSignalAccount phoneNumber: String) -> Bool {
        true
    }

    func isSystemContact(withSignalAccount phoneNumber: String, transaction: SDSAnyReadTransaction) -> Bool {
        true
    }

    func hasNameInSystemContacts(for address: SignalServiceAddress) -> Bool {
        false
    }

    func compare(signalAccount left: SignalAccount, with right: SignalAccount) -> ComparisonResult {
        .orderedSame
    }

    public func sortSignalServiceAddresses(_ addresses: [SignalServiceAddress],
                                           transaction: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        addresses
    }

    func cnContact(withId contactId: String?) -> CNContact? {
        nil
    }

    func avatarData(forCNContactId contactId: String?) -> Data? {
        nil
    }

    func avatarImage(forCNContactId contactId: String?) -> UIImage? {
        nil
    }

    var unknownUserLabel: String = "unknown"
}
