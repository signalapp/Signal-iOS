//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

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

public protocol GroupsV2 {

    func hasProfileKeyCredential(
        for address: SignalServiceAddress,
        transaction: SDSAnyReadTransaction
    ) -> Bool

    func scheduleAllGroupsV2ForProfileKeyUpdate(transaction: SDSAnyWriteTransaction)

    func processProfileKeyUpdates()

    func updateLocalProfileKeyInGroup(groupId: Data, transaction: SDSAnyWriteTransaction)

    func isGroupKnownToStorageService(
        groupModel: TSGroupModelV2,
        transaction: SDSAnyReadTransaction
    ) -> Bool

    typealias ProfileKeyCredentialMap = [Aci: ExpiringProfileKeyCredential]

    func createNewGroupOnService(
        groupModel: TSGroupModelV2,
        disappearingMessageToken: DisappearingMessageToken
    ) async throws -> GroupV2SnapshotResponse

    func loadProfileKeyCredentials(
        for acis: [Aci],
        forceRefresh: Bool
    ) async throws -> ProfileKeyCredentialMap

    func tryToFetchProfileKeyCredentials(
        for acis: [Aci],
        ignoreMissingProfiles: Bool,
        forceRefresh: Bool
    ) async throws

    func fetchLatestSnapshot(groupModel: TSGroupModelV2) async throws -> GroupV2SnapshotResponse

    func fetchLatestSnapshot(groupSecretParams: GroupSecretParams) async throws -> GroupV2SnapshotResponse

    func updateGroupV2(
        groupId: Data,
        groupSecretParams: GroupSecretParams,
        changesBlock: (GroupsV2OutgoingChanges) -> Void
    ) async throws -> TSGroupThread

    func updateGroupWithChangeActions(
        groupId: Data,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        changeActionsProto: GroupsProtoGroupChangeActions,
        groupSecretParams: GroupSecretParams
    ) async throws -> TSGroupThread

    func uploadGroupAvatar(avatarData: Data, groupSecretParams: GroupSecretParams) async throws -> String

    func cachedGroupInviteLinkPreview(groupSecretParams: GroupSecretParams) -> GroupInviteLinkPreview?

    // inviteLinkPassword is not necessary if we're already a member or have a pending request.
    func fetchGroupInviteLinkPreview(
        inviteLinkPassword: Data?,
        groupSecretParams: GroupSecretParams,
        allowCached: Bool
    ) async throws -> GroupInviteLinkPreview

    func fetchGroupInviteLinkAvatar(
        avatarUrlPath: String,
        groupSecretParams: GroupSecretParams
    ) async throws -> Data

    func fetchGroupAvatarRestoredFromBackup(
        groupModel: TSGroupModelV2,
        avatarUrlPath: String
    ) async throws -> TSGroupModel.AvatarDataState

    func joinGroupViaInviteLink(
        groupId: Data,
        groupSecretParams: GroupSecretParams,
        inviteLinkPassword: Data,
        groupInviteLinkPreview: GroupInviteLinkPreview,
        avatarData: Data?
    ) async throws

    func cancelRequestToJoin(groupModel: TSGroupModelV2) async throws -> TSGroupThread

    func fetchGroupExternalCredentials(secretParams: GroupSecretParams) async throws -> GroupsProtoGroupExternalCredential

    func groupRecordPendingStorageServiceRestore(
        masterKeyData: Data,
        transaction: SDSAnyReadTransaction
    ) -> StorageServiceProtoGroupV2Record?

    func restoreGroupFromStorageServiceIfNecessary(
        groupRecord: StorageServiceProtoGroupV2Record,
        account: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    )

    func fetchSomeGroupChangeActions(
        secretParams: GroupSecretParams,
        source: GroupChangeActionFetchSource
    ) async throws -> GroupChangesResponse

    func handleGroupSendEndorsementsResponse(
        _ groupSendEndorsementsResponse: GroupSendEndorsementsResponse,
        groupThreadId: Int64,
        secretParams: GroupSecretParams,
        membership: GroupMembership,
        localAci: Aci,
        tx: any DBWriteTransaction
    )
}

// MARK: -

/// Represents what we should do with regards to messages updating the other
/// members of the group about this change, if it successfully applied on
/// the service.
enum GroupUpdateMessageBehavior {
    /// Send a group update message to all other group members.
    case sendUpdateToOtherGroupMembers
    /// Do not send any group update messages.
    case sendNothing
}

// MARK: -

public enum GroupChangeActionFetchSource {
    /// We're fetching group change actions while processing an incoming
    /// message. We need to update to `revision` immediately and then stop
    /// applying updates. (We expect future updates will be applied by messages
    /// we've received but haven't yet processed.)
    case groupMessage(revision: UInt32)

