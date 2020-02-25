//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public enum GroupsV2Error: Error {
    // By the time we tried to apply the change, it was irrelevant.
    //
    // GroupsV2 TODO: We must handle this.  Not try to retry.
    case redundantChange
    // GroupsV2 TODO: We must handle this.  We've probably been removed from the group.
    case unauthorized
    case shouldRetry
    case shouldDiscard
    case groupNotInDatabase
    case timeout
}

@objc
public protocol GroupsV2: AnyObject {

    func createNewGroupOnServiceObjc(groupModel: TSGroupModel) -> AnyPromise

    func generateGroupSecretParamsData() throws -> Data

    func groupId(forGroupSecretParamsData groupSecretParamsData: Data) throws -> Data

    func hasProfileKeyCredential(for address: SignalServiceAddress,
                                 transaction: SDSAnyReadTransaction) -> Bool

    func tryToEnsureProfileKeyCredentialsObjc(for addresses: [SignalServiceAddress]) -> AnyPromise

    func buildGroupContextV2Proto(groupModel: TSGroupModel,
                                  changeActionsProtoData: Data?) throws -> SSKProtoGroupContextV2

    func groupV2ContextInfo(forMasterKeyData masterKeyData: Data?) throws -> GroupV2ContextInfo

    func parseAndVerifyChangeActionsProto(_ changeProtoData: Data,
                                          ignoreSignature: Bool) throws -> GroupsProtoGroupChangeActions

    func scheduleAllGroupsV2ForProfileKeyUpdate(transaction: SDSAnyWriteTransaction)

    func processProfileKeyUpdates()

    func updateLocalProfileKeyInGroup(groupId: Data, transaction: SDSAnyWriteTransaction)
}

// MARK: -

public protocol GroupsV2Swift: GroupsV2 {
    func createNewGroupOnService(groupModel: TSGroupModel) -> Promise<Void>

    func tryToEnsureProfileKeyCredentials(for addresses: [SignalServiceAddress]) -> Promise<Void>

    func tryToEnsureUuidsForGroupMembers(for addresses: [SignalServiceAddress]) -> Promise<Void>

    func fetchCurrentGroupV2Snapshot(groupModel: TSGroupModel) -> Promise<GroupV2Snapshot>

    func fetchCurrentGroupV2Snapshot(groupSecretParamsData: Data) -> Promise<GroupV2Snapshot>

    func fetchGroupChangeActions(groupSecretParamsData: Data,
                                 firstKnownRevision: UInt32?) -> Promise<[GroupV2Change]>

    func buildChangeSet(oldGroupModel: TSGroupModel,
                        newGroupModel: TSGroupModel,
                        oldDMConfiguration: OWSDisappearingMessagesConfiguration,
                        newDMConfiguration: OWSDisappearingMessagesConfiguration,
                        transaction: SDSAnyReadTransaction) throws -> GroupsV2ChangeSet

    // On success returns a group thread model that reflects the
    // latest state in the service, which (due to races) might
    // reflect changes after the change set.
    func updateExistingGroupOnService(changeSet: GroupsV2ChangeSet) -> Promise<TSGroupThread>

    func acceptInviteToGroupV2(groupThread: TSGroupThread) -> Promise<TSGroupThread>

    func leaveGroupV2OrDeclineInvite(groupThread: TSGroupThread) -> Promise<TSGroupThread>

    func updateDisappearingMessageStateOnService(groupThread: TSGroupThread,
                                                 disappearingMessageToken: DisappearingMessageToken) -> Promise<TSGroupThread>

    func reuploadLocalProfilePromise() -> Promise<Void>

    func updateGroupWithChangeActions(groupId: Data,
                                      changeActionsProto: GroupsProtoGroupChangeActions,
                                      ignoreSignature: Bool,
                                      groupSecretParamsData: Data) throws -> Promise<TSGroupThread>

     func uploadGroupAvatar(avatarData: Data, groupSecretParamsData: Data) -> Promise<String>
}

// MARK: -

public protocol GroupsV2ChangeSet: AnyObject {
    var groupId: Data { get }
    var groupSecretParamsData: Data { get }

    var newAvatarData: Data? { get }
    var newAvatarUrlPath: String? { get }

    func buildGroupChangeProto(currentGroupModel: TSGroupModel,
                               currentDisappearingMessageToken: DisappearingMessageToken) -> Promise<GroupsProtoGroupChangeActions>
}

// MARK: -

public enum GroupUpdateMode {
    // * Group update should halt at a specific revision.
    // * Group update _should not_ block on message processing.
    // * Group update _should not_ be throttled.
    //
    // upToRevision is inclusive.
    case upToSpecificRevisionImmediately(upToRevision: UInt32)
    // * Group update should continue until current revision.
    // * Group update _should_ block on message processing.
    // * Group update _should_ be throttled.
    case upToCurrentRevisionAfterMessageProcessWithThrottling
}

