//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

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
        return RemoteConfig.current.groupsV2MaxGroupSizeRecommended
    }

    public static var groupsV2MaxGroupSizeHardLimit: UInt {
        return RemoteConfig.current.groupsV2MaxGroupSizeHardLimit
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

    static func groupIdLength(for groupsVersion: GroupsVersion) -> UInt {
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

    public static func canLocalUserLeaveGroupWithoutChoosingNewAdmin(
        localAci: Aci,
        groupMembership: GroupMembership
    ) -> Bool {
        let fullMembers = Set(groupMembership.fullMembers.compactMap { $0.serviceId as? Aci })
        let fullMemberAdmins = Set(groupMembership.fullMemberAdministrators.compactMap { $0.serviceId as? Aci })
        return canLocalUserLeaveGroupWithoutChoosingNewAdmin(
            localAci: localAci,
            fullMembers: fullMembers,
            admins: fullMemberAdmins
        )
    }

    public static func canLocalUserLeaveGroupWithoutChoosingNewAdmin(
        localAci: Aci,
        fullMembers: Set<Aci>,
        admins: Set<Aci>
    ) -> Bool {
        // If the current user is the only admin and they're not the only member of
        // the group, then they must select a new admin.
        if Set([localAci]) == admins && Set([localAci]) != fullMembers {
            return false
        }
        return true
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

        guard address.serviceId != nil else {
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
    public static func localCreateNewGroup(
        members membersParam: [SignalServiceAddress],
        groupId: Data? = nil,
        name: String? = nil,
        avatarData: Data? = nil,
        disappearingMessageToken: DisappearingMessageToken,
        newGroupSeed: NewGroupSeed? = nil,
        shouldSendMessage: Bool
    ) async throws -> TSGroupThread {
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            throw OWSAssertionError("Missing localIdentifiers.")
        }

        try await ensureLocalProfileHasCommitmentIfNecessary()

        // Build member list.
        //
        // The group creator is an administrator;
        // the other members are normal users.
        var builder = GroupMembership.Builder()
        builder.addFullMembers(Set(membersParam), role: .normal)
        builder.remove(localIdentifiers.aci)
        builder.addFullMember(localIdentifiers.aci, role: .administrator)
        let initialGroupMembership = builder.build()

        // Try to get profile key credentials for all group members, since
        // we need them to fully add (rather than merely inviting) members.
        try await SSKEnvironment.shared.groupsV2Ref.tryToFetchProfileKeyCredentials(
            for: initialGroupMembership.allMembersOfAnyKind.compactMap { $0.serviceId as? Aci },
            ignoreMissingProfiles: false,
            forceRefresh: false
        )

        let groupAccess = GroupAccess.defaultForV2
        let separatedGroupMembership = SSKEnvironment.shared.databaseStorageRef.read { tx in
            // Before we create the group, we need to separate out the
            // pending and full members.
            return separateInvitedMembersForNewGroup(
                withMembership: initialGroupMembership,
                transaction: tx
            )
        }

        guard separatedGroupMembership.isFullMember(localIdentifiers.aci) else {
            throw OWSAssertionError("Local ACI is missing from group membership.")
        }

        // The avatar URL path will be filled in later.
        var groupModelBuilder = TSGroupModelBuilder()
        groupModelBuilder.groupId = groupId
        groupModelBuilder.name = name
        groupModelBuilder.avatarData = avatarData
        groupModelBuilder.avatarUrlPath = nil
        groupModelBuilder.groupMembership = separatedGroupMembership
        groupModelBuilder.groupAccess = groupAccess
        groupModelBuilder.newGroupSeed = newGroupSeed
        var proposedGroupModel = try groupModelBuilder.buildAsV2()

        if let avatarData = avatarData {
            // Upload avatar.
            let avatarUrlPath = try await SSKEnvironment.shared.groupsV2Ref.uploadGroupAvatar(
                avatarData: avatarData,
                groupSecretParams: try proposedGroupModel.secretParams()
            )

            // Fill in the avatarUrl on the group model.
            var builder = proposedGroupModel.asBuilder
            builder.avatarUrlPath = avatarUrlPath
            proposedGroupModel = try builder.buildAsV2()
        }

        let snapshotResponse = try await SSKEnvironment.shared.groupsV2Ref.createNewGroupOnService(
            groupModel: proposedGroupModel,
            disappearingMessageToken: disappearingMessageToken
        )

        let thread = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            let builder = try TSGroupModelBuilder.builderForSnapshot(
                groupV2Snapshot: snapshotResponse.groupSnapshot,
                transaction: tx
            )
            let groupModel = try builder.buildAsV2()

            let thread = self.insertGroupThreadInDatabaseAndCreateInfoMessage(
                groupModel: groupModel,
                disappearingMessageToken: disappearingMessageToken,
                groupUpdateSource: .localUser(originalSource: .aci(localIdentifiers.aci)),
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: .createdByLocalAction,
                transaction: tx
            )
            SSKEnvironment.shared.profileManagerRef.addThread(
                toProfileWhitelist: thread,
                userProfileWriter: .localUser,
                transaction: tx
            )
            return thread
        }

        if shouldSendMessage {
            await sendDurableNewGroupMessage(forThread: thread)
        }
        return thread
    }

    // Separates pending and non-pending members.
    // We cannot add non-pending members unless:
    //
    // * We know their profile key.
    // * We have a profile key credential for them.
    private static func separateInvitedMembersForNewGroup(
        withMembership newGroupMembership: GroupMembership,
        transaction tx: SDSAnyReadTransaction
    ) -> GroupMembership {
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci else {
            owsFailDebug("Missing localAci.")
            return newGroupMembership
        }
        var builder = GroupMembership.Builder()

        let newMembers = newGroupMembership.allMembersOfAnyKind

        // We only need to separate new members.
        for address in newMembers {
            // We must call this _after_ we try to fetch profile key credentials for
            // all members.
            let hasCredential = SSKEnvironment.shared.groupsV2Ref.hasProfileKeyCredential(for: address, transaction: tx)
            guard let role = newGroupMembership.role(for: address) else {
                owsFailDebug("Missing role: \(address)")
                continue
            }

            guard let serviceId = address.serviceId else {
                owsFailDebug("Missing serviceId.")
                continue
            }

            if let aci = serviceId as? Aci, hasCredential {
                builder.addFullMember(aci, role: role)
            } else {
                builder.addInvitedMember(serviceId, role: role, addedByAci: localAci)
            }
        }
        return builder.build()
    }

    // MARK: - Tests

    #if TESTABLE_BUILD

    /// Create a group for testing purposes.
    ///
    /// - Parameter shouldInsertInfoMessage
    /// Whether an info message describing this group's creation should be
    /// inserted in the to-be-created thread corresponding to the group. If
    /// `true`, the local user must be a member of the group.
    public static func createGroupForTests(members: [SignalServiceAddress],
                                           shouldInsertInfoMessage: Bool = false,
                                           name: String? = nil,
                                           descriptionText: String? = nil,
                                           avatarData: Data? = nil,
                                           groupId: Data? = nil,
                                           transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {

        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else {
            throw OWSAssertionError("Missing localIdentifiers.")
        }

        // GroupsV2 TODO: Elaborate tests to include admins, pending members, etc.
        // GroupsV2 TODO: Let tests specify access levels.
        // GroupsV2 TODO: Fill in avatarUrlPath when we test v2 groups.

        var builder = TSGroupModelBuilder()
        builder.groupId = groupId
        builder.name = name
        builder.descriptionText = descriptionText
        builder.avatarData = avatarData
        builder.avatarUrlPath = nil
        builder.groupMembership = GroupMembership(membersForTest: members)
        builder.groupAccess = .defaultForV2
        let groupModel = try builder.buildAsV2()

        // Just create it in the database, don't create it on the service.
        return try remoteUpsertExistingGroupForTests(
            groupModel: groupModel,
            disappearingMessageToken: nil,
            groupUpdateSource: .localUser(originalSource: .aci(localIdentifiers.aci)),
            infoMessagePolicy: shouldInsertInfoMessage ? .always : .never,
            localIdentifiers: localIdentifiers,
            transaction: transaction
        )
    }

    // If disappearingMessageToken is nil, don't update the disappearing messages configuration.
    private static func remoteUpsertExistingGroupForTests(
        groupModel: TSGroupModelV2,
        disappearingMessageToken: DisappearingMessageToken?,
        groupUpdateSource: GroupUpdateSource,
        infoMessagePolicy: InfoMessagePolicy = .always,
        localIdentifiers: LocalIdentifiers,
        transaction: SDSAnyWriteTransaction
    ) throws -> TSGroupThread {
        return try self.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(
            newGroupModel: groupModel,
            newDisappearingMessageToken: disappearingMessageToken,
            newlyLearnedPniToAciAssociations: [:],
            groupUpdateSource: groupUpdateSource,
            didAddLocalUserToV2Group: false,
            infoMessagePolicy: infoMessagePolicy,
            localIdentifiers: localIdentifiers,
            spamReportingMetadata: .unreportable,
            transaction: transaction
        )
    }

    #endif

    // MARK: - Disappearing Messages for group threads

    private static func updateDisappearingMessageConfiguration(
        newToken: DisappearingMessageToken,
        groupThread: TSGroupThread,
        tx: SDSAnyWriteTransaction
    ) -> DisappearingMessagesConfigurationStore.SetTokenResult {
        let setTokenResult = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            .set(token: newToken, for: groupThread, tx: tx.asV2Write)

        if setTokenResult.newConfiguration != setTokenResult.oldConfiguration {
            SSKEnvironment.shared.databaseStorageRef.touch(thread: groupThread, shouldReindex: false, transaction: tx)
        }

        return setTokenResult
    }

    // MARK: - Disappearing Messages for contact threads (for whatever reason, historically part of GroupManager)

    public static func remoteUpdateDisappearingMessages(
        contactThread: TSContactThread,
        disappearingMessageToken: VersionedDisappearingMessageToken,
        changeAuthor: Aci?,
        localIdentifiers: LocalIdentifiers,
        transaction: SDSAnyWriteTransaction
    ) {
        _ = self.updateDisappearingMessagesInDatabaseAndCreateMessages(
            newToken: disappearingMessageToken,
            contactThread: contactThread,
            changeAuthor: changeAuthor,
            localIdentifiers: localIdentifiers,
            transaction: transaction
        )
    }

    public static func localUpdateDisappearingMessageToken(
        _ disappearingMessageToken: VersionedDisappearingMessageToken,
        inContactThread contactThread: TSContactThread,
        tx: SDSAnyWriteTransaction
    ) {
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
            owsFailDebug("Not registered.")
            return
        }
        let updateResult = self.updateDisappearingMessagesInDatabaseAndCreateMessages(
            newToken: disappearingMessageToken,
            contactThread: contactThread,
            changeAuthor: localIdentifiers.aci,
            localIdentifiers: localIdentifiers,
            transaction: tx
        )
        self.sendDisappearingMessagesConfigurationMessage(
            updateResult: updateResult,
            contactThread: contactThread,
            transaction: tx
        )
    }

    private static func updateDisappearingMessagesInDatabaseAndCreateMessages(
        newToken: VersionedDisappearingMessageToken,
        contactThread: TSContactThread,
        changeAuthor: Aci?,
        localIdentifiers: LocalIdentifiers,
        transaction: SDSAnyWriteTransaction
    ) -> DisappearingMessagesConfigurationStore.SetTokenResult {
        let result = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            .set(
                token: newToken,
                for: .thread(contactThread),
                tx: transaction.asV2Write
            )

        // Skip redundant updates.
        if result.newConfiguration != result.oldConfiguration {
            let remoteContactName: String? = {
                if
                    let changeAuthor,
                    changeAuthor != localIdentifiers.aci
                {
                    return SSKEnvironment.shared.contactManagerRef.displayName(
                        for: SignalServiceAddress(changeAuthor),
                        tx: transaction
                    ).resolvedValue()
                }

                return nil
            }()

            let infoMessage = OWSDisappearingConfigurationUpdateInfoMessage(
                contactThread: contactThread,
                timestamp: MessageTimestampGenerator.sharedInstance.generateTimestamp(),
                isConfigurationEnabled: result.newConfiguration.isEnabled,
                configurationDurationSeconds: result.newConfiguration.durationSeconds,
                createdByRemoteName: remoteContactName
            )
            infoMessage.anyInsert(transaction: transaction)

            SSKEnvironment.shared.databaseStorageRef.touch(thread: contactThread, shouldReindex: false, transaction: transaction)
        }

        return result
    }

    private static func sendDisappearingMessagesConfigurationMessage(
        updateResult: DisappearingMessagesConfigurationStore.SetTokenResult,
        contactThread: TSContactThread,
        transaction: SDSAnyWriteTransaction
    ) {
        guard updateResult.newConfiguration != updateResult.oldConfiguration else {
            // The update was redundant, don't send an update message.
            return
        }
        let newConfiguration = updateResult.newConfiguration
        let message = OWSDisappearingMessagesConfigurationMessage(
            configuration: newConfiguration,
            thread: contactThread,
            transaction: transaction
        )
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: message
        )
        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)
    }

    // MARK: - Accept Invites

    public static func localAcceptInviteToGroupV2(
        groupModel: TSGroupModelV2,
        waitForMessageProcessing: Bool = false
    ) async throws {
        if waitForMessageProcessing {
            try await GroupManager.waitForMessageFetchingAndProcessingWithTimeout(description: "Accept invite")
        }
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            SSKEnvironment.shared.profileManagerRef.addGroupId(
                toProfileWhitelist: groupModel.groupId,
                userProfileWriter: .localUser,
                transaction: transaction
            )
        }
        _ = try await updateGroupV2(
            groupModel: groupModel,
            description: "Accept invite"
        ) { groupChangeSet in
            groupChangeSet.setLocalShouldAcceptInvite()
        }
    }

    // MARK: - Leave Group / Decline Invite

    public static func localLeaveGroupOrDeclineInvite(
        groupThread: TSGroupThread,
        replacementAdminAci: Aci? = nil,
        waitForMessageProcessing: Bool = false,
        tx: SDSAnyWriteTransaction
    ) -> Promise<TSGroupThread> {
        return SSKEnvironment.shared.localUserLeaveGroupJobQueueRef.addJob(
            groupThread: groupThread,
            replacementAdminAci: replacementAdminAci,
            waitForMessageProcessing: waitForMessageProcessing,
            tx: tx
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
                SSKEnvironment.shared.databaseStorageRef.write(.promise) { transaction in
                    self.localLeaveGroupOrDeclineInvite(groupThread: groupThread, tx: transaction).asVoid()
                }
            }.done { _ in
                success?()
            }.catch { error in
                owsFailDebug("Leave group failed: \(error)")
            }
        }
    }

    // MARK: - Remove From Group / Revoke Invite

    public static func removeFromGroupOrRevokeInviteV2(
        groupModel: TSGroupModelV2,
        serviceIds: [ServiceId]
    ) async throws -> TSGroupThread {
        return try await updateGroupV2(groupModel: groupModel, description: "Remove from group or revoke invite") { groupChangeSet in
            for serviceId in serviceIds {
                owsAssertDebug(!groupModel.groupMembership.isRequestingMember(serviceId))

                groupChangeSet.removeMember(serviceId)

                // Do not ban when revoking an invite
                if let aci = serviceId as? Aci, !groupModel.groupMembership.isInvitedMember(serviceId) {
                    groupChangeSet.addBannedMember(aci)
                }
            }
        }
    }

    public static func revokeInvalidInvites(groupModel: TSGroupModelV2) async throws -> TSGroupThread {
        return try await updateGroupV2(groupModel: groupModel, description: "Revoke invalid invites") { groupChangeSet in
            groupChangeSet.revokeInvalidInvites()
        }
    }

    // MARK: - Change Member Role

    public static func changeMemberRoleV2(
        groupModel: TSGroupModelV2,
        aci: Aci,
        role: TSGroupMemberRole
    ) async throws -> TSGroupThread {
        return try await updateGroupV2(groupModel: groupModel, description: "Change member role") { groupChangeSet in
            groupChangeSet.changeRoleForMember(aci, role: role)
        }
    }

    // MARK: - Change Group Access

    public static func changeGroupAttributesAccessV2(groupModel: TSGroupModelV2, access: GroupV2Access) async throws {
        _ = try await updateGroupV2(groupModel: groupModel, description: "Change group attributes access") { groupChangeSet in
            groupChangeSet.setAccessForAttributes(access)
        }
    }

    public static func changeGroupMembershipAccessV2(groupModel: TSGroupModelV2, access: GroupV2Access) async throws {
        _ = try await updateGroupV2(groupModel: groupModel, description: "Change group membership access") { groupChangeSet in
            groupChangeSet.setAccessForMembers(access)
        }
    }

    // MARK: - Group Links

    public static func updateLinkModeV2(groupModel: TSGroupModelV2, linkMode: GroupsV2LinkMode) async throws -> TSGroupThread {
        return try await updateGroupV2(groupModel: groupModel, description: "Change group link mode") { groupChangeSet in
            groupChangeSet.setLinkMode(linkMode)
        }
    }

    public static func resetLinkV2(groupModel: TSGroupModelV2) async throws -> TSGroupThread {
        return try await updateGroupV2(groupModel: groupModel, description: "Rotate invite link password") { groupChangeSet in
            groupChangeSet.rotateInviteLinkPassword()
        }
    }

    public static let inviteLinkPasswordLengthV2: UInt = 16

    public static func generateInviteLinkPasswordV2() -> Data {
        Randomness.generateRandomBytes(inviteLinkPasswordLengthV2)
    }

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

    public static func joinGroupViaInviteLink(
        groupId: Data,
        groupSecretParams: GroupSecretParams,
        inviteLinkPassword: Data,
        groupInviteLinkPreview: GroupInviteLinkPreview,
        avatarData: Data?
    ) async throws {
        try await ensureLocalProfileHasCommitmentIfNecessary()
        try await SSKEnvironment.shared.groupsV2Ref.joinGroupViaInviteLink(
            groupId: groupId,
            groupSecretParams: groupSecretParams,
            inviteLinkPassword: inviteLinkPassword,
            groupInviteLinkPreview: groupInviteLinkPreview,
            avatarData: avatarData
        )

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            SSKEnvironment.shared.profileManagerRef.addGroupId(
                toProfileWhitelist: groupId,
                userProfileWriter: .localUser,
                transaction: transaction
            )
        }
    }

    public static func acceptOrDenyMemberRequestsV2(
        groupModel: TSGroupModelV2,
        aci: Aci,
        shouldAccept: Bool
    ) async throws -> TSGroupThread {
        let description = (shouldAccept ? "Accept group member request" : "Deny group member request")
        return try await updateGroupV2(groupModel: groupModel, description: description) { groupChangeSet in
            if shouldAccept {
                groupChangeSet.addMember(aci, role: .`normal`)
            } else {
                groupChangeSet.removeMember(aci)
                groupChangeSet.addBannedMember(aci)
            }
        }
    }

    public static func cancelRequestToJoin(groupModel: TSGroupModelV2) async throws -> TSGroupThread {
        let description = "Cancel Request to Join"
        return try await Promise.wrapAsync {
            try await SSKEnvironment.shared.groupsV2Ref.cancelRequestToJoin(groupModel: groupModel)
        }.timeout(seconds: Self.groupUpdateTimeoutDuration, description: description) {
            return GroupsV2Error.timeout
        }.awaitable()
    }

    public static func cachedGroupInviteLinkPreview(groupInviteLinkInfo: GroupInviteLinkInfo) -> GroupInviteLinkPreview? {
        do {
            let groupContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: groupInviteLinkInfo.masterKey)
            return SSKEnvironment.shared.groupsV2Ref.cachedGroupInviteLinkPreview(groupSecretParams: groupContextInfo.groupSecretParams)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    // MARK: - Announcements

    public static func setIsAnnouncementsOnly(groupModel: TSGroupModelV2, isAnnouncementsOnly: Bool) async throws {
        _ = try await updateGroupV2(groupModel: groupModel, description: "Update isAnnouncementsOnly") { groupChangeSet in
            groupChangeSet.setIsAnnouncementsOnly(isAnnouncementsOnly)
        }
    }

    // MARK: - Local profile key

    public static func updateLocalProfileKey(groupModel: TSGroupModelV2) async throws -> TSGroupThread {
        return try await updateGroupV2(groupModel: groupModel, description: "Update local profile key") { changes in
            changes.setShouldUpdateLocalProfileKey()
        }
    }

    // MARK: - Removed from Group or Invite Revoked

    public static func handleNotInGroup(groupId: Data, transaction: SDSAnyWriteTransaction) {
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else {
            owsFailDebug("Missing localIdentifiers.")
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
            groupMembershipBuilder.remove(localIdentifiers.aci)
            var groupModelBuilder = groupModel.asBuilder
            do {
                groupModelBuilder.groupMembership = groupMembershipBuilder.build()
                let newGroupModel = try groupModelBuilder.build()

                // groupUpdateSource is unknown because we don't (and can't) know who removed
                // us or revoked our invite.
                //
                // newDisappearingMessageToken is nil because we don't want to change DM
                // state.
                _ = try updateExistingGroupThreadInDatabaseAndCreateInfoMessage(
                    newGroupModel: newGroupModel,
                    newDisappearingMessageToken: nil,
                    newlyLearnedPniToAciAssociations: [:],
                    groupUpdateSource: .unknown,
                    infoMessagePolicy: .always,
                    localIdentifiers: localIdentifiers,
                    spamReportingMetadata: .createdByLocalAction,
                    transaction: transaction
                )
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }

        if
            let groupModelV2 = groupModel as? TSGroupModelV2,
            groupModelV2.isJoinRequestPlaceholder
        {
            Logger.warn("Ignoring 403 for placeholder group.")
            Task {
                try? await SSKEnvironment.shared.groupsV2Ref.tryToUpdatePlaceholderGroupModelUsingInviteLinkPreview(
                    groupModel: groupModelV2,
                    removeLocalUserBlock: removeLocalUserBlock
                )
            }
        } else {
            removeLocalUserBlock(transaction)
        }
    }

    // MARK: - Messages

    public static func sendGroupUpdateMessage(thread: TSGroupThread, groupChangeProtoData: Data? = nil) async {
        guard thread.isGroupV2Thread else {
            owsFail("[GV1] Should be impossible to send V1 group messages!")
        }

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore

            let message = OutgoingGroupUpdateMessage(
                in: thread,
                groupMetaMessage: .update,
                expiresInSeconds: dmConfigurationStore.durationSeconds(for: thread, tx: transaction.asV2Read),
                groupChangeProtoData: groupChangeProtoData,
                additionalRecipients: Self.invitedMembers(in: thread),
                transaction: transaction
            )
            // "changeActionsProtoData" is _not_ an attachment, it is just put on
            // the outgoing proto directly.
            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: message
            )

            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)
        }
    }

    private static func sendDurableNewGroupMessage(forThread thread: TSGroupThread) async {
        guard thread.isGroupV2Thread else {
            owsFail("[GV1] Should be impossible to send V1 group messages!")
        }

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let message = OutgoingGroupUpdateMessage(
                in: thread,
                groupMetaMessage: .new,
                expiresInSeconds: dmConfigurationStore.durationSeconds(for: thread, tx: tx.asV2Read),
                additionalRecipients: Self.invitedMembers(in: thread),
                transaction: tx
            )
            // "changeActionsProtoData" is _not_ an attachment, it is just put on
            // the outgoing proto directly.
            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: message
            )
            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
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
    public static func insertGroupThreadInDatabaseAndCreateInfoMessage(
        groupModel: TSGroupModelV2,
        disappearingMessageToken: DisappearingMessageToken?,
        groupUpdateSource: GroupUpdateSource,
        infoMessagePolicy: InfoMessagePolicy = .always,
        localIdentifiers: LocalIdentifiers,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        transaction: SDSAnyWriteTransaction
    ) -> TSGroupThread {

        if let groupThread = TSGroupThread.fetch(groupId: groupModel.groupId, transaction: transaction) {
            owsFail("Inserting existing group thread: \(groupThread.uniqueId).")
        }

        let groupThread = DependenciesBridge.shared.threadStore.createGroupThread(
            groupModel: groupModel, tx: transaction.asV2Write
        )

        let newDisappearingMessageToken = disappearingMessageToken ?? DisappearingMessageToken.disabledToken
        _ = updateDisappearingMessageConfiguration(
            newToken: newDisappearingMessageToken,
            groupThread: groupThread,
            tx: transaction
        )

        autoWhitelistGroupIfNecessary(
            oldGroupModel: nil,
            newGroupModel: groupModel,
            groupUpdateSource: groupUpdateSource,
            localIdentifiers: localIdentifiers,
            tx: transaction
        )

        switch infoMessagePolicy {
        case .always, .insertsOnly:
            insertGroupUpdateInfoMessageForNewGroup(
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: spamReportingMetadata,
                groupThread: groupThread,
                groupModel: groupModel,
                disappearingMessageToken: newDisappearingMessageToken,
                groupUpdateSource: groupUpdateSource,
                transaction: transaction
            )
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
        newGroupModel: TSGroupModelV2,
        newDisappearingMessageToken: DisappearingMessageToken?,
        newlyLearnedPniToAciAssociations: [Pni: Aci],
        groupUpdateSource: GroupUpdateSource,
        didAddLocalUserToV2Group: Bool,
        infoMessagePolicy: InfoMessagePolicy = .always,
        localIdentifiers: LocalIdentifiers,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        transaction: SDSAnyWriteTransaction
    ) throws -> TSGroupThread {
        let threadId = TSGroupThread.threadId(forGroupId: newGroupModel.groupId, transaction: transaction)
        if TSGroupThread.anyExists(uniqueId: threadId, transaction: transaction) {
            return try updateExistingGroupThreadInDatabaseAndCreateInfoMessage(
                newGroupModel: newGroupModel,
                newDisappearingMessageToken: newDisappearingMessageToken,
                newlyLearnedPniToAciAssociations: newlyLearnedPniToAciAssociations,
                groupUpdateSource: groupUpdateSource,
                infoMessagePolicy: infoMessagePolicy,
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: spamReportingMetadata,
                transaction: transaction
            )
        } else {
            /// We only want to attribute the author for this insertion if we've
            /// just been added to the group. Otherwise, we don't want to
            /// attribute all the group state to the author of the most recent
            /// revision.
            let shouldAttributeAuthor: Bool = {
                if
                    didAddLocalUserToV2Group,
                    newGroupModel.groupMembership.isMemberOfAnyKind(localIdentifiers.aciAddress)
                {
                    return true
                }

                return false
            }()

            return insertGroupThreadInDatabaseAndCreateInfoMessage(
                groupModel: newGroupModel,
                disappearingMessageToken: newDisappearingMessageToken,
                groupUpdateSource: shouldAttributeAuthor ? groupUpdateSource : .unknown,
                infoMessagePolicy: infoMessagePolicy,
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: spamReportingMetadata,
                transaction: transaction
            )
        }
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
        newlyLearnedPniToAciAssociations: [Pni: Aci],
        groupUpdateSource: GroupUpdateSource,
        infoMessagePolicy: InfoMessagePolicy = .always,
        localIdentifiers: LocalIdentifiers,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        transaction: SDSAnyWriteTransaction
    ) throws -> TSGroupThread {
        // Step 1: First reload latest thread state. This ensures:
        //
        // * The thread (still) exists in the database.
        // * The update is working off latest database state.
        //
        // We always have the groupThread at the call sites of this method, but this
        // future-proofs us against bugs.
        guard let groupThread = TSGroupThread.fetch(groupId: newGroupModel.groupId, transaction: transaction) else {
            throw OWSAssertionError("Missing groupThread.")
        }

        guard
            let newGroupModel = newGroupModel as? TSGroupModelV2,
            let oldGroupModel = groupThread.groupModel as? TSGroupModelV2
        else {
            owsFail("[GV1] Should be impossible to update a V1 group!")
        }

        // Step 2: Update DM configuration in database, if necessary.
        let updateDMResult: DisappearingMessagesConfigurationStore.SetTokenResult
        if let newDisappearingMessageToken = newDisappearingMessageToken {
            // shouldInsertInfoMessage is false because we only want to insert a
            // single info message if we update both DM config and thread model.
            updateDMResult = updateDisappearingMessageConfiguration(
                newToken: newDisappearingMessageToken,
                groupThread: groupThread,
                tx: transaction
            )
        } else {
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let dmConfiguration = dmConfigurationStore.fetchOrBuildDefault(for: .thread(groupThread), tx: transaction.asV2Read)

            updateDMResult = (
                oldConfiguration: dmConfiguration,
                newConfiguration: dmConfiguration
            )
        }

        // Step 3: If any member was removed, make sure we rotate our sender key
        // session.
        //
        // If *we* were removed, check if the group contained any blocked
        // members and make a best-effort attempt to rotate our profile key if
        // this was our only mutual group with them.
        do {
            let oldMembers = oldGroupModel.membership.allMembersOfAnyKindServiceIds
            let newMembers = newGroupModel.membership.allMembersOfAnyKindServiceIds

            if oldMembers.subtracting(newMembers).isEmpty == false {
                SSKEnvironment.shared.senderKeyStoreRef.resetSenderKeySession(for: groupThread, transaction: transaction)
            }

            if
                DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction.asV2Read).isPrimaryDevice ?? true,
                let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)?.aci,
                oldGroupModel.membership.hasProfileKeyInGroup(serviceId: localAci),
                !newGroupModel.membership.hasProfileKeyInGroup(serviceId: localAci)
            {
                // If our profile key is no longer exposed to the group - for
                // example, we've left the group - check if the group had any
                // blocked users to whom our profile key was exposed.
                var shouldRotateProfileKey = false
                for member in oldMembers {
                    let memberAddress = SignalServiceAddress(member)

                    if
                        (
                            SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(memberAddress, transaction: transaction)
                            || DependenciesBridge.shared.recipientHidingManager.isHiddenAddress(memberAddress, tx: transaction.asV2Read)
                        ),
                        newGroupModel.membership.canViewProfileKeys(serviceId: member)
                    {
                        // Make a best-effort attempt to find other groups with
                        // this blocked user in which our profile key is
                        // exposed.
                        //
                        // We can only efficiently query for groups in which
                        // they are a full member, although that may not be all
                        // the groups in which they can see your profile key.
                        // Best effort.
                        let mutualGroupThreads = Self.mutualGroupThreads(
                            with: member,
                            localAci: localAci,
                            tx: transaction
                        )

                        // If there is exactly one group, it's the one we are leaving!
                        // We should rotate, as it's the last group we have in common.
                        if mutualGroupThreads.count == 1 {
                            shouldRotateProfileKey = true
                            break
                        }
                    }
                }

                if shouldRotateProfileKey {
                    SSKEnvironment.shared.profileManagerRef.forceRotateLocalProfileKeyForGroupDeparture(with: transaction)
                }
            }
        }

        // Step 4: Update group in database, if necessary.
        let hasUserFacingUpdate: Bool = {
            guard newGroupModel.revision > oldGroupModel.revision else {
                /// Local group state must never revert to an earlier revision.
                ///
                /// Races exist in the GV2 code, so if we find ourselves with a
                /// redundant update we'll simply drop it.
                ///
                /// Note that (excepting bugs elsewhere in the GV2 code) no
                /// matter which codepath learned about a particular revision,
                /// the group models each codepath constructs for that revision
                /// should be equivalent.
                Logger.warn("Skipping redundant update for V2 group.")
                return false
            }

            autoWhitelistGroupIfNecessary(
                oldGroupModel: oldGroupModel,
                newGroupModel: newGroupModel,
                groupUpdateSource: groupUpdateSource,
                localIdentifiers: localIdentifiers,
                tx: transaction
            )

            let hasUserFacingGroupModelChange = newGroupModel.hasUserFacingChangeCompared(
                to: oldGroupModel
            )
            let hasDMUpdate = updateDMResult.newConfiguration != updateDMResult.oldConfiguration

            let hasUserFacingUpdate = hasUserFacingGroupModelChange || hasDMUpdate
            groupThread.update(
                with: newGroupModel,
                shouldUpdateChatListUi: hasUserFacingUpdate,
                transaction: transaction
            )

            return hasUserFacingUpdate
        }()

        guard hasUserFacingUpdate else {
            return groupThread
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
                groupUpdateSource: groupUpdateSource,
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: spamReportingMetadata,
                transaction: transaction
            )
        default:
            break
        }

        return groupThread
    }

    private static func mutualGroupThreads(
        with member: ServiceId,
        localAci: Aci,
        tx: SDSAnyReadTransaction
    ) -> [TSGroupThread] {
        return DependenciesBridge.shared.groupMemberStore
            .groupThreadIds(
                withFullMember: member,
                tx: tx.asV2Read
            )
            .lazy
            .compactMap { groupThreadId in
                return TSGroupThread.anyFetchGroupThread(uniqueId: groupThreadId, transaction: tx)
            }
            .filter { groupThread in
                return groupThread.groupMembership.hasProfileKeyInGroup(serviceId: localAci)
            }
    }

    public static func hasMutualGroupThread(
        with member: ServiceId,
        localAci: Aci,
        tx: SDSAnyReadTransaction
    ) -> Bool {
        let mutualGroupThreads = Self.mutualGroupThreads(
            with: member,
            localAci: localAci,
            tx: tx
        )
        return !mutualGroupThreads.isEmpty
    }

    // MARK: - Storage Service

    private static func notifyStorageServiceOfInsertedGroup(groupModel: TSGroupModel,
                                                            transaction: SDSAnyReadTransaction) {
        guard let groupModel = groupModel as? TSGroupModelV2 else {
            // We only need to notify the storage service about v2 groups.
            return
        }
        guard !SSKEnvironment.shared.groupsV2Ref.isGroupKnownToStorageService(groupModel: groupModel,
                                                          transaction: transaction) else {
            // To avoid redundant storage service writes,
            // don't bother notifying the storage service
            // about v2 groups it already knows about.
            return
        }

        SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(groupModel: groupModel)
    }

    // MARK: - Profiles

    private static func autoWhitelistGroupIfNecessary(
        oldGroupModel: TSGroupModel?,
        newGroupModel: TSGroupModel,
        groupUpdateSource: GroupUpdateSource,
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyWriteTransaction
    ) {
        let justAdded = wasLocalUserJustAddedToTheGroup(
            oldGroupModel: oldGroupModel,
            newGroupModel: newGroupModel,
            localIdentifiers: localIdentifiers
        )
        guard justAdded else {
            return
        }

        let shouldAddToWhitelist: Bool
        switch groupUpdateSource {
        case .unknown, .legacyE164, .rejectedInviteToPni:
            // Invalid updaters, shouldn't add.
            shouldAddToWhitelist = false
        case .aci(let aci):
            shouldAddToWhitelist = SSKEnvironment.shared.profileManagerRef.isUser(inProfileWhitelist: SignalServiceAddress(aci), transaction: tx)
        case .localUser:
            // Always whitelist if its the local user updating.
            shouldAddToWhitelist = true
        }

        guard shouldAddToWhitelist else {
            return
        }

        // Ensure the thread is in our profile whitelist if we're a member of the group.
        // We don't want to do this if we're just a pending member or are leaving/have
        // already left the group.
        SSKEnvironment.shared.profileManagerRef.addGroupId(
            toProfileWhitelist: newGroupModel.groupId, userProfileWriter: .localUser, transaction: tx
        )
    }

    private static func wasLocalUserJustAddedToTheGroup(
        oldGroupModel: TSGroupModel?,
        newGroupModel: TSGroupModel,
        localIdentifiers: LocalIdentifiers
    ) -> Bool {
        if let oldGroupModel, oldGroupModel.groupMembership.isFullMember(localIdentifiers.aci) {
            // Local user already was a member.
            return false
        }
        if !newGroupModel.groupMembership.isFullMember(localIdentifiers.aci) {
            // Local user is not a member.
            return false
        }
        return true
    }

    // MARK: -

    /// A profile key is considered "authoritative" when it comes in on a group
    /// change action and the owner of the profile key matches the group change
    /// action author. We consider an "authoritative" profile key the source of
    /// truth. Even if we have a different profile key for this user already,
    /// we consider this authoritative profile key the correct, most up-to-date
    /// one. A "non-authoritative" profile key, on the other hand, may or may
    /// not be the most up to date profile key for a user (such as if one user
    /// adds another to a group without having their latest profile key), and we
    /// only use it if we have no other profile key for the user already.
    ///
    /// - Parameter allProfileKeysByAci: contains both authoritative and
    ///   non-authoritative profile keys.
    ///
    /// - Parameter authoritativeProfileKeysByAci: contains just authoritative
    ///   profile keys. If authoritative profile keys can't be determined, pass
    ///   an empty Dictionary.
    public static func storeProfileKeysFromGroupProtos(
        allProfileKeysByAci: [Aci: Data],
        authoritativeProfileKeysByAci: [Aci: Data] = [:],
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyWriteTransaction
    ) {
        // We trust what is locally-stored as the local user's profile key to be
        // more authoritative than what is stored in the group state on the server.
        var authoritativeProfileKeysByAci = authoritativeProfileKeysByAci
        authoritativeProfileKeysByAci.removeValue(forKey: localIdentifiers.aci)
        SSKEnvironment.shared.profileManagerRef.fillInProfileKeys(
            allProfileKeys: allProfileKeysByAci,
            authoritativeProfileKeys: authoritativeProfileKeysByAci,
            userProfileWriter: .groupState,
            localIdentifiers: localIdentifiers,
            tx: tx.asV2Write
        )
    }

    /// Ensure that we have a profile key commitment for our local profile
    /// available on the service.
    ///
    /// We (and other clients) need profile key credentials for group members in
    /// order to perform GV2 operations. However, other clients can't request
    /// our profile key credential from the service until we've uploaded a profile
    /// key commitment to the service.
    public static func ensureLocalProfileHasCommitmentIfNecessary() async throws {
        let accountManager = DependenciesBridge.shared.tsAccountManager

        func hasProfileKeyCredential() throws -> Bool {
            return try SSKEnvironment.shared.databaseStorageRef.read { tx in
                guard accountManager.registrationState(tx: tx.asV2Read).isRegistered else {
                    return false
                }
                guard let localAddress = accountManager.localIdentifiers(tx: tx.asV2Read)?.aciAddress else {
                    throw OWSAssertionError("Missing localAddress.")
                }
                return SSKEnvironment.shared.groupsV2Ref.hasProfileKeyCredential(for: localAddress, transaction: tx)
            }
        }

        guard try !hasProfileKeyCredential() else {
            return
        }

        // If we don't have a local profile key credential we should first
        // check if it is simply expired, by asking for a new one (which we
        // would get as part of fetching our local profile).
        _ = try await SSKEnvironment.shared.profileManagerRef.fetchLocalUsersProfile(authedAccount: .implicit()).awaitable()

        guard try !hasProfileKeyCredential() else {
            return
        }

        guard
            CurrentAppContext().isMainApp,
            SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
                accountManager.registrationState(tx: tx.asV2Read).isRegisteredPrimaryDevice
            })
        else {
            Logger.warn("Skipping upload of local profile key commitment, not in main app!")
            return
        }

        // We've never uploaded a profile key commitment - do so now.
        Logger.info("No profile key credential available for local account - uploading local profile!")
        _ = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            SSKEnvironment.shared.profileManagerRef.reuploadLocalProfile(
                unsavedRotatedProfileKey: nil,
                mustReuploadAvatar: false,
                authedAccount: .implicit(),
                tx: tx.asV2Write
            )
        }
    }
}