    /// We're fetching group change actions for some other reason (e.g., we just
    /// opened the group). We want to ensure we have the latest state, but we
    /// don't want to update until we've had a chance to finish processing any
    /// messages that might update the group.
    case other
}

// MARK: -

/// Represents a constructed group change, ready to be sent to the service.
public struct GroupsV2BuiltGroupChange {
    let proto: GroupsProtoGroupChangeActions
    let groupUpdateMessageBehavior: GroupUpdateMessageBehavior
}

public protocol GroupsV2OutgoingChanges: AnyObject {
    var groupId: Data { get }
    var groupSecretParams: GroupSecretParams { get }

    var newAvatarData: Data? { get }
    var newAvatarUrlPath: String? { get }

    func setTitle(_ value: String)

    func setDescriptionText(_ value: String?)

    func setAvatar(_ avatar: (data: Data, urlPath: String)?)

    func addMember(_ aci: Aci, role: TSGroupMemberRole)

    func removeMember(_ serviceId: ServiceId)

    func addBannedMember(_ aci: Aci)

    func removeBannedMember(_ aci: Aci)

    func revokeInvalidInvites()

    func changeRoleForMember(_ aci: Aci, role: TSGroupMemberRole)

    func setAccessForMembers(_ value: GroupV2Access)

    func setAccessForAttributes(_ value: GroupV2Access)

    func addInvitedMember(_ serviceId: ServiceId, role: TSGroupMemberRole)

    func setLocalShouldAcceptInvite()

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
    ) async throws -> GroupsV2BuiltGroupChange
}

// MARK: -

public protocol GroupV2Updates {
    func refreshGroupImpl(
        secretParams: GroupSecretParams,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        source: GroupChangeActionFetchSource,
        options: TSGroupModelOptions
    ) async throws

    func updateGroupWithChangeActions(
        groupId: Data,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        changeActionsProto: GroupsProtoGroupChangeActions,
        groupSendEndorsementsResponse: GroupSendEndorsementsResponse?,
        downloadedAvatars: GroupV2DownloadedAvatars,
        transaction: SDSAnyWriteTransaction
    ) throws -> TSGroupThread
}

extension GroupV2Updates {
    public func refreshGroup(
        secretParams: GroupSecretParams,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata = .learnedByLocallyInitatedRefresh,
        source: GroupChangeActionFetchSource = .other,
        options: TSGroupModelOptions = []
    ) async throws {
        return try await refreshGroupImpl(
            secretParams: secretParams,
            spamReportingMetadata: spamReportingMetadata,
            source: source,
            options: options
        )
    }

    public func refreshGroupUpThroughCurrentRevision(groupThread: TSGroupThread, throttle: Bool) {
        refreshGroupUpThroughCurrentRevision(groupThread: groupThread, options: throttle ? [.throttle] : [])
    }

    private func refreshGroupUpThroughCurrentRevision(groupThread: TSGroupThread, options: TSGroupModelOptions) {
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            return
        }
        let groupSecretParamsData = groupModel.secretParamsData
        Task {
            do {
                try await self.refreshGroupImpl(
                    secretParams: try GroupSecretParams(contents: [UInt8](groupSecretParamsData)),
                    spamReportingMetadata: .learnedByLocallyInitatedRefresh,
                    source: .other,
                    options: options
                )
            } catch {
                Logger.warn("Group refresh failed: \(error).")
            }
        }
    }
}

// MARK: -

public struct GroupChangesResponse {
    var groupChanges: [GroupV2Change]
    var groupSendEndorsementsResponse: GroupSendEndorsementsResponse?
    var shouldFetchMore: Bool
}

public struct GroupV2Change {
    public var snapshot: GroupV2Snapshot?
    public var changeActionsProto: GroupsProtoGroupChangeActions?
    public let downloadedAvatars: GroupV2DownloadedAvatars

    public init(
        snapshot: GroupV2Snapshot?,
        changeActionsProto: GroupsProtoGroupChangeActions?,
        downloadedAvatars: GroupV2DownloadedAvatars
    ) {
        owsPrecondition(snapshot != nil || changeActionsProto != nil)
        self.snapshot = snapshot
        self.changeActionsProto = changeActionsProto
        self.downloadedAvatars = downloadedAvatars
    }

    public var revision: UInt32 {
        return changeActionsProto?.revision ?? snapshot!.revision
    }
}

// MARK: -

extension GroupMasterKey {
    static func isValid(_ masterKeyData: Data) -> Bool {
        return (try? GroupMasterKey(contents: [UInt8](masterKeyData))) != nil
    }
}

// MARK: -

public struct GroupV2ContextInfo {
    public let masterKeyData: Data
    public let groupSecretParams: GroupSecretParams
    public let groupSecretParamsData: Data
    public let groupId: Data

