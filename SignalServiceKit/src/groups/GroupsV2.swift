//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public enum GroupsV2Error: Error {
    /// By the time we tried to apply the change, it was irrelevant.
    case redundantChange
    /// The change we attempted conflicts with what is on the service.
    case conflictingChangeOnService
    case shouldRetry
    case shouldDiscard
    case timeout
    case localUserNotInGroup
    case cannotBuildGroupChangeProto_conflictingChange
    case cannotBuildGroupChangeProto_lastAdminCantLeaveGroup
    case cannotBuildGroupChangeProto_tooManyMembers
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
    case missingGroupChangeProtos
    case groupBlocked
    case newMemberMissingAnnouncementOnlyCapability
    case localUserBlockedFromJoining

    /// We tried to apply an incremental group change proto but failed due to
    /// an incompatible revision in the proto.
    ///
    /// Note that group change protos can only be applied if they are a
    /// continuous incremental update, i.e. our local revision is N and the
    /// proto represents revision N+1.
    case groupChangeProtoForIncompatibleRevision

    /// We hit a 400 while making a service request, but believe it may be
    /// recoverable.
    case serviceRequestHitRecoverable400
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

    func masterKeyData(forGroupModel groupModel: TSGroupModelV2) throws -> Data

    func buildGroupContextV2Proto(groupModel: TSGroupModelV2,
                                  changeActionsProtoData: Data?) throws -> SSKProtoGroupContextV2

    func groupV2ContextInfo(forMasterKeyData masterKeyData: Data?) throws -> GroupV2ContextInfo

    func scheduleAllGroupsV2ForProfileKeyUpdate(transaction: SDSAnyWriteTransaction)

    func processProfileKeyUpdates()

    func updateLocalProfileKeyInGroup(groupId: Data, transaction: SDSAnyWriteTransaction)

    func isGroupKnownToStorageService(groupModel: TSGroupModelV2,
                                      transaction: SDSAnyReadTransaction) -> Bool

    func isValidGroupV2MasterKey(_ masterKeyData: Data) -> Bool

    func clearTemporalCredentials(transaction: SDSAnyWriteTransaction)
}

// MARK: -

public protocol GroupsV2Swift: GroupsV2 {

    typealias ProfileKeyCredentialMap = [UUID: ExpiringProfileKeyCredential]

    func createNewGroupOnService(groupModel: TSGroupModelV2,
                                 disappearingMessageToken: DisappearingMessageToken) -> Promise<Void>

    func loadProfileKeyCredentials(
        for uuids: [UUID],
        forceRefresh: Bool
    ) -> Promise<ProfileKeyCredentialMap>

    func tryToFetchProfileKeyCredentials(
        for uuids: [UUID],
        ignoreMissingProfiles: Bool,
        forceRefresh: Bool
    ) -> Promise<Void>

    func fetchCurrentGroupV2Snapshot(groupModel: TSGroupModelV2) -> Promise<GroupV2Snapshot>

    func fetchCurrentGroupV2Snapshot(groupSecretParamsData: Data) -> Promise<GroupV2Snapshot>

    func updateGroupV2(
        groupId: Data,
        groupSecretParamsData: Data,
        changesBlock: @escaping (GroupsV2OutgoingChanges) -> Void
    ) -> Promise<TSGroupThread>

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

    func tryToUpdatePlaceholderGroupModelUsingInviteLinkPreview(
        groupModel: TSGroupModelV2,
        removeLocalUserBlock: @escaping (SDSAnyWriteTransaction) -> Void
    )

    func fetchGroupExternalCredentials(groupModel: TSGroupModelV2) throws -> Promise<GroupsProtoGroupExternalCredential>

    func updateAlreadyMigratedGroupIfNecessary(v2GroupId: Data) -> Promise<Void>

    func groupRecordPendingStorageServiceRestore(
        masterKeyData: Data,
        transaction: SDSAnyReadTransaction
    ) -> StorageServiceProtoGroupV2Record?

