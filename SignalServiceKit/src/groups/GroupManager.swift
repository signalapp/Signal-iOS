//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class UpsertGroupResult: NSObject {
    @objc
    public enum Action: UInt {
        case inserted
        case updatedWithUserFacingChanges
        case updatedWithoutUserFacingChanges
        case unchanged
    }

    @objc
    public let action: Action

    @objc
    public let groupThread: TSGroupThread

    public required init(action: Action, groupThread: TSGroupThread) {
        self.action = action
        self.groupThread = groupThread
    }
}

// MARK: -

// * The "local" methods are used in response to the local user's interactions.
// * The "remote" methods are used in response to remote activity (incoming messages,
//   sync transcripts, group syncs, etc.).
@objc
public class GroupManager: NSObject {

    // Never instantiate this class.
    private override init() {}

    // MARK: -

    // GroupsV2 TODO: Finalize this value with the designers.
    public static let groupUpdateTimeoutDuration: TimeInterval = 30

    public static var groupsV2MaxGroupSizeRecommended: UInt {
        return RemoteConfig.groupsV2MaxGroupSizeRecommended
    }

    public static var groupsV2MaxGroupSizeHardLimit: UInt {
        return RemoteConfig.groupsV2MaxGroupSizeHardLimit
    }

    public static let maxGroupNameEncryptedByteCount: Int = 1024
    public static let maxGroupNameGlyphCount: Int = 32

    public static let maxGroupDescriptionEncryptedByteCount: Int = 8192
    public static let maxGroupDescriptionGlyphCount: Int = 480

    // Epoch 1: Group Links
    // Epoch 2: Group Description
    // Epoch 3: Announcement-Only Groups
    // Epoch 4: Banned Members
    // Epoch 5: Promote pending PNI members
    public static let changeProtoEpoch: UInt32 = 5

    // This matches kOversizeTextMessageSizeThreshold.
    public static let maxEmbeddedChangeProtoLength: UInt = 2 * 1024

    // MARK: - Group IDs

    private static func groupIdLength(for groupsVersion: GroupsVersion) -> Int32 {
        switch groupsVersion {
        case .V1:
            return kGroupIdLengthV1
        case .V2:
            return kGroupIdLengthV2
        }
    }

    @objc
    public static func isV1GroupId(_ groupId: Data) -> Bool {
        groupId.count == groupIdLength(for: .V1)
    }

    @objc
    public static func isV2GroupId(_ groupId: Data) -> Bool {
        groupId.count == groupIdLength(for: .V2)
    }

    @objc
    public static func isValidGroupId(_ groupId: Data, groupsVersion: GroupsVersion) -> Bool {
        let expectedLength = groupIdLength(for: groupsVersion)
        guard groupId.count == expectedLength else {
            owsFailDebug("Invalid groupId: \(groupId.count) != \(expectedLength)")
            return false
        }
        return true
    }

    @objc
    public static func isValidGroupIdOfAnyKind(_ groupId: Data) -> Bool {
        return isV1GroupId(groupId) || isV2GroupId(groupId)
    }

    // MARK: -

    public static func canLocalUserLeaveGroupWithoutChoosingNewAdmin(localAddress: SignalServiceAddress,
                                                                     groupMembership: GroupMembership) -> Bool {
        guard let localUuid = localAddress.uuid else {
            owsFailDebug("Missing localUuid.")
            return false
        }
        let remainingFullMemberUuids = Set(groupMembership.fullMembers.compactMap { $0.uuid })
        let remainingAdminUuids = Set(groupMembership.fullMemberAdministrators.compactMap { $0.uuid })
        return canLocalUserLeaveGroupWithoutChoosingNewAdmin(localUuid: localUuid,
                                                             remainingFullMemberUuids: remainingFullMemberUuids,
                                                             remainingAdminUuids: remainingAdminUuids)
    }

    public static func canLocalUserLeaveGroupWithoutChoosingNewAdmin(localUuid: UUID,
                                                                     remainingFullMemberUuids: Set<UUID>,
                                                                     remainingAdminUuids: Set<UUID>) -> Bool {
        let isLocalUserAdministrator = remainingAdminUuids.contains(localUuid)
        guard isLocalUserAdministrator else {
            // Only admins need to appoint new admins before leaving the group.
            return true
        }
        guard remainingAdminUuids.count == 1 else {
            // There's more than one admin.
            return true
        }
        guard remainingFullMemberUuids.count > 1 else {
            // There's no one else in the group, we can abandon it.
            return true
        }
        return false
    }

    // MARK: - Group Models