// MARK: -

@objc
public protocol GroupV2Updates: AnyObject {

    func tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithThrottling(_ groupThread: TSGroupThread)

    func tryToRefreshV2GroupUpToSpecificRevisionImmediately(_ groupThread: TSGroupThread,
                                                            upToRevision: UInt32)
}

// MARK: -

public protocol GroupV2UpdatesSwift: GroupV2Updates {
    func tryToRefreshV2GroupThreadWithThrottling(groupId: Data,
                                                 groupSecretParamsData: Data,
                                                 groupUpdateMode: GroupUpdateMode) -> Promise<Void>

    func updateGroupWithChangeActions(groupId: Data,
                                      changeActionsProto: GroupsProtoGroupChangeActions,
                                      downloadedAvatars: GroupV2DownloadedAvatars,
                                      transaction: SDSAnyWriteTransaction) throws -> TSGroupThread
}

// MARK: -

// GroupsV2 TODO: Can we eventually remove this and just use TSGroupModel?
public protocol GroupV2Snapshot {
    var groupSecretParamsData: Data { get }

    var debugDescription: String { get }

    var revision: UInt32 { get }

    var title: String { get }

    var avatarUrlPath: String? { get }
    var avatarData: Data? { get }

    var groupMembership: GroupMembership { get }

    var groupAccess: GroupAccess { get }

    var accessControlForAttributes: GroupsProtoAccessControlAccessRequired { get }
    var accessControlForMembers: GroupsProtoAccessControlAccessRequired { get }

    var disappearingMessageToken: DisappearingMessageToken { get }

    var profileKeys: [UUID: Data] { get }
}

// MARK: -

public struct GroupV2Change {
    public let snapshot: GroupV2Snapshot
    public let changeActionsProto: GroupsProtoGroupChangeActions

    public init(snapshot: GroupV2Snapshot,
                changeActionsProto: GroupsProtoGroupChangeActions) {
        self.snapshot = snapshot
        self.changeActionsProto = changeActionsProto
    }
}

// MARK: -

@objc
public class GroupV2ContextInfo: NSObject {
    @objc
    public let masterKeyData: Data
    @objc
    public let groupSecretParamsData: Data
    @objc
    public let groupId: Data

    public init(masterKeyData: Data, groupSecretParamsData: Data, groupId: Data) {
        self.masterKeyData = masterKeyData
        self.groupSecretParamsData = groupSecretParamsData
        self.groupId = groupId
    }
}

// MARK: -

public struct GroupV2DownloadedAvatars {
    // A map of avatar url-to-avatar data.
    private var avatarMap = [String: Data]()

    public init() {}

    public mutating func set(avatarData: Data, avatarUrlPath: String) {
        avatarMap[avatarUrlPath] = avatarData
    }

    public mutating func merge(_ other: GroupV2DownloadedAvatars) {
        for (avatarUrlPath, avatarData) in other.avatarMap {
            avatarMap[avatarUrlPath] = avatarData
        }
    }

    public func hasAvatarData(for avatarUrlPath: String) -> Bool {
        return avatarMap[avatarUrlPath] != nil
    }

    public func avatarData(for avatarUrlPath: String) throws -> Data {
        guard let avatarData = avatarMap[avatarUrlPath] else {
            throw OWSAssertionError("Missing avatarData.")
        }
        return avatarData
    }

    public var avatarUrlPaths: [String] {
        return Array(avatarMap.keys)
    }

    public static var empty: GroupV2DownloadedAvatars {
        return GroupV2DownloadedAvatars()
    }

    public static func from(groupModel: TSGroupModelV2) -> GroupV2DownloadedAvatars {
        return from(avatarData: groupModel.groupAvatarData, avatarUrlPath: groupModel.groupAvatarUrlPath)
    }

    public static func from(changeSet: GroupsV2ChangeSet) -> GroupV2DownloadedAvatars {
        return from(avatarData: changeSet.newAvatarData, avatarUrlPath: changeSet.newAvatarUrlPath)
    }

    private static func from(avatarData: Data?, avatarUrlPath: String?) -> GroupV2DownloadedAvatars {
        let hasAvatarData = avatarData != nil
        let hasAvatarUrlPath = avatarUrlPath != nil
        guard hasAvatarData == hasAvatarUrlPath else {
            // Fail but continue in production; we can recover from this scenario.
            owsFailDebug("hasAvatarData: \(hasAvatarData) != hasAvatarUrlPath: \(hasAvatarUrlPath)")
            return .empty
        }
        guard let avatarData = avatarData,
            let avatarUrlPath = avatarUrlPath else {
                // No avatar.
                return .empty
        }
        // Avatar found, add it to the result set.
        var downloadedAvatars = GroupV2DownloadedAvatars()
        downloadedAvatars.set(avatarData: avatarData, avatarUrlPath: avatarUrlPath)
        return downloadedAvatars
    }
}

