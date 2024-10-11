//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

class StoryManagerTest: SSKBaseTest {

    override func setUp() {
        super.setUp()

        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx.asV2Write
            )
        }
    }

    // MARK: - Message Creation

    func testProcessIncomingStoryMessage_createsPrivateStoryWithWhitelistedAuthor() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makePrivateStory()

        try write {
            SSKEnvironment.shared.profileManagerRef.addUser(
                toProfileWhitelist: SignalServiceAddress(author),
                userProfileWriter: .localUser,
                transaction: $0
            )

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0
            )

            // Message should have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0
            )
            XCTAssertNotNil(message)
        }
    }

    func testProcessIncomingStoryMessage_dropsPrivateStoryWithUnwhitelistedAuthor() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makePrivateStory()

        try write {
            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0
            )

            // Message should not have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0
            )
            XCTAssertNil(message)
        }
    }

    func testProcessIncomingStoryMessage_dropsStoryWithBlockedAuthor() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let privateStoryMessage = try Self.makePrivateStory()
        let groupStoryMessage = try Self.makeGroupStory()

        try write {
            SSKEnvironment.shared.profileManagerRef.addUser(
                toProfileWhitelist: SignalServiceAddress(author),
                userProfileWriter: .localUser,
                transaction: $0
            )

            SSKEnvironment.shared.blockingManagerRef.addBlockedAddress(
                SignalServiceAddress(author),
                blockMode: .localShouldNotLeaveGroups,
                transaction: $0
            )

            try StoryManager.processIncomingStoryMessage(
                privateStoryMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0
            )

            try StoryManager.processIncomingStoryMessage(
                groupStoryMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0
            )

            // Message should not have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0
            )
            XCTAssertNil(message)
        }
    }

    func testProcessIncomingStoryMessage_dropsStoryWithBlockedGroup() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makeGroupStory()

        let groupId = try GroupV2ContextInfo.deriveFrom(masterKeyData: storyMessage.group!.masterKey!).groupId

        try write {
            SSKEnvironment.shared.profileManagerRef.addUser(
                toProfileWhitelist: SignalServiceAddress(author),
                userProfileWriter: .localUser,
                transaction: $0
            )

            SSKEnvironment.shared.blockingManagerRef.addBlockedGroup(
                groupId: groupId,
                blockMode: .localShouldNotLeaveGroups,
                transaction: $0
            )

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0
            )

            // Message should not have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0
            )
            XCTAssertNil(message)
        }
    }

    func testProcessIncomingStoryMessage_dropsStoryWhenNotAGroupMember() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makeGroupStory()

        let groupId = try GroupV2ContextInfo.deriveFrom(masterKeyData: storyMessage.group!.masterKey!).groupId

        try write {
            SSKEnvironment.shared.profileManagerRef.addUser(
                toProfileWhitelist: SignalServiceAddress(author),
                userProfileWriter: .localUser,
                transaction: $0
            )

            try Self.makeGroupThread(groupId: groupId, transaction: $0)

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0
            )

            // Message should not have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0
            )
            XCTAssertNil(message)
        }
    }

    func testProcessIncomingStoryMessage_dropsAnnouncementStoryWhenNotAnAdmin() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makeGroupStory()

        let groupId = try GroupV2ContextInfo.deriveFrom(masterKeyData: storyMessage.group!.masterKey!).groupId

        try write {
            SSKEnvironment.shared.profileManagerRef.addUser(
                toProfileWhitelist: SignalServiceAddress(author),
                userProfileWriter: .localUser,
                transaction: $0
            )

            try Self.makeGroupThread(groupId: groupId, announcementOnly: true, members: [author], transaction: $0)

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0
            )

            // Message should not have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0
            )
            XCTAssertNil(message)
        }
    }

    func testProcessIncomingStoryMessage_createsAnnouncementStoryWhenAnAdmin() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makeGroupStory()

        let groupId = try GroupV2ContextInfo.deriveFrom(masterKeyData: storyMessage.group!.masterKey!).groupId

        try write {
            SSKEnvironment.shared.profileManagerRef.addUser(
                toProfileWhitelist: SignalServiceAddress(author),
                userProfileWriter: .localUser,
                transaction: $0
            )

            try Self.makeGroupThread(groupId: groupId, announcementOnly: true, admins: [author], transaction: $0)

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0
            )

            // Message should have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0
            )
            XCTAssertNotNil(message)
        }
    }

    func testProcessIncomingStoryMessage_createsStoryWhenAValidGroupMember() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makeGroupStory()

        let groupId = try GroupV2ContextInfo.deriveFrom(masterKeyData: storyMessage.group!.masterKey!).groupId

        try write {
            SSKEnvironment.shared.profileManagerRef.addUser(
                toProfileWhitelist: SignalServiceAddress(author),
                userProfileWriter: .localUser,
                transaction: $0
            )

            try Self.makeGroupThread(groupId: groupId, members: [author], transaction: $0)

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0
            )

            // Message should have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0
            )
            XCTAssertNotNil(message)
        }
    }

    func testProcessIncomingStoryMessage_storeAuthorProfileKey() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makePrivateStory()

        try write {
            SSKEnvironment.shared.profileManagerRef.addUser(
                toProfileWhitelist: SignalServiceAddress(author),
                userProfileWriter: .localUser,
                transaction: $0
            )

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0
            )

            let profileKey = SSKEnvironment.shared.profileManagerRef.profileKeyData(
                for: SignalServiceAddress(author),
                transaction: $0
            )
            XCTAssertEqual(profileKey, storyMessage.profileKey)
        }
    }

    func testProcessIncomingStoryMessage_dropMessageThatAlreadyExists() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makePrivateStory()

        try write {
            try StoryMessage.create(
                withIncomingStoryMessage: storyMessage,
                timestamp: timestamp,
                receivedTimestamp: timestamp,
                author: author,
                transaction: $0
            )

            SSKEnvironment.shared.profileManagerRef.addUser(
                toProfileWhitelist: SignalServiceAddress(author),
                userProfileWriter: .localUser,
                transaction: $0
            )

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0
            )

            let count = try StoryMessage
                .filter(Column(StoryMessage.columnName(.timestamp)) == timestamp)
                .filter(Column(StoryMessage.columnName(.authorAci)) == author.serviceIdUppercaseString)
                .fetchCount($0.unwrapGrdbRead.database)
            XCTAssertEqual(count, 1)
        }
    }

    // MARK: - Helpers

    static func makePrivateStory() throws -> SSKProtoStoryMessage {
        let storyMessageBuilder = SSKProtoStoryMessage.builder()
        storyMessageBuilder.setFileAttachment(makeImageAttachment())
        storyMessageBuilder.setProfileKey(Randomness.generateRandomBytes(32))
        return try storyMessageBuilder.build()
    }

    static func makeImageAttachment() -> SSKProtoAttachmentPointer {
        let builder = SSKProtoAttachmentPointer.builder()
        builder.setCdnID(1)
        builder.setCdnNumber(3)
        builder.setCdnKey("someCdnKey")
        builder.setDigest(Randomness.generateRandomBytes(32))
        builder.setKey(Randomness.generateRandomBytes(32))
        builder.setContentType(MimeType.imageJpeg.rawValue)
        return builder.buildInfallibly()
    }

    static func makeGroupStory() throws -> SSKProtoStoryMessage {
        let storyMessageBuilder = SSKProtoStoryMessage.builder()
        storyMessageBuilder.setFileAttachment(makeImageAttachment())
        storyMessageBuilder.setProfileKey(Randomness.generateRandomBytes(32))

        let groupContext = makeGroupContext()

        storyMessageBuilder.setGroup(groupContext)

        return try storyMessageBuilder.build()
    }

    static func makeGroupThread(
        groupId: Data,
        announcementOnly: Bool = false,
        members: [Aci] = [],
        admins: [Aci] = [],
        transaction: SDSAnyWriteTransaction
    ) throws {
        var membershipBuilder = GroupMembership.Builder()

        for member in members {
            membershipBuilder.addFullMember(member, role: .normal)
        }

        for admin in admins {
            membershipBuilder.addFullMember(admin, role: .administrator)
        }

        var modelBuilder = TSGroupModelBuilder()
        modelBuilder.groupId = groupId
        modelBuilder.groupMembership = membershipBuilder.build()
        modelBuilder.isAnnouncementsOnly = announcementOnly
        let groupModel = try modelBuilder.buildAsV2()

        let thread = TSGroupThread(groupModel: groupModel)
        thread.anyInsert(transaction: transaction)
    }

    static func makeGroupContext() -> SSKProtoGroupContextV2 {
        let builder = SSKProtoGroupContextV2.builder()
        builder.setMasterKey(Data(repeating: 0, count: 32))
        builder.setRevision(1)
        return builder.buildInfallibly()
    }

    static func makeGroupContextInfo(for context: SSKProtoGroupContextV2) throws -> GroupV2ContextInfo {
        return try GroupV2ContextInfo.deriveFrom(masterKeyData: context.masterKey!)
    }

    // MARK: - Overrides

    class StoryManager: SignalServiceKit.StoryManager {

        override static func enqueueDownloadOfAttachmentsForStoryMessage(
            _ message: StoryMessage,
            tx: any DBWriteTransaction
        ) {
            // Do nothing
        }
    }
}