    @objc
    public static func fakeGroupModel(groupId: Data) -> TSGroupModel? {
        do {
            var builder = TSGroupModelBuilder()
            builder.groupId = groupId

            if GroupManager.isV1GroupId(groupId) {
                builder.groupsVersion = .V1
            } else if GroupManager.isV2GroupId(groupId) {
                builder.groupsVersion = .V2
            } else {
                throw OWSAssertionError("Invalid group id: \(groupId).")
            }

            return try builder.build()
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    /// Confirms that a given address supports V2 groups.
    ///
    /// This check will succeed for any currently-registered users. It is
    /// possible that contacts dating from the V1 group era will fail this
    /// check.
    ///
    /// This method should only be used in contexts in which it is possible we
    /// are dealing with very old historical contacts, and need to filter them
    /// for those that are GV2-compatible.
    public static func doesUserSupportGroupsV2(address: SignalServiceAddress) -> Bool {
        guard address.isValid else {
            Logger.warn("Invalid address: \(address).")
            return false
        }

        guard address.uuid != nil else {
            Logger.warn("Member without UUID.")
            return false
        }

        return true
    }

    // MARK: - Create New Group

    /// Create a new group locally, and upload it to the service.
    ///
    /// - Parameter groupId
    /// A fixed group ID. Intended for use exclusively in tests.
    public static func localCreateNewGroup(members membersParam: [SignalServiceAddress],
                                           groupId: Data? = nil,
                                           name: String? = nil,
                                           avatarData: Data? = nil,
                                           disappearingMessageToken: DisappearingMessageToken,
                                           newGroupSeed: NewGroupSeed? = nil,
                                           shouldSendMessage: Bool) -> Promise<TSGroupThread> {

        guard let localAddress = tsAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Missing localAddress."))
        }

        return firstly { () -> Promise<Void> in
            return self.ensureLocalProfileHasCommitmentIfNecessary()
        }.map(on: DispatchQueue.global()) { () throws -> GroupMembership in
            // Build member list.
            //
            // The group creator is an administrator;
            // the other members are normal users.
            var builder = GroupMembership.Builder()
            builder.addFullMembers(Set(membersParam), role: .normal)
            builder.remove(localAddress)
            builder.addFullMember(localAddress, role: .administrator)
            return builder.build()
        }.then(on: DispatchQueue.global()) { (groupMembership: GroupMembership) -> Promise<GroupMembership> in
            // Try to get profile key credentials for all group members, since
            // we need them to fully add (rather than merely inviting) members.
            firstly { () -> Promise<Void> in
                self.groupsV2Swift.tryToFetchProfileKeyCredentials(
                    for: groupMembership.allMembersOfAnyKind.compactMap { $0.uuid },
                    ignoreMissingProfiles: false,
                    forceRefresh: false
                )
            }.map(on: DispatchQueue.global()) { _ -> GroupMembership in
                return groupMembership
            }
        }.map(on: DispatchQueue.global()) { (proposedGroupMembership: GroupMembership) throws -> TSGroupModelV2 in
            let groupAccess = GroupAccess.defaultForV2
            let groupModel = try self.databaseStorage.read { (transaction) throws -> TSGroupModelV2 in
                // Before we create the group, we need to separate out the
                // pending and full members.
                let groupMembership = self.separateInvitedMembersForNewGroup(
                    withMembership: proposedGroupMembership,
                    transaction: transaction
                )

                guard groupMembership.isFullMember(localAddress) else {
                    throw OWSAssertionError("Missing localAddress.")
                }

                // The avatar URL path will be filled in later.
                var builder = TSGroupModelBuilder()
                builder.groupId = groupId
                builder.name = name
                builder.avatarData = avatarData
                builder.avatarUrlPath = nil
                builder.groupMembership = groupMembership
                builder.groupAccess = groupAccess
                builder.newGroupSeed = newGroupSeed
                return try builder.buildAsV2()
            }

            return groupModel
        }.then(on: DispatchQueue.global()) { (proposedGroupModel: TSGroupModelV2) -> Promise<TSGroupModelV2> in
            guard let avatarData = avatarData else {
                // No avatar to upload.
                return Promise.value(proposedGroupModel)
            }
            // Upload avatar.
            return firstly {
                self.groupsV2Swift.uploadGroupAvatar(avatarData: avatarData,
                                                     groupSecretParamsData: proposedGroupModel.secretParamsData)
            }.map(on: DispatchQueue.global()) { (avatarUrlPath: String) -> TSGroupModelV2 in
                // Fill in the avatarUrl on the group model.
                var builder = proposedGroupModel.asBuilder
                builder.avatarUrlPath = avatarUrlPath
                return try builder.buildAsV2()
            }
        }.then(on: DispatchQueue.global()) { (proposedGroupModel: TSGroupModelV2) -> Promise<TSGroupModelV2> in
            return firstly {
                self.groupsV2Swift.createNewGroupOnService(groupModel: proposedGroupModel,
                                                           disappearingMessageToken: disappearingMessageToken)
            }.then(on: DispatchQueue.global()) { _ in
                self.groupsV2Swift.fetchCurrentGroupV2Snapshot(groupModel: proposedGroupModel)
            }.map(on: DispatchQueue.global()) { (groupV2Snapshot: GroupV2Snapshot) throws -> TSGroupModelV2 in
                let createdGroupModel = try self.databaseStorage.write { (transaction) throws -> TSGroupModelV2 in
                    var builder = try TSGroupModelBuilder.builderForSnapshot(groupV2Snapshot: groupV2Snapshot,
                                                                             transaction: transaction)
                    builder.wasJustCreatedByLocalUser = true
                    return try builder.buildAsV2()
                }
                if proposedGroupModel != createdGroupModel {
                    owsFailDebug("Proposed group model does not match created group model.")
                }
                return createdGroupModel
            }
        }.then(on: DispatchQueue.global()) { (groupModel: TSGroupModelV2) -> Promise<TSGroupThread> in
            let thread = databaseStorage.write { (transaction: SDSAnyWriteTransaction) -> TSGroupThread in
                return self.insertGroupThreadInDatabaseAndCreateInfoMessage(groupModel: groupModel,
                                                                            disappearingMessageToken: disappearingMessageToken,
                                                                            groupUpdateSourceAddress: localAddress,
                                                                            shouldAttributeAuthor: true,
                                                                            transaction: transaction)
            }

            self.profileManager.addThread(toProfileWhitelist: thread)

            if shouldSendMessage {
                return firstly {
                    sendDurableNewGroupMessage(forThread: thread)
                }.map(on: DispatchQueue.global()) { _ in
                    return thread
                }
            } else {
                return Promise.value(thread)
            }
        }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                  description: "Create new group") {
            GroupsV2Error.timeout
        }
    }

    // Separates pending and non-pending members.
    // We cannot add non-pending members unless:
    //
    // * We know their profile key.
    // * We have a profile key credential for them.
    private static func separateInvitedMembersForNewGroup(withMembership newGroupMembership: GroupMembership,
                                                          transaction: SDSAnyReadTransaction) -> GroupMembership {
        guard let localUuid = tsAccountManager.localUuid else {
            owsFailDebug("Missing localUuid.")
            return newGroupMembership
        }
        var builder = GroupMembership.Builder()

        let newMembers = newGroupMembership.allMembersOfAnyKind

        // We only need to separate new members.
        for address in newMembers {
            // We must call this _after_ we try to fetch profile key credentials for
            // all members.
            let isPending = !groupsV2Swift.hasProfileKeyCredential(for: address,
                                                                   transaction: transaction)
            guard let role = newGroupMembership.role(for: address) else {
                owsFailDebug("Missing role: \(address)")
                continue
            }

            if isPending {
                builder.addInvitedMember(address, role: role, addedByUuid: localUuid)
            } else {
                builder.addFullMember(address, role: role)
            }
        }
        return builder.build()
    }

    // MARK: - Tests

    #if TESTABLE_BUILD

    @objc
    public static func createGroupForTests(members: [SignalServiceAddress],
                                           name: String? = nil,
                                           avatarData: Data? = nil) throws -> TSGroupThread {

        return try databaseStorage.write { transaction in
            return try createGroupForTests(members: members,
                                           name: name,
                                           avatarData: avatarData,
                                           transaction: transaction)
        }
    }

    @objc
    public static func createGroupForTestsObjc(members: [SignalServiceAddress],
                                               name: String? = nil,
                                               avatarData: Data? = nil,
                                               transaction: SDSAnyWriteTransaction) -> TSGroupThread {
        do {
            return try createGroupForTests(members: members,
                                           name: name,
                                           avatarData: avatarData,
                                           groupsVersion: .V1, // Tests historically hardcode V1 groups.
                                           transaction: transaction)
        } catch {
            owsFail("Error: \(error)")
        }
    }

