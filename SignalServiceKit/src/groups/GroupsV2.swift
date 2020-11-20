//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public enum GroupsV2Error: Error {
    // By the time we tried to apply the change, it was irrelevant.
    case redundantChange
    case unauthorized
    case shouldRetry
    case shouldDiscard
    case groupNotInDatabase
    case timeout
    case localUserNotInGroup
    case conflictingChange
    case lastAdminCantLeaveGroup
    case tooManyMembers
    case gv2NotEnabled
    case localUserIsAlreadyRequestingMember
    case localUserIsNotARequestingMember
    case requestingMemberCantLoadGroupState
    case cantApplyChangesToPlaceholder
    case expiredGroupInviteLink
    case groupDoesNotExistOnService
    case groupNeedsToBeMigrated
    case groupCannotBeMigrated
    case groupDowngradeNotAllowed
}

// MARK: -

@objc
public enum GroupsV2LinkMode: UInt, CustomStringConvertible {
    case disabled
    case enabledWithoutApproval
    case enabledWithApproval

    public var description: String {
        switch self {
        case .disabled:
            return ".disabled"
        case .enabledWithoutApproval:
            return ".enabledWithoutApproval"
        case .enabledWithApproval:
            return ".enabledWithApproval"
        }
    }
}

// MARK: -

@objc
public protocol GroupsV2: AnyObject {

    func generateGroupSecretParamsData() throws -> Data

    func groupId(forGroupSecretParamsData groupSecretParamsData: Data) throws -> Data

    func v2GroupId(forV1GroupId v1GroupId: Data) -> Data?

    func hasProfileKeyCredential(for address: SignalServiceAddress,
                                 transaction: SDSAnyReadTransaction) -> Bool

    func tryToEnsureProfileKeyCredentialsObjc(for addresses: [SignalServiceAddress]) -> AnyPromise

    func masterKeyData(forGroupModel groupModel: TSGroupModelV2) throws -> Data

    func buildGroupContextV2Proto(groupModel: TSGroupModelV2,
                                  changeActionsProtoData: Data?) throws -> SSKProtoGroupContextV2

    func groupV2ContextInfo(forMasterKeyData masterKeyData: Data?) throws -> GroupV2ContextInfo

    func scheduleAllGroupsV2ForProfileKeyUpdate(transaction: SDSAnyWriteTransaction)

    func processProfileKeyUpdates()

    func updateLocalProfileKeyInGroup(groupId: Data, transaction: SDSAnyWriteTransaction)

    func isGroupKnownToStorageService(groupModel: TSGroupModelV2,
                                      transaction: SDSAnyReadTransaction) -> Bool

    func restoreGroupFromStorageServiceIfNecessary(masterKeyData: Data, transaction: SDSAnyWriteTransaction)

    func isValidGroupV2MasterKey(_ masterKeyData: Data) -> Bool
}

// MARK: -

public protocol GroupsV2Swift: GroupsV2 {
    func createNewGroupOnService(groupModel: TSGroupModelV2,
                                 disappearingMessageToken: DisappearingMessageToken) -> Promise<Void>

    func tryToEnsureProfileKeyCredentials(for addresses: [SignalServiceAddress]) -> Promise<Void>

    func fetchCurrentGroupV2Snapshot(groupModel: TSGroupModelV2) -> Promise<GroupV2Snapshot>

    func fetchCurrentGroupV2Snapshot(groupSecretParamsData: Data) -> Promise<GroupV2Snapshot>

    func fetchGroupChangeActions(groupSecretParamsData: Data,
                                 includeCurrentRevision: Bool,
                                 firstKnownRevision: UInt32?) -> Promise<[GroupV2Change]>

    func buildChangeSet(oldGroupModel: TSGroupModelV2,
                        newGroupModel: TSGroupModelV2,
                        oldDMConfiguration: OWSDisappearingMessagesConfiguration,
                        newDMConfiguration: OWSDisappearingMessagesConfiguration,
                        transaction: SDSAnyReadTransaction) throws -> GroupsV2ChangeSet

    // On success returns a group thread model that reflects the
    // latest state in the service, which (due to races) might
    // reflect changes after the change set.
    func updateExistingGroupOnService(changeSet: GroupsV2ChangeSet) -> Promise<TSGroupThread>

    func updateGroupV2(groupModel: TSGroupModelV2,
                       changeSetBlock: @escaping (GroupsV2ChangeSet) -> Void) -> Promise<TSGroupThread>

    func reuploadLocalProfilePromise() -> Promise<Void>