// MARK: -

public extension GroupManager {
    class func waitForMessageFetchingAndProcessingWithTimeout(description: String) async throws {
        return try await Promise.wrapAsync {
            await SSKEnvironment.shared.messageProcessorRef.waitForFetchingAndProcessing().awaitable()
        }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration, description: description) {
            return GroupsV2Error.timeout
        }.awaitable()
    }
}

// MARK: - Add/Invite to group

extension GroupManager {
    public static func addOrInvite(
        serviceIds: [ServiceId],
        toExistingGroup existingGroupModel: TSGroupModel
    ) async throws -> TSGroupThread {
        guard let existingGroupModel = existingGroupModel as? TSGroupModelV2 else {
            owsFail("[GV1] Mutations on V1 groups should be impossible!")
        }

        // Ensure we have fetched profile key credentials before performing
        // the add below, since we depend on credential state to decide
        // whether to add or invite a user.
        try await SSKEnvironment.shared.groupsV2Ref.tryToFetchProfileKeyCredentials(
            for: serviceIds.compactMap { $0 as? Aci },
            ignoreMissingProfiles: false,
            forceRefresh: false
        )

        return try await updateGroupV2(
            groupModel: existingGroupModel,
            description: "Add/Invite new non-admin members"
        ) { groupChangeSet in
            SSKEnvironment.shared.databaseStorageRef.read { transaction in
                for serviceId in serviceIds {
                    owsAssertDebug(!existingGroupModel.groupMembership.isMemberOfAnyKind(serviceId))

                    // Important that at this point we already have the
                    // profile keys for these users
                    let hasCredential = SSKEnvironment.shared.groupsV2Ref.hasProfileKeyCredential(
                        for: SignalServiceAddress(serviceId),
                        transaction: transaction
                    )

                    if let aci = serviceId as? Aci, hasCredential {
                        groupChangeSet.addMember(aci, role: .normal)
                    } else {
                        groupChangeSet.addInvitedMember(serviceId, role: .normal)
                    }

                    if let aci = serviceId as? Aci, existingGroupModel.groupMembership.isBannedMember(aci) {
                        groupChangeSet.removeBannedMember(aci)
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
    ) async throws {
        guard let existingGroupModel = existingGroupModel as? TSGroupModelV2 else {
            owsFail("[GV1] Mutations on V1 groups should be impossible!")
        }

        let avatarUrlPath = try await { () -> String? in
            guard let avatarData else {
                return nil
            }

            // Skip upload if the new avatar data is the same as the existing
            if
                let existingAvatarHash = existingGroupModel.avatarHash,
                try existingAvatarHash == TSGroupModel.hash(forAvatarData: avatarData)
            {
                return nil
            }

            return try await SSKEnvironment.shared.groupsV2Ref.uploadGroupAvatar(
                avatarData: avatarData,
                groupSecretParams: try existingGroupModel.secretParams()
            )
        }()

        var message = "Update attributes:"
        message += title != nil ? " title" : ""
        message += description != nil ? " description" : ""
        message += avatarData != nil ? " settingAvatarData" : " clearingAvatarData"

        _ = try await self.updateGroupV2(
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