    public static func createGroupForTests(members: [SignalServiceAddress],
                                           name: String? = nil,
                                           descriptionText: String? = nil,
                                           avatarData: Data? = nil,
                                           groupId: Data? = nil,
                                           groupsVersion: GroupsVersion = .V1,
                                           transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {

        guard let localAddress = tsAccountManager.localAddress else {
            throw OWSAssertionError("Missing localAddress.")
        }

        // GroupsV2 TODO: Elaborate tests to include admins, pending members, etc.
        let groupMembership = GroupMembership(v1Members: Set(members))
        // GroupsV2 TODO: Let tests specify access levels.
        // GroupsV2 TODO: Fill in avatarUrlPath when we test v2 groups.
        let groupAccess = GroupAccess.defaultForV1
        // Use buildGroupModel() to fill in defaults, like it was a new group.

        var builder = TSGroupModelBuilder()
        builder.groupId = groupId
        builder.name = name
        builder.descriptionText = descriptionText
        builder.avatarData = avatarData
        builder.avatarUrlPath = nil
        builder.groupMembership = groupMembership
        builder.groupAccess = groupAccess
        builder.groupsVersion = groupsVersion
        let groupModel = try builder.build()

        // Just create it in the database, don't create it on the service.
        return try remoteUpsertExistingGroupForTests(groupModel: groupModel,
                                                     disappearingMessageToken: nil,
                                                     groupUpdateSourceAddress: localAddress,
                                                     transaction: transaction).groupThread
    }

    // If disappearingMessageToken is nil, don't update the disappearing messages configuration.
    private static func remoteUpsertExistingGroupForTests(groupModel: TSGroupModel,
                                                          disappearingMessageToken: DisappearingMessageToken?,
                                                          groupUpdateSourceAddress: SignalServiceAddress?,
                                                          infoMessagePolicy: InfoMessagePolicy = .always,
                                                          transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {
        owsAssertDebug(groupModel.groupsVersion == .V1)

        return try self.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(
            newGroupModel: groupModel,
            newDisappearingMessageToken: disappearingMessageToken,
            newlyLearnedPniToAciAssociations: [:],
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            canInsert: true,
            didAddLocalUserToV2Group: false,
            infoMessagePolicy: infoMessagePolicy,
            transaction: transaction
        )
    }

    #endif

    // MARK: - Disappearing Messages

    @objc
    public static func remoteUpdateDisappearingMessages(withContactThread thread: TSThread,
                                                        disappearingMessageToken: DisappearingMessageToken,
                                                        groupUpdateSourceAddress: SignalServiceAddress?,
                                                        transaction: SDSAnyWriteTransaction) {
        guard !thread.isGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        _ = self.updateDisappearingMessagesInDatabaseAndCreateMessages(token: disappearingMessageToken,
                                                                       thread: thread,
                                                                       shouldInsertInfoMessage: true,
                                                                       groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                       transaction: transaction)
    }

    public static func localUpdateDisappearingMessages(thread: TSThread,
                                                       disappearingMessageToken: DisappearingMessageToken) -> Promise<Void> {

        let simpleUpdate = {
            return databaseStorage.write(.promise) { transaction in
                let updateResult = self.updateDisappearingMessagesInDatabaseAndCreateMessages(token: disappearingMessageToken,
                                                                                              thread: thread,
                                                                                              shouldInsertInfoMessage: true,
                                                                                              groupUpdateSourceAddress: nil,
                                                                                              transaction: transaction)
                self.sendDisappearingMessagesConfigurationMessage(updateResult: updateResult,
                                                                  thread: thread,
                                                                  transaction: transaction)
            }
        }

        guard let groupThread = thread as? TSGroupThread else {
            return simpleUpdate()
        }
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            return simpleUpdate()
        }

        return firstly {
            updateGroupV2(groupModel: groupModel,
                          description: "Update disappearing messages") { groupChangeSet in
                groupChangeSet.setNewDisappearingMessageToken(disappearingMessageToken)
            }
        }.asVoid()
    }

    private struct UpdateDMConfigurationResult {
        let oldConfiguration: OWSDisappearingMessagesConfiguration
        let newConfiguration: OWSDisappearingMessagesConfiguration
    }

    private static func updateDisappearingMessagesInDatabaseAndCreateMessages(
        token newToken: DisappearingMessageToken,
        thread: TSThread,
        shouldInsertInfoMessage: Bool,
        groupUpdateSourceAddress: SignalServiceAddress?,
        transaction: SDSAnyWriteTransaction
    ) -> UpdateDMConfigurationResult {
        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let result = dmConfigurationStore.set(token: newToken, for: .thread(thread), tx: transaction.asV2Write)

        // Skip redundant updates.
        if result.newConfiguration != result.oldConfiguration {
            if shouldInsertInfoMessage {
                var remoteContactName: String?
                if let groupUpdateSourceAddress, groupUpdateSourceAddress.isValid, !groupUpdateSourceAddress.isLocalAddress {
                    remoteContactName = contactsManager.displayName(for: groupUpdateSourceAddress, transaction: transaction)
                }
                let infoMessage = OWSDisappearingConfigurationUpdateInfoMessage(
                    thread: thread,
                    configuration: result.newConfiguration,
                    createdByRemoteName: remoteContactName,
                    createdInExistingGroup: false
                )
                infoMessage.anyInsert(transaction: transaction)
            }

            databaseStorage.touch(thread: thread, shouldReindex: false, transaction: transaction)
        }

        return UpdateDMConfigurationResult(
            oldConfiguration: result.oldConfiguration,
            newConfiguration: result.newConfiguration
        )
    }

    private static func sendDisappearingMessagesConfigurationMessage(
        updateResult: UpdateDMConfigurationResult,
        thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) {
        guard updateResult.newConfiguration != updateResult.oldConfiguration else {
            // The update was redundant, don't send an update message.
            return
        }
        guard !thread.isGroupV2Thread else {
            // Don't send DM configuration messages for v2 groups.
            return
        }
        let newConfiguration = updateResult.newConfiguration
        let message = OWSDisappearingMessagesConfigurationMessage(configuration: newConfiguration, thread: thread, transaction: transaction)
        sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
    }

    // MARK: - Accept Invites

    public static func localAcceptInviteToGroupV2(
        groupModel: TSGroupModelV2,
        waitForMessageProcessing: Bool = false
    ) -> Promise<TSGroupThread> {
        firstly { () -> Promise<Void> in
            if waitForMessageProcessing {
                return GroupManager.messageProcessingPromise(for: groupModel, description: "Accept invite")
            }

            return Promise.value(())
        }.then { () -> Promise<Void> in
            self.databaseStorage.write(.promise) { transaction in
                self.profileManager.addGroupId(toProfileWhitelist: groupModel.groupId,
                                               userProfileWriter: .localUser,
                                               transaction: transaction)
            }
        }.then(on: DispatchQueue.global()) { _ -> Promise<TSGroupThread> in
            return updateGroupV2(
                groupModel: groupModel,
                description: "Accept invite"
            ) { groupChangeSet in
                groupChangeSet.setLocalShouldAcceptInvite()
            }
        }
    }

    // MARK: - Leave Group / Decline Invite

    public static func localLeaveGroupOrDeclineInvite(
        groupThread: TSGroupThread,
        replacementAdminUuid: UUID? = nil,
        waitForMessageProcessing: Bool = false,
        transaction: SDSAnyWriteTransaction
    ) -> Promise<TSGroupThread> {
        guard groupThread.isGroupV2Thread else {
            owsFail("[GV1] Mutations on V1 groups should be impossible!")
        }

        return localLeaveGroupV2OrDeclineInvite(
            groupThreadId: groupThread.uniqueId,
            replacementAdminUuid: replacementAdminUuid,
            waitForMessageProcessing: waitForMessageProcessing,
            transaction: transaction
        )
    }

    private static func localLeaveGroupV2OrDeclineInvite(
        groupThreadId threadId: String,
        replacementAdminUuid: UUID?,
        waitForMessageProcessing: Bool,
        transaction: SDSAnyWriteTransaction
    ) -> Promise<TSGroupThread> {
        sskJobQueues.localUserLeaveGroupJobQueue.add(
            threadId: threadId,
            replacementAdminUuid: replacementAdminUuid,
            waitForMessageProcessing: waitForMessageProcessing,
            transaction: transaction
        )
    }

    @objc
    public static func leaveGroupOrDeclineInviteAsyncWithoutUI(groupThread: TSGroupThread,
                                                               transaction: SDSAnyWriteTransaction,
                                                               success: (() -> Void)?) {

        guard groupThread.isLocalUserMemberOfAnyKind else {
            owsFailDebug("unexpectedly trying to leave group for which we're not a member.")
            return
        }

        transaction.addAsyncCompletionOffMain {
            firstly {
                databaseStorage.write(.promise) { transaction in
                    self.localLeaveGroupOrDeclineInvite(
                        groupThread: groupThread,
                        transaction: transaction
                    ).asVoid()
                }
            }.done { _ in
                success?()
            }.catch { error in
                owsFailDebug("Leave group failed: \(error)")
            }
        }
    }

    // MARK: - Remove From Group / Revoke Invite

    public static func removeFromGroupOrRevokeInviteV2(groupModel: TSGroupModelV2,
                                                       uuids: [UUID]) -> Promise<TSGroupThread> {
        updateGroupV2(groupModel: groupModel,
                      description: "Remove from group or revoke invite") { groupChangeSet in
            for uuid in uuids {
                owsAssertDebug(!groupModel.groupMembership.isRequestingMember(uuid))

                groupChangeSet.removeMember(uuid)

                // Do not ban when revoking an invite
                if !groupModel.groupMembership.isInvitedMember(uuid) {
                    groupChangeSet.addBannedMember(uuid)
                }
            }
        }
    }

    public static func revokeInvalidInvites(groupModel: TSGroupModelV2) -> Promise<TSGroupThread> {
        updateGroupV2(groupModel: groupModel,
                      description: "Revoke invalid invites") { groupChangeSet in
            groupChangeSet.revokeInvalidInvites()
        }
    }

    // MARK: - Change Member Role

    public static func changeMemberRoleV2(groupModel: TSGroupModelV2,
                                          uuid: UUID,
                                          role: TSGroupMemberRole) -> Promise<TSGroupThread> {
        changeMemberRolesV2(groupModel: groupModel, uuids: [uuid], role: role)
    }

    public static func changeMemberRolesV2(groupModel: TSGroupModelV2,
                                           uuids: [UUID],
                                           role: TSGroupMemberRole) -> Promise<TSGroupThread> {
        updateGroupV2(groupModel: groupModel,
                      description: "Change member role") { groupChangeSet in
            for uuid in uuids {
                groupChangeSet.changeRoleForMember(uuid, role: role)
            }
        }
    }

    // MARK: - Change Group Access

    public static func changeGroupAttributesAccessV2(groupModel: TSGroupModelV2,
                                                     access: GroupV2Access) -> Promise<TSGroupThread> {
        updateGroupV2(groupModel: groupModel,
                      description: "Change group attributes access") { groupChangeSet in
            groupChangeSet.setAccessForAttributes(access)
        }
    }

    public static func changeGroupMembershipAccessV2(groupModel: TSGroupModelV2,
                                                     access: GroupV2Access) -> Promise<TSGroupThread> {
        updateGroupV2(groupModel: groupModel,
                      description: "Change group membership access") { groupChangeSet in
            groupChangeSet.setAccessForMembers(access)
        }
    }

    // MARK: - Group Links

    public static func updateLinkModeV2(groupModel: TSGroupModelV2,
                                        linkMode: GroupsV2LinkMode) -> Promise<TSGroupThread> {
        updateGroupV2(groupModel: groupModel,
                      description: "Change group link mode") { groupChangeSet in
            groupChangeSet.setLinkMode(linkMode)
        }
    }

    public static func resetLinkV2(groupModel: TSGroupModelV2) -> Promise<TSGroupThread> {
        updateGroupV2(groupModel: groupModel,
                      description: "Rotate invite link password") { groupChangeSet in
            groupChangeSet.rotateInviteLinkPassword()
        }
    }

    public static let inviteLinkPasswordLengthV2: UInt = 16

    public static func generateInviteLinkPasswordV2() -> Data {
        Cryptography.generateRandomBytes(inviteLinkPasswordLengthV2)
    }

    public static func groupInviteLink(forGroupModelV2 groupModelV2: TSGroupModelV2) throws -> URL {
        try groupsV2Swift.groupInviteLink(forGroupModelV2: groupModelV2)
    }

    @objc
    public static func isPossibleGroupInviteLink(_ url: URL) -> Bool {
        let possibleHosts: [String]
        if url.scheme == "https" {
            possibleHosts = ["signal.group"]
        } else if url.scheme == "sgnl" {
            possibleHosts = ["signal.group", "joingroup"]
        } else {
            return false
        }
        guard let host = url.host else {
            return false
        }
        return possibleHosts.contains(host)
    }

    @objc
    public static func parseGroupInviteLink(_ url: URL) -> GroupInviteLinkInfo? {
        groupsV2Swift.parseGroupInviteLink(url)
    }

    public static func joinGroupViaInviteLink(groupId: Data,
                                              groupSecretParamsData: Data,
                                              inviteLinkPassword: Data,
                                              groupInviteLinkPreview: GroupInviteLinkPreview,
                                              avatarData: Data?) -> Promise<TSGroupThread> {
        let description = "Join Group Invite Link"

        return firstly(on: DispatchQueue.global()) {
            self.ensureLocalProfileHasCommitmentIfNecessary()
        }.then(on: DispatchQueue.global()) { () throws -> Promise<TSGroupThread> in
            self.groupsV2Swift.joinGroupViaInviteLink(groupId: groupId,
                                                      groupSecretParamsData: groupSecretParamsData,
                                                      inviteLinkPassword: inviteLinkPassword,
                                                      groupInviteLinkPreview: groupInviteLinkPreview,
                                                      avatarData: avatarData)
        }.map(on: DispatchQueue.global()) { (groupThread: TSGroupThread) -> TSGroupThread in
            self.databaseStorage.write { transaction in
                self.profileManager.addGroupId(toProfileWhitelist: groupId,
                                               userProfileWriter: .localUser,
                                               transaction: transaction)
            }
            return groupThread
        }.timeout(seconds: Self.groupUpdateTimeoutDuration, description: description) {
            GroupsV2Error.timeout
        }
    }

    public static func acceptOrDenyMemberRequestsV2(groupModel: TSGroupModelV2,
                                                    uuids: [UUID],
                                                    shouldAccept: Bool) -> Promise<TSGroupThread> {
        let description = (shouldAccept
                            ? "Accept group member request"
                            : "Deny group member request")
        return updateGroupV2(groupModel: groupModel,
                             description: description) { groupChangeSet in
            for uuid in uuids {
                if shouldAccept {
                    groupChangeSet.addMember(uuid, role: .`normal`)
                } else {
                    groupChangeSet.removeMember(uuid)
                    groupChangeSet.addBannedMember(uuid)
                }
            }
        }
    }

    public static func cancelMemberRequestsV2(groupModel: TSGroupModelV2) -> Promise<TSGroupThread> {

        let description = "Cancel Member Request"

        return firstly(on: DispatchQueue.global()) {
            self.groupsV2Swift.cancelMemberRequests(groupModel: groupModel)
        }.timeout(seconds: Self.groupUpdateTimeoutDuration, description: description) {
            GroupsV2Error.timeout
        }
    }

    @objc
    public static func cachedGroupInviteLinkPreview(groupInviteLinkInfo: GroupInviteLinkInfo) -> GroupInviteLinkPreview? {
        do {
            let groupContextInfo = try self.groupsV2Swift.groupV2ContextInfo(forMasterKeyData: groupInviteLinkInfo.masterKey)
            return groupsV2Swift.cachedGroupInviteLinkPreview(groupSecretParamsData: groupContextInfo.groupSecretParamsData)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    // MARK: - Announcements

    public static func setIsAnnouncementsOnly(groupModel: TSGroupModelV2,
                                              isAnnouncementsOnly: Bool) -> Promise<TSGroupThread> {
        updateGroupV2(groupModel: groupModel,
                      description: "Update isAnnouncementsOnly") { groupChangeSet in
            groupChangeSet.setIsAnnouncementsOnly(isAnnouncementsOnly)
        }
    }

    // MARK: - Local profile key

    public static func updateLocalProfileKey(groupModel: TSGroupModelV2) -> Promise<TSGroupThread> {
        updateGroupV2(groupModel: groupModel, description: "Update local profile key") { changes in
            changes.setShouldUpdateLocalProfileKey()
        }
    }

    // MARK: - Removed from Group or Invite Revoked

    public static func handleNotInGroup(groupId: Data,
                                        transaction: SDSAnyWriteTransaction) {
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return
        }
        guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            // Local user may have just deleted the thread via the UI.
            // Or we maybe be trying to restore a group from storage service
            // that we are no longer a member of.
            Logger.warn("Missing group in database.")
            return
        }

        let groupModel = groupThread.groupModel

        let removeLocalUserBlock: (SDSAnyWriteTransaction) -> Void = { transaction in
            // Remove local user from group.
            // We do _not_ bump the revision number since this (unlike all other
            // changes to group state) is inferred from a 403. This is fine; if
            // we're ever re-added to the group the groups v2 machinery will
            // recover.
            var groupMembershipBuilder = groupModel.groupMembership.asBuilder
            groupMembershipBuilder.remove(localAddress)
            var groupModelBuilder = groupModel.asBuilder
            do {
                groupModelBuilder.groupMembership = groupMembershipBuilder.build()
                let newGroupModel = try groupModelBuilder.build()

                // groupUpdateSourceAddress is nil because we don't (and can't) know who
                // removed us or revoked our invite.
                //
                // newDisappearingMessageToken is nil because we don't want to change
                // DM state.
                _ = try updateExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                newDisappearingMessageToken: nil,
                                                                                newlyLearnedPniToAciAssociations: [:],
                                                                                groupUpdateSourceAddress: nil,
                                                                                infoMessagePolicy: .always,
                                                                                transaction: transaction)
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }

        if let groupModelV2 = groupModel as? TSGroupModelV2,
           groupModelV2.isPlaceholderModel {
            Logger.warn("Ignoring 403 for placeholder group.")
            groupsV2Swift.tryToUpdatePlaceholderGroupModelUsingInviteLinkPreview(
                groupModel: groupModelV2,
                removeLocalUserBlock: removeLocalUserBlock
            )
        } else {
            removeLocalUserBlock(transaction)
        }
    }

    // MARK: - Messages

    public static func sendGroupUpdateMessage(thread: TSGroupThread,
                                              changeActionsProtoData: Data? = nil) -> Promise<Void> {
        guard thread.isGroupV2Thread else {
            owsFail("[GV1] Should be impossible to send V1 group messages!")
        }

        return databaseStorage.write(.promise) { transaction in
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore

            let message = OutgoingGroupUpdateMessage(
                in: thread,
                groupMetaMessage: .update,
                expiresInSeconds: dmConfigurationStore.durationSeconds(for: thread, tx: transaction.asV2Read),
                changeActionsProtoData: changeActionsProtoData,
                additionalRecipients: Self.invitedMembers(in: thread),
                transaction: transaction
            )

            Self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
        }
    }

    private static func sendDurableNewGroupMessage(forThread thread: TSGroupThread) -> Promise<Void> {
        guard thread.isGroupV2Thread else {
            owsFail("[GV1] Should be impossible to send V1 group messages!")
        }

        return databaseStorage.write(.promise) { tx in
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let message = OutgoingGroupUpdateMessage(
                in: thread,
                groupMetaMessage: .new,
                expiresInSeconds: dmConfigurationStore.durationSeconds(for: thread, tx: tx.asV2Read),
                additionalRecipients: Self.invitedMembers(in: thread),
                transaction: tx
            )
            Self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: tx)
        }
    }

