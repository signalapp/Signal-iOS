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
                tx: tx,
            )
        }
    }

    // MARK: - Message Creation

    func testProcessIncomingStoryMessage_createsPrivateStoryWithWhitelistedAuthor() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makePrivateStory()

        let profileManager = SSKEnvironment.shared.profileManagerRef as! OWSFakeProfileManager
        profileManager.fakeUserProfiles = [
            SignalServiceAddress(author): OWSUserProfile(address: .otherUser(SignalServiceAddress(author))),
        ]
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher

        try write {
            var recipient = recipientFetcher.fetchOrCreate(serviceId: author, tx: $0)
            profileManager.addRecipientToProfileWhitelist(&recipient, userProfileWriter: .localUser, tx: $0)

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0,
            )

            // Message should have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0,
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
                transaction: $0,
            )

            // Message should not have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0,
            )
            XCTAssertNil(message)
        }
    }

    func testProcessIncomingStoryMessage_dropsStoryWithBlockedAuthor() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let privateStoryMessage = try Self.makePrivateStory()
        let groupStoryMessage = try Self.makeGroupStory()

        let profileManager = SSKEnvironment.shared.profileManagerRef
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher

        try write {
            var recipient = recipientFetcher.fetchOrCreate(serviceId: author, tx: $0)
            profileManager.addRecipientToProfileWhitelist(&recipient, userProfileWriter: .localUser, tx: $0)

            SSKEnvironment.shared.blockingManagerRef.addBlockedAddress(
                SignalServiceAddress(author),
                blockMode: .localShouldNotLeaveGroups,
                transaction: $0,
            )

            try StoryManager.processIncomingStoryMessage(
                privateStoryMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0,
            )

            try StoryManager.processIncomingStoryMessage(
                groupStoryMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0,
            )

            // Message should not have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0,
            )
            XCTAssertNil(message)
        }
    }

    func testProcessIncomingStoryMessage_dropsStoryWithBlockedGroup() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makeGroupStory()

        let groupMasterKey = try GroupMasterKey(contents: storyMessage.group!.masterKey!)
        let groupId = try GroupSecretParams.deriveFromMasterKey(groupMasterKey: groupMasterKey).getPublicParams().getGroupIdentifier().serialize()

        let profileManager = SSKEnvironment.shared.profileManagerRef
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher

        try write {
            var recipient = recipientFetcher.fetchOrCreate(serviceId: author, tx: $0)
            profileManager.addRecipientToProfileWhitelist(&recipient, userProfileWriter: .localUser, tx: $0)

            TSGroupThread.forUnitTest(
                masterKey: groupMasterKey,
            ).anyInsert(transaction: $0)
            SSKEnvironment.shared.blockingManagerRef.addBlockedGroupId(
                groupId,
                blockMode: .localShouldNotLeaveGroups,
                transaction: $0,
            )

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0,
            )

            // Message should not have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0,
            )
            XCTAssertNil(message)
        }
    }

    func testProcessIncomingStoryMessage_dropsStoryWhenNotAGroupMember() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makeGroupStory()

        let secretParams = try GroupV2ContextInfo.deriveFrom(masterKeyData: storyMessage.group!.masterKey!).groupSecretParams

        let profileManager = SSKEnvironment.shared.profileManagerRef
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher

        try write {
            var recipient = recipientFetcher.fetchOrCreate(serviceId: author, tx: $0)
            profileManager.addRecipientToProfileWhitelist(&recipient, userProfileWriter: .localUser, tx: $0)

            try Self.makeGroupThread(secretParams: secretParams, transaction: $0)

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0,
            )

            // Message should not have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0,
            )
            XCTAssertNil(message)
        }
    }

    func testProcessIncomingStoryMessage_dropsAnnouncementStoryWhenNotAnAdmin() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makeGroupStory()

        let secretParams = try GroupV2ContextInfo.deriveFrom(masterKeyData: storyMessage.group!.masterKey!).groupSecretParams

        let profileManager = SSKEnvironment.shared.profileManagerRef
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher

        try write {
            var recipient = recipientFetcher.fetchOrCreate(serviceId: author, tx: $0)
            profileManager.addRecipientToProfileWhitelist(&recipient, userProfileWriter: .localUser, tx: $0)

            try Self.makeGroupThread(secretParams: secretParams, announcementOnly: true, members: [author], transaction: $0)

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0,
            )

            // Message should not have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0,
            )
            XCTAssertNil(message)
        }
    }

    func testProcessIncomingStoryMessage_createsAnnouncementStoryWhenAnAdmin() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makeGroupStory()

        let secretParams = try GroupV2ContextInfo.deriveFrom(masterKeyData: storyMessage.group!.masterKey!).groupSecretParams

        let profileManager = SSKEnvironment.shared.profileManagerRef as! OWSFakeProfileManager
        profileManager.fakeUserProfiles = [
            SignalServiceAddress(author): OWSUserProfile(address: .otherUser(SignalServiceAddress(author))),
        ]
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher

        try write {
            var recipient = recipientFetcher.fetchOrCreate(serviceId: author, tx: $0)
            profileManager.addRecipientToProfileWhitelist(&recipient, userProfileWriter: .localUser, tx: $0)

            try Self.makeGroupThread(secretParams: secretParams, announcementOnly: true, admins: [author], transaction: $0)

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0,
            )

            // Message should have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0,
            )
            XCTAssertNotNil(message)
        }
    }

    func testProcessIncomingStoryMessage_createsStoryWhenAValidGroupMember() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makeGroupStory()

        let secretParams = try GroupV2ContextInfo.deriveFrom(masterKeyData: storyMessage.group!.masterKey!).groupSecretParams

        let profileManager = SSKEnvironment.shared.profileManagerRef as! OWSFakeProfileManager
        profileManager.fakeUserProfiles = [
            SignalServiceAddress(author): OWSUserProfile(address: .otherUser(SignalServiceAddress(author))),
        ]
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher

        try write {
            var recipient = recipientFetcher.fetchOrCreate(serviceId: author, tx: $0)
            profileManager.addRecipientToProfileWhitelist(&recipient, userProfileWriter: .localUser, tx: $0)

            try Self.makeGroupThread(secretParams: secretParams, members: [author], transaction: $0)

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0,
            )

            // Message should have been created.
            let message = StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: $0,
            )
            XCTAssertNotNil(message)
        }
    }

    func testProcessIncomingStoryMessage_storeAuthorProfileKey() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makePrivateStory()

        let profileManager = SSKEnvironment.shared.profileManagerRef as! OWSFakeProfileManager
        profileManager.fakeUserProfiles = [
            SignalServiceAddress(author): OWSUserProfile(address: .otherUser(SignalServiceAddress(author))),
        ]
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher

        try write {
            var recipient = recipientFetcher.fetchOrCreate(serviceId: author, tx: $0)
            profileManager.addRecipientToProfileWhitelist(&recipient, userProfileWriter: .localUser, tx: $0)

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0,
            )

            let profileManager = SSKEnvironment.shared.profileManagerRef
            let profileKey = profileManager.userProfile(
                for: SignalServiceAddress(author),
                tx: $0,
            )?.profileKey
            XCTAssertEqual(profileKey?.keyData, storyMessage.profileKey)
        }
    }

    func testProcessIncomingStoryMessage_dropMessageThatAlreadyExists() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = Aci.randomForTesting()
        let storyMessage = try Self.makePrivateStory()

        let profileManager = SSKEnvironment.shared.profileManagerRef
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher

        try write {
            try StoryMessage.create(
                withIncomingStoryMessage: storyMessage,
                timestamp: timestamp,
                receivedTimestamp: timestamp,
                author: author,
                transaction: $0,
            )

            var recipient = recipientFetcher.fetchOrCreate(serviceId: author, tx: $0)
            profileManager.addRecipientToProfileWhitelist(&recipient, userProfileWriter: .localUser, tx: $0)

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                localIdentifiers: .forUnitTests,
                transaction: $0,
            )

            let count = try StoryMessage
                .filter(Column(StoryMessage.columnName(.timestamp)) == timestamp)
                .filter(Column(StoryMessage.columnName(.authorAci)) == author.serviceIdUppercaseString)
                .fetchCount($0.database)
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
        secretParams: GroupSecretParams,
        announcementOnly: Bool = false,
        members: [Aci] = [],
        admins: [Aci] = [],
        transaction: DBWriteTransaction,
    ) throws {
        var membershipBuilder = GroupMembership.Builder()

        for member in members {
            membershipBuilder.addFullMember(member, role: .normal)
        }

        for admin in admins {
            membershipBuilder.addFullMember(admin, role: .administrator)
        }

        var modelBuilder = TSGroupModelBuilder(secretParams: secretParams)
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
            tx: DBWriteTransaction,
        ) {
            // Do nothing
        }
    }
}