    func parseAndVerifyChangeActionsProto(_ changeProtoData: Data,
                                          ignoreSignature: Bool) throws -> GroupsProtoGroupChangeActions

    func updateGroupWithChangeActions(groupId: Data,
                                      changeActionsProto: GroupsProtoGroupChangeActions,
                                      ignoreSignature: Bool,
                                      groupSecretParamsData: Data) throws -> Promise<TSGroupThread>

    func uploadGroupAvatar(avatarData: Data, groupSecretParamsData: Data) -> Promise<String>

    func groupInviteLink(forGroupModelV2 groupModelV2: TSGroupModelV2) throws -> URL

    func isPossibleGroupInviteLink(_ url: URL) -> Bool

    func parseGroupInviteLink(_ url: URL) -> GroupInviteLinkInfo?

    func cachedGroupInviteLinkPreview(groupSecretParamsData: Data) -> GroupInviteLinkPreview?

    // inviteLinkPassword is not necessary if we're already a member or have a pending request.
    func fetchGroupInviteLinkPreview(inviteLinkPassword: Data?,
                                     groupSecretParamsData: Data,
                                     allowCached: Bool) -> Promise<GroupInviteLinkPreview>

    func fetchGroupInviteLinkAvatar(avatarUrlPath: String,
                                    groupSecretParamsData: Data) -> Promise<Data>

    func joinGroupViaInviteLink(groupId: Data,
                                groupSecretParamsData: Data,
                                inviteLinkPassword: Data,
                                groupInviteLinkPreview: GroupInviteLinkPreview,
                                avatarData: Data?) -> Promise<TSGroupThread>

    func cancelMemberRequests(groupModel: TSGroupModelV2) -> Promise<TSGroupThread>

    func tryToUpdatePlaceholderGroupModelUsingInviteLinkPreview(groupModel: TSGroupModelV2)

    func fetchGroupExternalCredentials(groupModel: TSGroupModelV2) throws -> Promise<GroupsProtoGroupExternalCredential>

    func updateAlreadyMigratedGroupIfNecessary(v2GroupId: Data) -> Promise<Void>
}

// MARK: -

// TODO: Rename to GroupsV2ProposedChanges
public protocol GroupsV2ChangeSet: AnyObject {
    var groupId: Data { get }
    var groupSecretParamsData: Data { get }

    var newAvatarData: Data? { get }
    var newAvatarUrlPath: String? { get }

    func addMember(_ uuid: UUID, role: TSGroupMemberRole)

    func removeMember(_ uuid: UUID)

    func revokeInvalidInvites()

    func changeRoleForMember(_ uuid: UUID, role: TSGroupMemberRole)

    func setAccessForMembers(_ value: GroupV2Access)

    func setAccessForAttributes(_ value: GroupV2Access)

    func promoteInvitedMember(_ uuid: UUID)

    func setShouldLeaveGroupDeclineInvite()

    func setNewDisappearingMessageToken(_ newDisappearingMessageToken: DisappearingMessageToken)

    func setLinkMode(_ linkMode: GroupsV2LinkMode)

    func rotateInviteLinkPassword()

    func buildGroupChangeProto(currentGroupModel: TSGroupModelV2,
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
    // * Group update should continue until current revision.
    // * Group update _should not_ block on message processing.
    // * Group update _should not_ be throttled.
    case upToCurrentRevisionImmediately

    public var shouldBlockOnMessageProcessing: Bool {
        switch self {
        case .upToCurrentRevisionAfterMessageProcessWithThrottling:
            return true
        default:
            return false
        }
    }

    public var shouldThrottle: Bool {
        switch self {
        case .upToCurrentRevisionAfterMessageProcessWithThrottling:
            return true
        default:
            return false
        }
    }

    public var upToRevision: UInt32? {
        switch self {
        case .upToSpecificRevisionImmediately(let upToRevision):
            return upToRevision
        default:
            return nil
        }
    }
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
    func tryToRefreshV2GroupUpToCurrentRevisionImmediately(groupId: Data,
                                                           groupSecretParamsData: Data) -> Promise<TSGroupThread>

    func tryToRefreshV2GroupThread(groupId: Data,
                                   groupSecretParamsData: Data,
                                   groupUpdateMode: GroupUpdateMode) -> Promise<TSGroupThread>

    func updateGroupWithChangeActions(groupId: Data,
                                      changeActionsProto: GroupsProtoGroupChangeActions,
                                      downloadedAvatars: GroupV2DownloadedAvatars,
                                      transaction: SDSAnyWriteTransaction) throws -> TSGroupThread
}

// MARK: -

public protocol GroupV2Snapshot {
    var groupSecretParamsData: Data { get }