    private static func invitedMembers(in thread: TSGroupThread) -> Set<SignalServiceAddress> {
        thread.groupModel.groupMembership.invitedMembers.filter { doesUserSupportGroupsV2(address: $0) }
    }

    private static func invitedOrRequestedMembers(in thread: TSGroupThread) -> Set<SignalServiceAddress> {
        thread.groupModel.groupMembership.invitedOrRequestMembers.filter { doesUserSupportGroupsV2(address: $0) }
    }

    @objc
    public static func shouldMessageHaveAdditionalRecipients(_ message: TSOutgoingMessage,
                                                             groupThread: TSGroupThread) -> Bool {
        guard groupThread.groupModel.groupsVersion == .V2 else {
            return false
        }
        switch message.groupMetaMessage {
        case .update, .new:
            return true
        default:
            return false
        }
    }

    // MARK: - Group Database

    @objc
    public enum InfoMessagePolicy: UInt {
        case always
        case insertsOnly
        case updatesOnly
        case never
    }

    // If disappearingMessageToken is nil, don't update the disappearing messages configuration.
    public static func insertGroupThreadInDatabaseAndCreateInfoMessage(groupModel: TSGroupModel,
                                                                       disappearingMessageToken: DisappearingMessageToken?,
                                                                       groupUpdateSourceAddress: SignalServiceAddress?,
                                                                       shouldAttributeAuthor: Bool,
                                                                       infoMessagePolicy: InfoMessagePolicy = .always,
                                                                       transaction: SDSAnyWriteTransaction) -> TSGroupThread {

        if let groupThread = TSGroupThread.fetch(groupId: groupModel.groupId, transaction: transaction) {
            owsFail("Inserting existing group thread: \(groupThread.uniqueId).")
        }

        let groupThread = TSGroupThread(groupModelPrivate: groupModel,
                                        transaction: transaction)
        groupThread.anyInsert(transaction: transaction)

        TSGroupThread.setGroupIdMapping(groupThread.uniqueId,
                                        forGroupId: groupModel.groupId,
                                        transaction: transaction)

        let sourceAddress: SignalServiceAddress? = (shouldAttributeAuthor
                                                        ? groupUpdateSourceAddress
                                                        : nil)

        let newDisappearingMessageToken = disappearingMessageToken ?? DisappearingMessageToken.disabledToken
        _ = updateDisappearingMessagesInDatabaseAndCreateMessages(token: newDisappearingMessageToken,
                                                                  thread: groupThread,
                                                                  shouldInsertInfoMessage: false,
                                                                  groupUpdateSourceAddress: sourceAddress,
                                                                  transaction: transaction)

        autoWhitelistGroupIfNecessary(oldGroupModel: nil,
                                      newGroupModel: groupModel,
                                      groupUpdateSourceAddress: groupUpdateSourceAddress,
                                      transaction: transaction)

        switch infoMessagePolicy {
        case .always, .insertsOnly:
            insertGroupUpdateInfoMessage(groupThread: groupThread,
                                         oldGroupModel: nil,
                                         newGroupModel: groupModel,
                                         oldDisappearingMessageToken: nil,
                                         newDisappearingMessageToken: newDisappearingMessageToken,
                                         newlyLearnedPniToAciAssociations: [:],
                                         groupUpdateSourceAddress: sourceAddress,
                                         transaction: transaction)
        default:
            break
        }

        notifyStorageServiceOfInsertedGroup(groupModel: groupModel,
                                            transaction: transaction)

        return groupThread
    }