    func restoreGroupFromStorageServiceIfNecessary(
        groupRecord: StorageServiceProtoGroupV2Record,
        transaction: SDSAnyWriteTransaction
    )
}

// MARK: -

public protocol GroupsV2OutgoingChanges: AnyObject {
    var groupId: Data { get }
    var groupSecretParamsData: Data { get }

    var newAvatarData: Data? { get }
    var newAvatarUrlPath: String? { get }

    func setTitle(_ value: String)

    func setDescriptionText(_ value: String?)

    func setAvatar(_ avatar: (data: Data, urlPath: String)?)

    func addMember(_ uuid: UUID, role: TSGroupMemberRole)

    func removeMember(_ uuid: UUID)

    func addBannedMember(_ uuid: UUID)

    func removeBannedMember(_ uuid: UUID)

    func revokeInvalidInvites()

    func changeRoleForMember(_ uuid: UUID, role: TSGroupMemberRole)

    func setAccessForMembers(_ value: GroupV2Access)

    func setAccessForAttributes(_ value: GroupV2Access)

    func addInvitedMember(_ uuid: UUID, role: TSGroupMemberRole)

    func promoteInvitedMember(_ uuid: UUID)

    func setShouldLeaveGroupDeclineInvite()

    func setNewDisappearingMessageToken(_ newDisappearingMessageToken: DisappearingMessageToken)

    func setLinkMode(_ linkMode: GroupsV2LinkMode)

    func rotateInviteLinkPassword()

    func setIsAnnouncementsOnly(_ isAnnouncementsOnly: Bool)

    func setShouldUpdateLocalProfileKey()

    func buildGroupChangeProto(
        currentGroupModel: TSGroupModelV2,
        currentDisappearingMessageToken: DisappearingMessageToken,
        forceRefreshProfileKeyCredentials: Bool
    ) -> Promise<GroupsProtoGroupChangeActions>
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
    // * Group update _should_ block on message processing.
    // * Group update _should not_ be throttled.
    case upToCurrentRevisionAfterMessageProcessWithoutThrottling
    // * Group update should continue until current revision.
    // * Group update _should not_ block on message processing.
    // * Group update _should not_ be throttled.
    case upToCurrentRevisionImmediately