    public static func deriveFrom(masterKeyData: Data) throws -> GroupV2ContextInfo {
        let groupSecretParams = try self.groupSecretParams(for: masterKeyData)
        let groupIdentifier = try groupSecretParams.getPublicParams().getGroupIdentifier()
        return GroupV2ContextInfo(
            masterKeyData: masterKeyData,
            groupSecretParams: groupSecretParams,
            groupId: groupIdentifier.serialize().asData
        )
    }

    private static func groupSecretParams(for masterKeyData: Data) throws -> GroupSecretParams {
        let groupMasterKey = try GroupMasterKey(contents: [UInt8](masterKeyData))
        return try GroupSecretParams.deriveFromMasterKey(groupMasterKey: groupMasterKey)
    }

    private init(masterKeyData: Data, groupSecretParams: GroupSecretParams, groupId: Data) {
        self.masterKeyData = masterKeyData
        self.groupSecretParams = groupSecretParams
        self.groupSecretParamsData = groupSecretParams.serialize().asData
        self.groupId = groupId
    }
}

// MARK: -

public struct GroupInviteLinkInfo {
    public let masterKey: Data
    public let inviteLinkPassword: Data

    public init(masterKey: Data, inviteLinkPassword: Data) {
        self.masterKey = masterKey
        self.inviteLinkPassword = inviteLinkPassword
    }

    public static func parseFrom(_ url: URL) -> GroupInviteLinkInfo? {
        guard GroupManager.isPossibleGroupInviteLink(url) else {
            return nil
        }
        guard let protoBase64Url = url.fragment, !protoBase64Url.isEmpty else {
            owsFailDebug("Missing encoded data.")
            return nil
        }
        do {
            let protoData = try Data.data(fromBase64Url: protoBase64Url)
            let proto = try GroupsProtoGroupInviteLink(serializedData: protoData)
            guard let protoContents = proto.contents else {
                owsFailDebug("Missing proto contents.")
                return nil
            }
            switch protoContents {
            case .contentsV1(let contentsV1):
                guard let masterKey = contentsV1.groupMasterKey, !masterKey.isEmpty else {
                    owsFailDebug("Invalid masterKey.")
                    return nil
                }
                guard let inviteLinkPassword = contentsV1.inviteLinkPassword, !inviteLinkPassword.isEmpty else {
                    owsFailDebug("Invalid inviteLinkPassword.")
                    return nil
                }
                return GroupInviteLinkInfo(masterKey: masterKey, inviteLinkPassword: inviteLinkPassword)
            }
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }
}

// MARK: -

public struct GroupInviteLinkPreview: Equatable {
    public let title: String
    public let descriptionText: String?
    public let avatarUrlPath: String?
    public let memberCount: UInt32
    public let addFromInviteLinkAccess: GroupV2Access
    public let revision: UInt32
    public let isLocalUserRequestingMember: Bool
}

// MARK: -

public struct GroupV2DownloadedAvatars {
    typealias AvatarDataState = TSGroupModel.AvatarDataState

    private var avatarMap = [String: AvatarDataState]()

    init() {}

    mutating func set(avatarDataState: AvatarDataState, avatarUrlPath: String) {
        avatarMap[avatarUrlPath] = avatarDataState
    }

    mutating func merge(_ other: GroupV2DownloadedAvatars) {
        for (avatarUrlPath, avatarDataState) in other.avatarMap {
            avatarMap[avatarUrlPath] = avatarDataState
        }
    }

    func avatarDataState(for avatarUrlPath: String) -> AvatarDataState? {
        return avatarMap[avatarUrlPath]
    }

    var avatarUrlPaths: [String] {
        return Array(avatarMap.keys)
    }

    static func from(groupModel: TSGroupModelV2) -> GroupV2DownloadedAvatars {
        return from(
            avatarDataState: groupModel.avatarDataState,
            avatarUrlPath: groupModel.avatarUrlPath
        )
    }

    static func from(changes: GroupsV2OutgoingChanges) -> GroupV2DownloadedAvatars {
        return from(
            avatarDataState: AvatarDataState(avatarData: changes.newAvatarData),
            avatarUrlPath: changes.newAvatarUrlPath
        )
    }