    /// Update persisted group-related state for the provided models, or insert
    /// it if this group does not already exist. If appropriate, inserts an info
    /// message into the group thread describing what has changed about the
    /// group.
    ///
    /// - Parameter newlyLearnedPniToAciAssociations
    /// Associations between PNIs and ACIs that were learned as a result of this
    /// group update.
    public static func tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(
        newGroupModel: TSGroupModel,
        newDisappearingMessageToken: DisappearingMessageToken?,
        newlyLearnedPniToAciAssociations: [ServiceId: ServiceId],
        groupUpdateSourceAddress: SignalServiceAddress?,
        canInsert: Bool,
        didAddLocalUserToV2Group: Bool,
        infoMessagePolicy: InfoMessagePolicy = .always,
        transaction: SDSAnyWriteTransaction
    ) throws -> UpsertGroupResult {

        TSGroupThread.ensureGroupIdMapping(forGroupId: newGroupModel.groupId,
                                           transaction: transaction)

        let threadId = TSGroupThread.threadId(forGroupId: newGroupModel.groupId,
                                              transaction: transaction)

        guard TSGroupThread.anyExists(uniqueId: threadId, transaction: transaction) else {
            guard canInsert else {
                throw OWSAssertionError("Missing groupThread.")
            }

            // When inserting a v2 group into the database for the
            // first time, we don't want to attribute all of the group
            // state to the author of the most recent revision.
            //
            // We only want to attribute the changes if we've just been
            // added, so that we can say "Alice added you to the group,"
            // etc.
            var shouldAttributeAuthor = true
            if newGroupModel.groupsVersion == .V2 {
                if let localAddress = tsAccountManager.localAddress,
                   newGroupModel.groupMembers.contains(localAddress),
                   didAddLocalUserToV2Group {
                    // Do attribute.
                } else {
                    // Don't attribute.
                    shouldAttributeAuthor = false
                }
            }

            let thread = insertGroupThreadInDatabaseAndCreateInfoMessage(groupModel: newGroupModel,
                                                                         disappearingMessageToken: newDisappearingMessageToken,
                                                                         groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                         shouldAttributeAuthor: shouldAttributeAuthor,
                                                                         infoMessagePolicy: infoMessagePolicy,
                                                                         transaction: transaction)

            return UpsertGroupResult(action: .inserted, groupThread: thread)
        }

        return try updateExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                           newDisappearingMessageToken: newDisappearingMessageToken,
                                                                           newlyLearnedPniToAciAssociations: newlyLearnedPniToAciAssociations,
                                                                           groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                           infoMessagePolicy: infoMessagePolicy,
                                                                           transaction: transaction)
    }

    /// Update persisted group-related state for the provided models. If
    /// appropriate, inserts an info message into the group thread describing
    /// what has changed about the group.
    ///
    /// - Parameter newlyLearnedPniToAciAssociations
    /// Associations between PNIs and ACIs that were learned as a result of this
    /// group update.
    public static func updateExistingGroupThreadInDatabaseAndCreateInfoMessage(
        newGroupModel: TSGroupModel,
        newDisappearingMessageToken: DisappearingMessageToken?,
        newlyLearnedPniToAciAssociations: [ServiceId: ServiceId],
        groupUpdateSourceAddress: SignalServiceAddress?,
        infoMessagePolicy: InfoMessagePolicy = .always,
        transaction: SDSAnyWriteTransaction
    ) throws -> UpsertGroupResult {

        // Step 1: First reload latest thread state. This ensures:
        //
        // * The thread (still) exists in the database.
        // * The update is working off latest database state.
        //
        // We always have the groupThread at the call sites of this method, but this
        // future-proofs us against bugs.
        let groupId = newGroupModel.groupId
        guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            throw OWSAssertionError("Missing groupThread.")
        }

        // Step 2: Update DM configuration in database, if necessary.
        let updateDMResult: UpdateDMConfigurationResult
        if let newDisappearingMessageToken = newDisappearingMessageToken {
            // shouldInsertInfoMessage is false because we only want to insert a
            // single info message if we update both DM config and thread model.
            updateDMResult = updateDisappearingMessagesInDatabaseAndCreateMessages(token: newDisappearingMessageToken,
                                                                                   thread: groupThread,
                                                                                   shouldInsertInfoMessage: false,
                                                                                   groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                   transaction: transaction)
        } else {
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let dmConfiguration = dmConfigurationStore.fetchOrBuildDefault(for: .thread(groupThread), tx: transaction.asV2Read)
            updateDMResult = UpdateDMConfigurationResult(oldConfiguration: dmConfiguration, newConfiguration: dmConfiguration)
        }

        // Step 3: If any member was removed, make sure we rotate our sender key session
        let oldGroupModel = groupThread.groupModel
        if let newGroupModelV2 = newGroupModel as? TSGroupModelV2,
           let oldGroupModelV2 = oldGroupModel as? TSGroupModelV2 {

            let oldMembers = oldGroupModelV2.membership.allMembersOfAnyKind
            let newMembers = newGroupModelV2.membership.allMembersOfAnyKind

            if oldMembers.subtracting(newMembers).isEmpty == false {
                senderKeyStore.resetSenderKeySession(for: groupThread, transaction: transaction)
            }
        }

        // Step 4: Update group in database, if necessary.
        let updateThreadResult: UpsertGroupResult = {
            if let newGroupModelV2 = newGroupModel as? TSGroupModelV2,
               let oldGroupModelV2 = oldGroupModel as? TSGroupModelV2 {
                guard newGroupModelV2.revision >= oldGroupModelV2.revision else {
                    // This is a key check.  We never want to revert group state
                    // in the database to an earlier revision. Races are
                    // unavoidable: there are multiple triggers for group updates
                    // and some of them require interacting with the service.
                    // Ultimately it is safe to ignore stale writes and treat
                    // them as successful.
                    //
                    // NOTE: As always, we return the group thread with the
                    // latest group state.
                    Logger.warn("Skipping stale update for v2 group.")
                    return UpsertGroupResult(action: .unchanged, groupThread: groupThread)
                }
            }

            guard !oldGroupModel.isEqual(to: newGroupModel, comparisonMode: .compareAll) else {
                // Skip redundant update.
                return UpsertGroupResult(action: .unchanged, groupThread: groupThread)
            }

            let hasUserFacingChange = !oldGroupModel.isEqual(to: newGroupModel,
                                                             comparisonMode: .userFacingOnly)

            autoWhitelistGroupIfNecessary(oldGroupModel: oldGroupModel,
                                          newGroupModel: newGroupModel,
                                          groupUpdateSourceAddress: groupUpdateSourceAddress,
                                          transaction: transaction)

            TSGroupThread.ensureGroupIdMapping(forGroupId: newGroupModel.groupId, transaction: transaction)

            groupThread.update(with: newGroupModel, transaction: transaction)

            let action: UpsertGroupResult.Action = (hasUserFacingChange
                                                        ? .updatedWithUserFacingChanges
                                                        : .updatedWithoutUserFacingChanges)
            return UpsertGroupResult(action: action, groupThread: groupThread)
        }()

        let hadUserFacingChanges: Bool = {
            if updateDMResult.newConfiguration != updateDMResult.oldConfiguration {
                return true
            }
            switch updateThreadResult.action {
            case .inserted, .updatedWithUserFacingChanges:
                return true
            case .unchanged, .updatedWithoutUserFacingChanges:
                break
            }
            return false
        }()

        guard hadUserFacingChanges else {
            // Neither DM config nor thread model had user-facing changes.
            return updateThreadResult
        }

        switch infoMessagePolicy {
        case .always, .updatesOnly:
            insertGroupUpdateInfoMessage(
                groupThread: groupThread,
                oldGroupModel: oldGroupModel,
                newGroupModel: newGroupModel,
                oldDisappearingMessageToken: updateDMResult.oldConfiguration.asToken,
                newDisappearingMessageToken: updateDMResult.newConfiguration.asToken,
                newlyLearnedPniToAciAssociations: newlyLearnedPniToAciAssociations,
                groupUpdateSourceAddress: groupUpdateSourceAddress,
                transaction: transaction
            )
        default:
            break
        }

        return UpsertGroupResult(action: .updatedWithUserFacingChanges, groupThread: groupThread)
    }

    // MARK: - Storage Service

    private static func notifyStorageServiceOfInsertedGroup(groupModel: TSGroupModel,
                                                            transaction: SDSAnyReadTransaction) {
        guard let groupModel = groupModel as? TSGroupModelV2 else {
            // We only need to notify the storage service about v2 groups.
            return
        }
        guard !groupsV2Swift.isGroupKnownToStorageService(groupModel: groupModel,
                                                          transaction: transaction) else {
            // To avoid redundant storage service writes,
            // don't bother notifying the storage service
            // about v2 groups it already knows about.
            return
        }

        storageServiceManager.recordPendingUpdates(groupModel: groupModel)
    }

    // MARK: - Profiles

    private static func autoWhitelistGroupIfNecessary(oldGroupModel: TSGroupModel?,
                                                      newGroupModel: TSGroupModel,
                                                      groupUpdateSourceAddress: SignalServiceAddress?,
                                                      transaction: SDSAnyWriteTransaction) {

        guard wasLocalUserJustAddedToTheGroup(oldGroupModel: oldGroupModel,
                                              newGroupModel: newGroupModel) else {
            if DebugFlags.internalLogging {
                Logger.verbose("Local user was not just added to the group.")
            }
            return
        }

        guard let groupUpdateSourceAddress = groupUpdateSourceAddress else {
            if DebugFlags.internalLogging {
                Logger.info("No groupUpdateSourceAddress.")
            }
            return
        }

        let isLocalAddress = groupUpdateSourceAddress.isLocalAddress
        let isSystemContact = contactsManager.isSystemContact(address: groupUpdateSourceAddress,
                                                              transaction: transaction)
        let isUserInProfileWhitelist = profileManager.isUser(inProfileWhitelist: groupUpdateSourceAddress,
                                                             transaction: transaction)
        let shouldAddToWhitelist = (isLocalAddress || isSystemContact || isUserInProfileWhitelist)
        guard shouldAddToWhitelist else {
            if DebugFlags.internalLogging {
                Logger.info("Not adding to whitelist. groupUpdateSourceAddress: \(groupUpdateSourceAddress), isLocalAddress: \(isLocalAddress), isSystemContact: \(isSystemContact), isUserInProfileWhitelists: \(isUserInProfileWhitelist), ")
            }
            return
        }

        if DebugFlags.internalLogging {
            Logger.info("Adding to whitelist")
        }

        // Ensure the thread is in our profile whitelist if we're a member of the group.
        // We don't want to do this if we're just a pending member or are leaving/have
        // already left the group.
        self.profileManager.addGroupId(toProfileWhitelist: newGroupModel.groupId,
                                       userProfileWriter: .localUser,
                                       transaction: transaction)
    }

    private static func wasLocalUserJustAddedToTheGroup(oldGroupModel: TSGroupModel?,
                                                        newGroupModel: TSGroupModel) -> Bool {

        guard let localAddress = self.tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return false
        }
        if let oldGroupModel = oldGroupModel {
            guard !oldGroupModel.groupMembership.isFullMember(localAddress) else {
                // Local user already was a member.
                return false
            }
        }
        guard newGroupModel.groupMembership.isFullMember(localAddress) else {
            // Local user is not a member.
            return false
        }
        return true
    }

    // MARK: -

    @objc
    public static func storeProfileKeysFromGroupProtos(_ profileKeysByUuid: [UUID: Data]) {
        var profileKeysByAddress = [SignalServiceAddress: Data]()
        for (uuid, profileKeyData) in profileKeysByUuid {
            profileKeysByAddress[SignalServiceAddress(uuid: uuid)] = profileKeyData
        }
        // If we receive a profile key from a user, that's "authoritative" and
        // can discard and previous key from them.
        //
        // However, if we learn of a user's profile key from v2 group protos,
        // it might be stale.  E.g. maybe they were added by someone who
        // doesn't know their new profile key.  So we only want to fill in
        // missing keys, not overwrite any existing keys.
        profileManager.fillInMissingProfileKeys(profileKeysByAddress, userProfileWriter: .groupState, authedAccount: .implicit())
    }

    /// Ensure that we have a profile key commitment for our local profile
    /// available on the service.
    ///
    /// We (and other clients) need profile key credentials for group members in
    /// order to perform GV2 operations. However, other clients can't request
    /// our profile key credential from the service until we've uploaded a profile
    /// key commitment to the service.
    public static func ensureLocalProfileHasCommitmentIfNecessary() -> Promise<Void> {
        guard tsAccountManager.isOnboarded else {
            return Promise.value(())
        }
        guard let localAddress = self.tsAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Missing localAddress."))
        }

        return databaseStorage.read(.promise) { transaction -> Bool in
            return self.groupsV2Swift.hasProfileKeyCredential(for: localAddress,
                                                              transaction: transaction)
        }.then(on: DispatchQueue.global()) { hasLocalCredential -> Promise<Void> in
            guard !hasLocalCredential else {
                return .value(())
            }

            // If we don't have a local profile key credential we should first
            // check if it is simply expired, by asking for a new one (which we
            // would get as part of fetching our local profile).
            return self.profileManager.fetchLocalUsersProfilePromise(authedAccount: .implicit()).asVoid()
        }.then(on: DispatchQueue.global()) { () -> Promise<Void> in
            let hasProfileKeyCredentialAfterRefresh = databaseStorage.read { transaction in
                self.groupsV2Swift.hasProfileKeyCredential(for: localAddress, transaction: transaction)
            }

            if hasProfileKeyCredentialAfterRefresh {
                // We successfully refreshed our profile key credential, which
                // means we have previously uploaded a commitment, and all is
                // well.
                return .value(())
            }

            guard
                tsAccountManager.isRegisteredPrimaryDevice,
                CurrentAppContext().isMainApp
            else {
                Logger.warn("Skipping upload of local profile key commitment, not in main app!")
                return .value(())
            }

            // We've never uploaded a profile key commitment - do so now.
            Logger.info("No profile key credential available for local account - uploading local profile!")
            return self.groupsV2Swift.reuploadLocalProfilePromise()
        }
    }

    // MARK: - Network Errors

    static func isNetworkFailureOrTimeout(_ error: Error) -> Bool {
        if error.isNetworkConnectivityFailure {
            return true
        }

        switch error {
        case GroupsV2Error.timeout:
            return true
        default:
            return false
        }
    }
}