    var debugDescription: String { get }

    var revision: UInt32 { get }

    var title: String { get }

    var avatarUrlPath: String? { get }
    var avatarData: Data? { get }

    var groupMembership: GroupMembership { get }

    var groupAccess: GroupAccess { get }

    var disappearingMessageToken: DisappearingMessageToken { get }

    var profileKeys: [UUID: Data] { get }

    var inviteLinkPassword: Data? { get }
}

// MARK: -

public struct GroupV2Diff {
    public let changeActionsProto: GroupsProtoGroupChangeActions
    public let downloadedAvatars: GroupV2DownloadedAvatars

    public init(changeActionsProto: GroupsProtoGroupChangeActions,
                downloadedAvatars: GroupV2DownloadedAvatars) {
        self.changeActionsProto = changeActionsProto
        self.downloadedAvatars = downloadedAvatars
    }

    public var revision: UInt32 {
        return changeActionsProto.revision
    }
}

// MARK: -

public struct GroupV2Change {
    public var snapshot: GroupV2Snapshot?
    public var diff: GroupV2Diff

    public init(snapshot: GroupV2Snapshot?,
                diff: GroupV2Diff) {
        self.snapshot = snapshot
        self.diff = diff
    }

    public var revision: UInt32 {
        return diff.revision
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

@objc
public class GroupInviteLinkInfo: NSObject {
    @objc
    public let masterKey: Data
    @objc
    public let inviteLinkPassword: Data

    public init(masterKey: Data, inviteLinkPassword: Data) {
        self.masterKey = masterKey
        self.inviteLinkPassword = inviteLinkPassword
    }
}

// MARK: -

@objc
public class GroupInviteLinkPreview: NSObject {
    public let title: String
    public let avatarUrlPath: String?
    public let memberCount: UInt32
    public let addFromInviteLinkAccess: GroupV2Access
    public let revision: UInt32
    public let isLocalUserRequestingMember: Bool

    public init(title: String,
                avatarUrlPath: String?,
                memberCount: UInt32,
                addFromInviteLinkAccess: GroupV2Access,
                revision: UInt32,
                isLocalUserRequestingMember: Bool) {
        self.title = title
        self.avatarUrlPath = avatarUrlPath
        self.memberCount = memberCount
        self.addFromInviteLinkAccess = addFromInviteLinkAccess
        self.revision = revision
        self.isLocalUserRequestingMember = isLocalUserRequestingMember
    }

    @objc
    public override func isEqual(_ object: Any?) -> Bool {
        guard let otherRecipient = object as? GroupInviteLinkPreview else { return false }
        return (title == otherRecipient.title &&
            avatarUrlPath == otherRecipient.avatarUrlPath &&
            memberCount == otherRecipient.memberCount &&
            addFromInviteLinkAccess == otherRecipient.addFromInviteLinkAccess &&
            revision == otherRecipient.revision &&
            isLocalUserRequestingMember == otherRecipient.isLocalUserRequestingMember)
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
        return from(avatarData: groupModel.groupAvatarData, avatarUrlPath: groupModel.avatarUrlPath)
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

public struct InvalidInvite: Equatable {
    public let userId: Data
    public let addedByUserId: Data

    public init(userId: Data, addedByUserId: Data) {
        self.userId = userId
        self.addedByUserId = addedByUserId
    }
}

// MARK: -

public class MockGroupsV2: NSObject, GroupsV2Swift {

    public func createNewGroupOnService(groupModel: TSGroupModelV2,
                                        disappearingMessageToken: DisappearingMessageToken) -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public func generateGroupSecretParamsData() throws -> Data {
        if CurrentAppContext().isRunningTests {
            return Randomness.generateRandomBytes(289)
        }
        owsFail("Not implemented.")
    }

    public func groupId(forGroupSecretParamsData groupSecretParamsData: Data) throws -> Data {
        if CurrentAppContext().isRunningTests {
            owsAssert(groupSecretParamsData.count >= 32)
            return groupSecretParamsData.subdata(in: Int(0)..<Int(32))
        }
        owsFail("Not implemented.")
    }

    public func v2GroupId(forV1GroupId v1GroupId: Data) -> Data? {
        let v2GroupId = v1GroupId + v1GroupId
        owsAssert(GroupManager.isV1GroupId(v1GroupId))
        owsAssert(GroupManager.isV2GroupId(v2GroupId))
        return v2GroupId
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

    public func fetchCurrentGroupV2Snapshot(groupModel: TSGroupModelV2) -> Promise<GroupV2Snapshot> {
        owsFail("Not implemented.")
    }

    public func fetchCurrentGroupV2Snapshot(groupSecretParamsData: Data) -> Promise<GroupV2Snapshot> {
        owsFail("Not implemented.")
    }

    public func fetchGroupChangeActions(groupSecretParamsData: Data,
                                        includeCurrentRevision: Bool,
                                        firstKnownRevision: UInt32?) -> Promise<[GroupV2Change]> {
        owsFail("Not implemented.")
    }

    public func masterKeyData(forGroupModel groupModel: TSGroupModelV2) throws -> Data {
        owsFail("Not implemented.")
    }

    public func buildGroupContextV2Proto(groupModel: TSGroupModelV2,
                                         changeActionsProtoData: Data?) throws -> SSKProtoGroupContextV2 {
        owsFail("Not implemented.")
    }

    public func buildChangeSet(oldGroupModel: TSGroupModelV2,
                               newGroupModel: TSGroupModelV2,
                               oldDMConfiguration: OWSDisappearingMessagesConfiguration,
                               newDMConfiguration: OWSDisappearingMessagesConfiguration,
                               transaction: SDSAnyReadTransaction) throws -> GroupsV2ChangeSet {
        owsFail("Not implemented.")
    }

    public func updateExistingGroupOnService(changeSet: GroupsV2ChangeSet) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func updateGroupV2(groupModel: TSGroupModelV2,
                              changeSetBlock: @escaping (GroupsV2ChangeSet) -> Void) -> Promise<TSGroupThread> {
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

    public func isGroupKnownToStorageService(groupModel: TSGroupModelV2,
                                             transaction: SDSAnyReadTransaction) -> Bool {
        owsFail("Not implemented.")
    }

    public func restoreGroupFromStorageServiceIfNecessary(masterKeyData: Data, transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func isValidGroupV2MasterKey(_ masterKeyData: Data) -> Bool {
        owsFail("Not implemented.")
    }

    public func groupInviteLink(forGroupModelV2 groupModelV2: TSGroupModelV2) throws -> URL {
        owsFail("Not implemented.")
    }

    public func isPossibleGroupInviteLink(_ url: URL) -> Bool {
        owsFail("Not implemented.")
    }

    public func parseGroupInviteLink(_ url: URL) -> GroupInviteLinkInfo? {
        if CurrentAppContext().isRunningTests {
            Logger.warn("Not implemented.")
        } else {
            owsFail("Not implemented.")
        }
        return nil
    }

    public func cachedGroupInviteLinkPreview(groupSecretParamsData: Data) -> GroupInviteLinkPreview? {
        owsFail("Not implemented.")
    }

    public func fetchGroupInviteLinkPreview(inviteLinkPassword: Data?,
                                            groupSecretParamsData: Data,
                                            allowCached: Bool) -> Promise<GroupInviteLinkPreview> {
        owsFail("Not implemented.")
    }

    public func fetchGroupInviteLinkAvatar(avatarUrlPath: String,
                                           groupSecretParamsData: Data) -> Promise<Data> {
        owsFail("Not implemented.")
    }

    public func joinGroupViaInviteLink(groupId: Data,
                                       groupSecretParamsData: Data,
                                       inviteLinkPassword: Data,
                                       groupInviteLinkPreview: GroupInviteLinkPreview,
                                       avatarData: Data?) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func cancelMemberRequests(groupModel: TSGroupModelV2) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func tryToUpdatePlaceholderGroupModelUsingInviteLinkPreview(groupModel: TSGroupModelV2) {
        owsFail("Not implemented.")
    }

    public func fetchGroupExternalCredentials(groupModel: TSGroupModelV2) throws -> Promise<GroupsProtoGroupExternalCredential> {
        owsFail("Not implemented")
    }

    public func updateAlreadyMigratedGroupIfNecessary(v2GroupId: Data) -> Promise<Void> {
        owsFail("Not implemented")
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

    public func tryToRefreshV2GroupUpToCurrentRevisionImmediately(groupId: Data,
                                                                  groupSecretParamsData: Data) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func tryToRefreshV2GroupThread(groupId: Data,
                                          groupSecretParamsData: Data,
                                          groupUpdateMode: GroupUpdateMode) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func updateGroupWithChangeActions(groupId: Data,
                                             changeActionsProto: GroupsProtoGroupChangeActions,
                                             downloadedAvatars: GroupV2DownloadedAvatars,
                                             transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {
        owsFail("Not implemented.")
    }
}