// MARK: -

public class MockGroupsV2: NSObject, GroupsV2Swift {

    public func createNewGroupOnService(groupModel: TSGroupModel) -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public func createNewGroupOnServiceObjc(groupModel: TSGroupModel) -> AnyPromise {
        owsFail("Not implemented.")
    }

    public func generateGroupSecretParamsData() throws -> Data {
        owsFail("Not implemented.")
    }

    public func groupId(forGroupSecretParamsData groupSecretParamsData: Data) throws -> Data {
        owsFail("Not implemented.")
    }

    public func hasProfileKeyCredential(for address: SignalServiceAddress,
                                        transaction: SDSAnyReadTransaction) -> Bool {
        owsFail("Not implemented.")
    }

    public func tryToEnsureProfileKeyCredentialsObjc(for addresses: [SignalServiceAddress]) -> AnyPromise {
        owsFail("Not implemented.")
    }

    public func tryToEnsureProfileKeyCredentials(for addresses: [SignalServiceAddress]) -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public func tryToEnsureUuidsForGroupMembers(for addresses: [SignalServiceAddress]) -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public func fetchCurrentGroupV2Snapshot(groupModel: TSGroupModel) -> Promise<GroupV2Snapshot> {
        owsFail("Not implemented.")
    }

    public func fetchCurrentGroupV2Snapshot(groupSecretParamsData: Data) -> Promise<GroupV2Snapshot> {
        owsFail("Not implemented.")
    }

    public func fetchGroupChangeActions(groupSecretParamsData: Data,
                                        firstKnownRevision: UInt32?) -> Promise<[GroupV2Change]> {
        owsFail("Not implemented.")
    }

    public func buildGroupContextV2Proto(groupModel: TSGroupModel,
                                         changeActionsProtoData: Data?) throws -> SSKProtoGroupContextV2 {
        owsFail("Not implemented.")
    }

    public func buildChangeSet(oldGroupModel: TSGroupModel,
                               newGroupModel: TSGroupModel,
                               oldDMConfiguration: OWSDisappearingMessagesConfiguration,
                               newDMConfiguration: OWSDisappearingMessagesConfiguration,
                               transaction: SDSAnyReadTransaction) throws -> GroupsV2ChangeSet {
        owsFail("Not implemented.")
    }

    public func updateExistingGroupOnService(changeSet: GroupsV2ChangeSet) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func acceptInviteToGroupV2(groupThread: TSGroupThread) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func leaveGroupV2OrDeclineInvite(groupThread: TSGroupThread) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func updateDisappearingMessageStateOnService(groupThread: TSGroupThread,
                                                        disappearingMessageToken: DisappearingMessageToken) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func reuploadLocalProfilePromise() -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public func groupV2ContextInfo(forMasterKeyData masterKeyData: Data?) throws -> GroupV2ContextInfo {
        owsFail("Not implemented.")
    }

    public func parseAndVerifyChangeActionsProto(_ changeProtoData: Data,
                                                 ignoreSignature: Bool) throws -> GroupsProtoGroupChangeActions {
        owsFail("Not implemented.")
    }

    public func scheduleAllGroupsV2ForProfileKeyUpdate(transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func processProfileKeyUpdates() {
        owsFail("Not implemented.")
    }

    public func updateLocalProfileKeyInGroup(groupId: Data, transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func updateGroupWithChangeActions(groupId: Data,
                                             changeActionsProto: GroupsProtoGroupChangeActions,
                                             ignoreSignature: Bool,
                                             groupSecretParamsData: Data) throws -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func uploadGroupAvatar(avatarData: Data,
                                  groupSecretParamsData: Data) -> Promise<String> {
        owsFail("Not implemented.")
    }
}

// MARK: -

public class MockGroupV2Updates: NSObject, GroupV2UpdatesSwift {
    @objc
    public func tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithThrottling(_ groupThread: TSGroupThread) {
        owsFail("Not implemented.")
    }

    @objc
    public func tryToRefreshV2GroupUpToSpecificRevisionImmediately(_ groupThread: TSGroupThread,
                                                                   upToRevision: UInt32) {
        owsFail("Not implemented.")
    }

    public func tryToRefreshV2GroupThreadWithThrottling(groupId: Data,
                                                        groupSecretParamsData: Data,
                                                        groupUpdateMode: GroupUpdateMode) -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public func updateGroupWithChangeActions(groupId: Data,
                                             changeActionsProto: GroupsProtoGroupChangeActions,
                                             downloadedAvatars: GroupV2DownloadedAvatars,
                                             transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {
        owsFail("Not implemented.")
    }
}