    private static func from(avatarDataState: AvatarDataState, avatarUrlPath: String?) -> GroupV2DownloadedAvatars {
        var downloadedAvatars = GroupV2DownloadedAvatars()

        guard let avatarUrlPath else {
            return downloadedAvatars
        }

        downloadedAvatars.set(avatarDataState: avatarDataState, avatarUrlPath: avatarUrlPath)
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

public class MockGroupsV2: GroupsV2 {

    public func createNewGroupOnService(
        groupModel: TSGroupModelV2,
        disappearingMessageToken: DisappearingMessageToken
    ) async throws -> GroupV2SnapshotResponse {
        owsFail("Not implemented.")
    }

    public func hasProfileKeyCredential(for address: SignalServiceAddress,
                                        transaction: SDSAnyReadTransaction) -> Bool {
        owsFail("Not implemented.")
    }

    public func loadProfileKeyCredentials(
        for acis: [Aci],
        forceRefresh: Bool
    ) async throws -> ProfileKeyCredentialMap {
        owsFail("Not implemented.")
    }

    public func tryToFetchProfileKeyCredentials(
        for acis: [Aci],
        ignoreMissingProfiles: Bool,
        forceRefresh: Bool
    ) async throws { }

    public func fetchLatestSnapshot(groupModel: TSGroupModelV2) async throws -> GroupV2SnapshotResponse {
        owsFail("Not implemented.")
    }

    public func fetchLatestSnapshot(groupSecretParams: GroupSecretParams) async throws -> GroupV2SnapshotResponse {
        owsFail("Not implemented.")
    }

    public func updateGroupV2(
        groupId: Data,
        groupSecretParams: GroupSecretParams,
        changesBlock: (GroupsV2OutgoingChanges) -> Void
    ) async throws -> TSGroupThread {
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

    public func updateGroupWithChangeActions(
        groupId: Data,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        changeActionsProto: GroupsProtoGroupChangeActions,
        groupSecretParams: GroupSecretParams
    ) async throws -> TSGroupThread {
        owsFail("Not implemented.")
    }

    public func uploadGroupAvatar(
        avatarData: Data,
        groupSecretParams: GroupSecretParams
    ) async throws -> String {
        owsFail("Not implemented.")
    }

    public func isGroupKnownToStorageService(
        groupModel: TSGroupModelV2,
        transaction: SDSAnyReadTransaction
    ) -> Bool {
        return true
    }

    public func groupRecordPendingStorageServiceRestore(masterKeyData: Data, transaction: SDSAnyReadTransaction) -> StorageServiceProtoGroupV2Record? {
        return nil
    }

    public func restoreGroupFromStorageServiceIfNecessary(
        groupRecord: StorageServiceProtoGroupV2Record,
        account: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        owsFail("Not implemented.")
    }

    public func cachedGroupInviteLinkPreview(groupSecretParams: GroupSecretParams) -> GroupInviteLinkPreview? {
        owsFail("Not implemented.")
    }

    public func fetchGroupInviteLinkPreview(
        inviteLinkPassword: Data?,
        groupSecretParams: GroupSecretParams,
        allowCached: Bool
    ) async throws -> GroupInviteLinkPreview {
        owsFail("Not implemented.")
    }

    public func fetchGroupInviteLinkAvatar(
        avatarUrlPath: String,
        groupSecretParams: GroupSecretParams
    ) async throws -> Data {
        owsFail("Not implemented.")
    }

    public func fetchGroupAvatarRestoredFromBackup(
        groupModel: TSGroupModelV2,
        avatarUrlPath: String
    ) async throws -> TSGroupModel.AvatarDataState {
        owsFail("Not implemented")
    }

    public func joinGroupViaInviteLink(
        groupId: Data,
        groupSecretParams: GroupSecretParams,
        inviteLinkPassword: Data,
        groupInviteLinkPreview: GroupInviteLinkPreview,
        avatarData: Data?
    ) async throws {
        owsFail("Not implemented.")
    }

    public func cancelRequestToJoin(groupModel: TSGroupModelV2) async throws -> TSGroupThread {
        owsFail("Not implemented.")
    }

    public func fetchGroupExternalCredentials(secretParams: GroupSecretParams) async throws -> GroupsProtoGroupExternalCredential {
        owsFail("Not implemented")
    }

    public func fetchSomeGroupChangeActions(secretParams: GroupSecretParams, source: GroupChangeActionFetchSource) async throws -> GroupChangesResponse {
        owsFail("not implemented")
    }

    public func handleGroupSendEndorsementsResponse(
        _ groupSendEndorsementsResponse: GroupSendEndorsementsResponse,
        groupThreadId: Int64,
        secretParams: GroupSecretParams,
        membership: GroupMembership,
        localAci: Aci,
        tx: any DBWriteTransaction
    ) {
        owsFail("Not implemented.")
    }
}

// MARK: -

public class MockGroupV2Updates: GroupV2Updates {
    public func refreshGroupImpl(
        secretParams: GroupSecretParams,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        source: GroupChangeActionFetchSource,
        options: TSGroupModelOptions
    ) async throws {
        owsFail("Not implemented.")
    }

    public func updateGroupWithChangeActions(
        groupId: Data,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        changeActionsProto: GroupsProtoGroupChangeActions,
        groupSendEndorsementsResponse: GroupSendEndorsementsResponse?,
        downloadedAvatars: GroupV2DownloadedAvatars,
        transaction: SDSAnyWriteTransaction
    ) throws -> TSGroupThread {
        owsFail("Not implemented.")
    }
}