    public var shouldBlockOnMessageProcessing: Bool {
        switch self {
        case .upToCurrentRevisionAfterMessageProcessWithThrottling,
             .upToCurrentRevisionAfterMessageProcessWithoutThrottling:
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

    public var shouldUpdateToCurrentRevision: Bool {
        switch self {
        case .upToSpecificRevisionImmediately:
            return false
        default:
            return true
        }
    }
}

// MARK: -

@objc
public protocol GroupV2Updates: AnyObject {
    func tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithThrottling(_ groupThread: TSGroupThread)

    func tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithoutThrottling(_ groupThread: TSGroupThread)
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
    var descriptionText: String? { get }

    var avatarUrlPath: String? { get }
    var avatarData: Data? { get }

    var groupMembership: GroupMembership { get }

    var groupAccess: GroupAccess { get }

    var disappearingMessageToken: DisappearingMessageToken { get }

    var profileKeys: [UUID: Data] { get }

    var inviteLinkPassword: Data? { get }

    var isAnnouncementsOnly: Bool { get }
}

// MARK: -

public struct GroupV2Change {
    public var snapshot: GroupV2Snapshot?
    public var changeActionsProto: GroupsProtoGroupChangeActions?
    public let downloadedAvatars: GroupV2DownloadedAvatars

    public init(snapshot: GroupV2Snapshot?,
                changeActionsProto: GroupsProtoGroupChangeActions?,
                downloadedAvatars: GroupV2DownloadedAvatars) {
        owsAssert(snapshot != nil || changeActionsProto != nil)
        self.snapshot = snapshot
        self.changeActionsProto = changeActionsProto
        self.downloadedAvatars = downloadedAvatars
    }

    public var revision: UInt32 {
        return changeActionsProto?.revision ?? snapshot!.revision
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
    public let descriptionText: String?
    public let avatarUrlPath: String?
    public let memberCount: UInt32
    public let addFromInviteLinkAccess: GroupV2Access
    public let revision: UInt32
    public let isLocalUserRequestingMember: Bool

    public init(title: String,
                descriptionText: String?,
                avatarUrlPath: String?,
                memberCount: UInt32,
                addFromInviteLinkAccess: GroupV2Access,
                revision: UInt32,
                isLocalUserRequestingMember: Bool) {
        self.title = title
        self.descriptionText = descriptionText
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
                    descriptionText == otherRecipient.descriptionText &&
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
        return from(avatarData: groupModel.avatarData, avatarUrlPath: groupModel.avatarUrlPath)
    }

    public static func from(changes: GroupsV2OutgoingChanges) -> GroupV2DownloadedAvatars {
        return from(avatarData: changes.newAvatarData, avatarUrlPath: changes.newAvatarUrlPath)
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
        guard TSGroupModel.isValidGroupAvatarData(avatarData) else {
            owsFailDebug("Invalid group avatar")
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

public class MockGroupsV2: NSObject, GroupsV2Swift, GroupsV2 {

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

    public func loadProfileKeyCredentials(
        for uuids: [UUID],
        forceRefresh: Bool
    ) -> Promise<ProfileKeyCredentialMap> {
        owsFail("Not implemented.")
    }

    public func tryToFetchProfileKeyCredentials(
        for uuids: [UUID],
        ignoreMissingProfiles: Bool,
        forceRefresh: Bool
    ) -> Promise<Void> {
        return Promise.value(())
    }

    public func fetchCurrentGroupV2Snapshot(groupModel: TSGroupModelV2) -> Promise<GroupV2Snapshot> {
        owsFail("Not implemented.")
    }

    public func fetchCurrentGroupV2Snapshot(groupSecretParamsData: Data) -> Promise<GroupV2Snapshot> {
        owsFail("Not implemented.")
    }

    public func masterKeyData(forGroupModel groupModel: TSGroupModelV2) throws -> Data {
        owsFail("Not implemented.")
    }

    public func buildGroupContextV2Proto(groupModel: TSGroupModelV2,
                                         changeActionsProtoData: Data?) throws -> SSKProtoGroupContextV2 {
        owsFail("Not implemented.")
    }

    public func updateGroupV2(
        groupId: Data,
        groupSecretParamsData: Data,
        changesBlock: @escaping (GroupsV2OutgoingChanges) -> Void
    ) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func reuploadLocalProfilePromise() -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public var groupV2ContextInfos = [Data: GroupV2ContextInfo]()

    public func groupV2ContextInfo(forMasterKeyData masterKeyData: Data?) throws -> GroupV2ContextInfo {
        guard let masterKeyData = masterKeyData, let info = groupV2ContextInfos[masterKeyData] else {
            owsFail("No registered GroupV2ContextInfo on mock")
        }
        return info
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
        return true
    }

    public func groupRecordPendingStorageServiceRestore(masterKeyData: Data, transaction: SDSAnyReadTransaction) -> StorageServiceProtoGroupV2Record? {
        return nil
    }

    public func restoreGroupFromStorageServiceIfNecessary(groupRecord: StorageServiceProtoGroupV2Record, transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func isValidGroupV2MasterKey(_ masterKeyData: Data) -> Bool {
        owsFail("Not implemented.")
    }

    public func clearTemporalCredentials(transaction: SDSAnyWriteTransaction) {
        // Do nothing.
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

    public func tryToUpdatePlaceholderGroupModelUsingInviteLinkPreview(
        groupModel _: TSGroupModelV2,
        removeLocalUserBlock _: (SDSAnyWriteTransaction) -> Void
    ) {
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

public class MockGroupV2Updates: NSObject, GroupV2UpdatesSwift, GroupV2Updates {
    @objc
    public func tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithThrottling(_ groupThread: TSGroupThread) {
        owsFail("Not implemented.")
    }

    @objc
    public func tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithoutThrottling(_ groupThread: TSGroupThread) {
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