// MARK: -

public extension GroupManager {
    class func messageProcessingPromise(for thread: TSThread,
                                        description: String) -> Promise<Void> {
        guard thread.isGroupV2Thread else {
            return Promise.value(())
        }

        return messageProcessingPromise(description: description)
    }

    class func messageProcessingPromise(for groupModel: TSGroupModel,
                                        description: String) -> Promise<Void> {
        guard groupModel.groupsVersion == .V2 else {
            return Promise.value(())
        }

        return messageProcessingPromise(description: description)
    }

    private class func messageProcessingPromise(description: String) -> Promise<Void> {
        return firstly {
            self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                  description: description) {
            GroupsV2Error.timeout
        }
    }
}

// MARK: -

public extension Error {
    var isNetworkFailureOrTimeout: Bool {
        return GroupManager.isNetworkFailureOrTimeout(self)
    }
}

// MARK: - Add/Invite to group

extension GroupManager {
    public static func addOrInvite(
        aciOrPniUuids: [UUID],
        toExistingGroup existingGroupModel: TSGroupModel
    ) -> Promise<TSGroupThread> {
        guard let existingGroupModel = existingGroupModel as? TSGroupModelV2 else {
            owsFail("[GV1] Mutations on V1 groups should be impossible!")
        }

        return firstly { () -> Promise<Void> in
            // Ensure we have fetched profile key credentials before performing
            // the add below, since we depend on credential state to decide
            // whether to add or invite a user.

            self.groupsV2Swift.tryToFetchProfileKeyCredentials(
                for: aciOrPniUuids,
                ignoreMissingProfiles: false,
                forceRefresh: false
            )
        }.then(on: DispatchQueue.global()) { () -> Promise<TSGroupThread> in
            updateGroupV2(
                groupModel: existingGroupModel,
                description: "Add/Invite new non-admin members"
            ) { groupChangeSet in
                self.databaseStorage.read { transaction in
                    for uuid in aciOrPniUuids {
                        owsAssertDebug(!existingGroupModel.groupMembership.isMemberOfAnyKind(uuid))

                        // Important that at this point we already have the
                        // profile keys for these users
                        let isPending = !self.groupsV2Swift.hasProfileKeyCredential(
                            for: SignalServiceAddress(uuid: uuid),
                            transaction: transaction
                        )

                        if isPending {
                            groupChangeSet.addInvitedMember(uuid, role: .normal)
                        } else {
                            groupChangeSet.addMember(uuid, role: .normal)
                        }

                        if existingGroupModel.groupMembership.isBannedMember(uuid) {
                            groupChangeSet.removeBannedMember(uuid)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Update attributes

extension GroupManager {
    public static func updateGroupAttributes(
        title: String?,
        description: String?,
        avatarData: Data?,
        inExistingGroup existingGroupModel: TSGroupModel
    ) -> Promise<TSGroupThread> {
        guard let existingGroupModel = existingGroupModel as? TSGroupModelV2 else {
            owsFail("[GV1] Mutations on V1 groups should be impossible!")
        }

        return firstly(on: DispatchQueue.global()) { () -> Promise<String?> in
            guard let avatarData = avatarData else {
                return .value(nil)
            }

            // Skip upload if the new avatar data is the same as the existing
            if
                let existingAvatarHash = existingGroupModel.avatarHash,
                try existingAvatarHash == TSGroupModel.hash(forAvatarData: avatarData)
            {
                return .value(nil)
            }

            return self.groupsV2Swift.uploadGroupAvatar(
                avatarData: avatarData,
                groupSecretParamsData: existingGroupModel.secretParamsData
            ).map { Optional.some($0) }
        }.then(on: DispatchQueue.global()) { (avatarUrlPath: String?) -> Promise<TSGroupThread> in
            var message = "Update attributes:"
            message += title != nil ? " title" : ""
            message += description != nil ? " description" : ""
            message += avatarData != nil ? " settingAvatarData" : " clearingAvatarData"

            return self.updateGroupV2(
                groupModel: existingGroupModel,
                description: message
            ) { groupChangeSet in
                if
                    let title = title?.ows_stripped(),
                    title != existingGroupModel.groupName
                {
                    groupChangeSet.setTitle(title)
                }

                if
                    let description = description?.ows_stripped(),
                    description != existingGroupModel.descriptionText
                {
                    groupChangeSet.setDescriptionText(description)
                } else if
                    description == nil,
                    existingGroupModel.descriptionText != nil
                {
                    groupChangeSet.setDescriptionText(nil)
                }

                // Having a URL from the previous step means this data
                // represents a new avatar, which we have already uploaded.
                if
                    let avatarData = avatarData,
                    let avatarUrlPath = avatarUrlPath
                {
                    groupChangeSet.setAvatar((data: avatarData, urlPath: avatarUrlPath))
                } else if
                    avatarData == nil,
                    existingGroupModel.avatarData != nil
                {
                    groupChangeSet.setAvatar(nil)
                }
            }
        }
    }
}
