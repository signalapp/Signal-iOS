//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import GRDB

@testable import SignalServiceKit

class StoryManagerTest: SSKBaseTestSwift {

    // MARK: - Message Creation

    func testProcessIncomingStoryMessage_createsPrivateStoryWithWhitelistedAuthor() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = SignalServiceAddress(uuid: UUID())
        let storyMessage = try Self.makePrivateStory(author: author)

        try write {
            profileManager.addUser(
                toProfileWhitelist: author,
                userProfileWriter: .localUser,
                transaction: $0
            )

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
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

        let author = SignalServiceAddress(uuid: UUID())
        let storyMessage = try Self.makePrivateStory(author: author)

        try write {
            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
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

        let author = SignalServiceAddress(uuid: UUID())
        let privateStoryMessage = try Self.makePrivateStory(author: author)
        let groupStoryMessage = try Self.makeGroupStory(author: author)

        try write {
            profileManager.addUser(
                toProfileWhitelist: author,
                userProfileWriter: .localUser,
                transaction: $0
            )

            blockingManager.addBlockedAddress(
                author,
                blockMode: .localShouldNotLeaveGroups,
                transaction: $0
            )

            try StoryManager.processIncomingStoryMessage(
                privateStoryMessage,
                timestamp: timestamp,
                author: author,
                transaction: $0
            )

            try StoryManager.processIncomingStoryMessage(
                groupStoryMessage,
                timestamp: timestamp,
                author: author,
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

        let author = SignalServiceAddress(uuid: UUID())
        let storyMessage = try Self.makeGroupStory(author: author)

        let groupId = try groupsV2.groupV2ContextInfo(forMasterKeyData: storyMessage.group!.masterKey!).groupId

        try write {
            profileManager.addUser(
                toProfileWhitelist: author,
                userProfileWriter: .localUser,
                transaction: $0
            )

            blockingManager.addBlockedGroup(
                groupId: groupId,
                blockMode: .localShouldNotLeaveGroups,
                transaction: $0
            )

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
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

        let author = SignalServiceAddress(uuid: UUID())
        let storyMessage = try Self.makeGroupStory(author: author)

        let groupId = try groupsV2.groupV2ContextInfo(forMasterKeyData: storyMessage.group!.masterKey!).groupId

        try write {
            profileManager.addUser(
                toProfileWhitelist: author,
                userProfileWriter: .localUser,
                transaction: $0
            )

            try Self.makeGroupThread(groupId: groupId, transaction: $0)

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
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

    func testProcessIncomingStoryMessage_createsStoryWhenAValidGroupMember() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = SignalServiceAddress(uuid: UUID())
        let storyMessage = try Self.makeGroupStory(author: author)

        let groupId = try groupsV2.groupV2ContextInfo(forMasterKeyData: storyMessage.group!.masterKey!).groupId

        try write {
            profileManager.addUser(
                toProfileWhitelist: author,
                userProfileWriter: .localUser,
                transaction: $0
            )

            try Self.makeGroupThread(groupId: groupId, members: [author], transaction: $0)

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
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

        let author = SignalServiceAddress(uuid: UUID())
        let storyMessage = try Self.makePrivateStory(author: author)

        try write {
            profileManager.addUser(
                toProfileWhitelist: author,
                userProfileWriter: .localUser,
                transaction: $0
            )

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                transaction: $0
            )

            let profileKey = profileManager.profileKeyData(
                for: author,
                transaction: $0
            )
            XCTAssertEqual(profileKey, storyMessage.profileKey)
        }
    }

    func testProcessIncomingStoryMessage_dropMessageThatAlreadyExists() throws {
        let timestamp = Date().ows_millisecondsSince1970

        let author = SignalServiceAddress(uuid: UUID())
        let storyMessage = try Self.makePrivateStory(author: author)

        try write {
            try StoryMessage.create(
                withIncomingStoryMessage: storyMessage,
                timestamp: timestamp,
                receivedTimestamp: timestamp,
                author: author,
                transaction: $0
            )

            profileManager.addUser(
                toProfileWhitelist: author,
                userProfileWriter: .localUser,
                transaction: $0
            )

            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: timestamp,
                author: author,
                transaction: $0
            )

            let count = try StoryMessage
                .filter(Column(StoryMessage.columnName(.timestamp)) == timestamp)
                .filter(Column(StoryMessage.columnName(.authorUuid)) == author.uuid!.uuidString)
                .fetchCount($0.unwrapGrdbRead.database)
            XCTAssertEqual(count, 1)
        }
    }

    // MARK: - Helpers

    static func makePrivateStory(author: SignalServiceAddress) throws -> SSKProtoStoryMessage {
        let storyMessageBuilder = SSKProtoStoryMessage.builder()
        storyMessageBuilder.setFileAttachment(try makeImageAttachment())
        storyMessageBuilder.setProfileKey(Randomness.generateRandomBytes(32))
        return try storyMessageBuilder.build()
    }

    static func makeImageAttachment() throws -> SSKProtoAttachmentPointer {
        let builder = SSKProtoAttachmentPointer.builder()
        builder.setCdnID(1)
        builder.setKey(Randomness.generateRandomBytes(32))
        builder.setContentType(OWSMimeTypeImageJpeg)
        return try builder.build()
    }

    static func makeGroupStory(author: SignalServiceAddress) throws -> SSKProtoStoryMessage {
        let storyMessageBuilder = SSKProtoStoryMessage.builder()
        storyMessageBuilder.setFileAttachment(try makeImageAttachment())
        storyMessageBuilder.setProfileKey(Randomness.generateRandomBytes(32))

        let groupContext = try makeGroupContext()
        let groupInfo = try makeGroupContextInfo(for: groupContext)
        (groupsV2 as! MockGroupsV2).groupV2ContextInfos[groupContext.masterKey!] = groupInfo

        storyMessageBuilder.setGroup(groupContext)

        return try storyMessageBuilder.build()
    }

    static func makeGroupThread(groupId: Data, members: [SignalServiceAddress] = [], transaction: SDSAnyWriteTransaction) throws {
        var membershipBuilder = GroupMembership.Builder()
        for member in members {
            membershipBuilder.addFullMember(member, role: .normal)
        }

        var modelBuilder = TSGroupModelBuilder()
        modelBuilder.groupId = groupId
        modelBuilder.groupMembership = membershipBuilder.build()
        let groupModel = try modelBuilder.build()

        let thread = TSGroupThread(groupModelPrivate: groupModel, transaction: transaction)
        thread.anyInsert(transaction: transaction)
    }

    static func makeGroupContext() throws -> SSKProtoGroupContextV2 {
        let builder = SSKProtoGroupContextV2.builder()
        builder.setMasterKey(Data())
        builder.setRevision(1)
        return try builder.build()
    }

    static func makeGroupContextInfo(for context: SSKProtoGroupContextV2) throws -> GroupV2ContextInfo {
        let bytes: [UInt8] = .init(repeating: 1, count: Int(kGroupIdLengthV2))
        return GroupV2ContextInfo(
            masterKeyData: context.masterKey!,
            groupSecretParamsData: Data(),
            groupId: Data(bytes)
        )
    }
}
