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
    override private init() {}

    // MARK: -

    // GroupsV2 TODO: Finalize this value with the designers.
    public static let groupUpdateTimeoutDuration: TimeInterval = 30

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

    public static let maxEmbeddedChangeProtoLength: UInt = UInt(OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes)

    // MARK: - Group IDs

    static func groupIdLength(for groupsVersion: GroupsVersion) -> UInt {
        switch groupsVersion {
        case .V1:
            return kGroupIdLengthV1
        case .V2:
            return kGroupIdLengthV2
        }
    }

    public static func isV1GroupId(_ groupId: Data) -> Bool {
        groupId.count == groupIdLength(for: .V1)
    }

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

    public static func isValidGroupIdOfAnyKind(_ groupId: Data) -> Bool {
        return isV1GroupId(groupId) || isV2GroupId(groupId)
    }

    // MARK: -

    public static func canLocalUserLeaveGroupWithoutChoosingNewAdmin(
        localAci: Aci,
        groupMembership: GroupMembership,
    ) -> Bool {
        let fullMembers = Set(groupMembership.fullMembers.compactMap { $0.serviceId as? Aci })
        let fullMemberAdmins = Set(groupMembership.fullMemberAdministrators.compactMap { $0.serviceId as? Aci })
        return canLocalUserLeaveGroupWithoutChoosingNewAdmin(
            localAci: localAci,
            fullMembers: fullMembers,
            admins: fullMemberAdmins,
        )
    }

    public static func canLocalUserLeaveGroupWithoutChoosingNewAdmin(
        localAci: Aci,
        fullMembers: Set<Aci>,
        admins: Set<Aci>,
    ) -> Bool {
        // If the current user is the only admin and they're not the only member of
        // the group, then they must select a new admin.
        if Set([localAci]) == admins, Set([localAci]) != fullMembers {
            return false
        }
        return true
    }

    // MARK: - Group Models

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
    public static func localCreateNewGroup(
        seed: NewGroupSeed,
        members membersParam: [SignalServiceAddress],
        name: StrippedNonEmptyString,
        avatarData: Data?,
        disappearingMessageToken: DisappearingMessageToken,
    ) async throws -> TSGroupThread {
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            throw OWSAssertionError("Missing localIdentifiers.")
        }

        var otherMembers = membersParam.compactMap(\.serviceId)
        otherMembers.removeAll(where: { $0 == localIdentifiers.aci })

        try await ensureLocalProfileHasCommitmentIfNecessary()

        var downloadedAvatars = GroupAvatarStateMap()

        let newGroupParams = GroupsV2Protos.NewGroupParams(
            secretParams: seed.groupSecretParams,
            title: name,
            avatarUrlPath: try await { () async throws -> String? in
                guard let avatarData else {
                    return nil
                }
                // Upload avatar.
                let avatarUrlPath = try await SSKEnvironment.shared.groupsV2Ref.uploadGroupAvatar(
                    avatarData: avatarData,
                    groupSecretParams: seed.groupSecretParams,
                )
                downloadedAvatars.set(avatarDataState: .available(avatarData), avatarUrlPath: avatarUrlPath)
                return avatarUrlPath
            }(),
            otherMembers: otherMembers,
            disappearingMessageToken: disappearingMessageToken,
        )

        let snapshotResponse = try await SSKEnvironment.shared.groupsV2Ref.createNewGroupOnService(
            newGroupParams,
            downloadedAvatars: downloadedAvatars,
            localAci: localIdentifiers.aci,
        )

        let thread = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            let builder = try TSGroupModelBuilder.builderForSnapshot(
                groupV2Snapshot: snapshotResponse.groupSnapshot,
                transaction: tx,
            )
            let groupModel = try builder.buildAsV2()

            let thread = self.insertGroupThreadInDatabaseAndCreateInfoMessage(
                groupModel: groupModel,
                disappearingMessageToken: disappearingMessageToken,
                groupUpdateSource: .localUser(originalSource: .aci(localIdentifiers.aci)),
                infoMessagePolicy: .insert,
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: .createdByLocalAction,
                transaction: tx,
            )
            SSKEnvironment.shared.profileManagerRef.addGroupId(
                toProfileWhitelist: groupModel.groupId,
                userProfileWriter: .localUser,
                transaction: tx,
            )
            if let groupSendEndorsementsResponse = snapshotResponse.groupSendEndorsementsResponse {
                SSKEnvironment.shared.groupsV2Ref.handleGroupSendEndorsementsResponse(
                    groupSendEndorsementsResponse,
                    groupThreadId: thread.sqliteRowId!,
                    secretParams: snapshotResponse.groupSnapshot.groupSecretParams,
                    membership: snapshotResponse.groupSnapshot.groupMembership,
                    localAci: localIdentifiers.aci,
                    tx: tx,
                )
            }
            return thread
        }

        await sendDurableNewGroupMessage(forThread: thread)

        return thread
    }

    // MARK: - Tests

#if TESTABLE_BUILD

    /// Create a group for testing purposes.
    ///
    /// - Parameter shouldInsertInfoMessage
    /// Whether an info message describing this group's creation should be
    /// inserted in the to-be-created thread corresponding to the group. If
    /// `true`, the local user must be a member of the group.
    public static func createGroupForTests(
        members: [SignalServiceAddress],
        shouldInsertInfoMessage: Bool = false,
        name: String? = nil,
        descriptionText: String? = nil,
        transaction: DBWriteTransaction,
    ) throws -> TSGroupThread {

        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction) else {
            throw OWSAssertionError("Missing localIdentifiers.")
        }

        // GroupsV2 TODO: Elaborate tests to include admins, pending members, etc.
        // GroupsV2 TODO: Let tests specify access levels.
        // GroupsV2 TODO: Fill in avatarUrlPath when we test v2 groups.

        let secretParams = try GroupSecretParams.generate()
        var builder = TSGroupModelBuilder(secretParams: secretParams)
        builder.name = name
        builder.descriptionText = descriptionText
        builder.groupMembership = GroupMembership(membersForTest: members)
        builder.groupAccess = .defaultForV2
        let groupModel = try builder.buildAsV2()

        // Just create it in the database, don't create it on the service.
        return remoteUpsertExistingGroupForTests(
            groupModel: groupModel,
            disappearingMessageToken: nil,
            groupUpdateSource: .localUser(originalSource: .aci(localIdentifiers.aci)),
            infoMessagePolicy: shouldInsertInfoMessage ? .insert : .doNotInsert,
            localIdentifiers: localIdentifiers,
            transaction: transaction,
        )
    }

    // If disappearingMessageToken is nil, don't update the disappearing messages configuration.
    private static func remoteUpsertExistingGroupForTests(
        groupModel: TSGroupModelV2,
        disappearingMessageToken: DisappearingMessageToken?,
        groupUpdateSource: GroupUpdateSource,
        infoMessagePolicy: InfoMessagePolicy = .insert,
        localIdentifiers: LocalIdentifiers,
        transaction: DBWriteTransaction,
    ) -> TSGroupThread {
        return self.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(
            newGroupModel: groupModel,
            newDisappearingMessageToken: disappearingMessageToken,
            newlyLearnedPniToAciAssociations: [:],
            groupUpdateSource: groupUpdateSource,
            didAddLocalUserToV2Group: false,
            infoMessagePolicy: infoMessagePolicy,
            localIdentifiers: localIdentifiers,
            spamReportingMetadata: .unreportable,
            transaction: transaction,
        )
    }

#endif

    // MARK: - Disappearing Messages for group threads

    private static func updateDisappearingMessageConfiguration(
        newToken: DisappearingMessageToken,
        groupThread: TSGroupThread,
        tx: DBWriteTransaction,
    ) -> DisappearingMessagesConfigurationStore.SetTokenResult {
        let setTokenResult = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            .set(token: newToken, for: groupThread, tx: tx)

        if setTokenResult.newConfiguration != setTokenResult.oldConfiguration {
            SSKEnvironment.shared.databaseStorageRef.touch(thread: groupThread, shouldReindex: false, tx: tx)
        }

        return setTokenResult
    }

    // MARK: - Disappearing Messages for contact threads (for whatever reason, historically part of GroupManager)

    public static func remoteUpdateDisappearingMessages(
        contactThread: TSContactThread,
        disappearingMessageToken: VersionedDisappearingMessageToken,
        changeAuthor: Aci?,
        localIdentifiers: LocalIdentifiers,
        transaction: DBWriteTransaction,
    ) {
        _ = self.updateDisappearingMessagesInDatabaseAndCreateMessages(
            newToken: disappearingMessageToken,
            contactThread: contactThread,
            changeAuthor: changeAuthor,
            localIdentifiers: localIdentifiers,
            transaction: transaction,
        )
    }

    public static func localUpdateDisappearingMessageToken(
        _ disappearingMessageToken: VersionedDisappearingMessageToken,
        inContactThread contactThread: TSContactThread,
        tx: DBWriteTransaction,
    ) {
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx) else {
            owsFailDebug("Not registered.")
            return
        }
        let updateResult = self.updateDisappearingMessagesInDatabaseAndCreateMessages(
            newToken: disappearingMessageToken,
            contactThread: contactThread,
            changeAuthor: localIdentifiers.aci,
            localIdentifiers: localIdentifiers,
            transaction: tx,
        )
        self.sendDisappearingMessagesConfigurationMessage(
            updateResult: updateResult,
            contactThread: contactThread,
            transaction: tx,
        )
    }

    private static func updateDisappearingMessagesInDatabaseAndCreateMessages(
        newToken: VersionedDisappearingMessageToken,
        contactThread: TSContactThread,
        changeAuthor: Aci?,
        localIdentifiers: LocalIdentifiers,
        transaction: DBWriteTransaction,
    ) -> DisappearingMessagesConfigurationStore.SetTokenResult {
        let result = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            .set(
                token: newToken,
                for: .thread(contactThread),
                tx: transaction,
            )

        // Skip redundant updates.
        if !result.newConfiguration.hasSameDuration(as: result.oldConfiguration) {
            let remoteContactName: String? = {
                if
                    let changeAuthor,
                    changeAuthor != localIdentifiers.aci
                {
                    return SSKEnvironment.shared.contactManagerRef.displayName(
                        for: SignalServiceAddress(changeAuthor),
                        tx: transaction,
                    ).resolvedValue()
                }

                return nil
            }()

            let infoMessage = OWSDisappearingConfigurationUpdateInfoMessage(
                contactThread: contactThread,
                timestamp: MessageTimestampGenerator.sharedInstance.generateTimestamp(),
                isConfigurationEnabled: result.newConfiguration.isEnabled,
                configurationDurationSeconds: result.newConfiguration.durationSeconds,
                createdByRemoteName: remoteContactName,
            )
            infoMessage.anyInsert(transaction: transaction)

            SSKEnvironment.shared.databaseStorageRef.touch(thread: contactThread, shouldReindex: false, tx: transaction)
        }

        return result
    }

    private static func sendDisappearingMessagesConfigurationMessage(
        updateResult: DisappearingMessagesConfigurationStore.SetTokenResult,
        contactThread: TSContactThread,
        transaction: DBWriteTransaction,
    ) {
        guard updateResult.newConfiguration != updateResult.oldConfiguration else {
            // The update was redundant, don't send an update message.
            return
        }
        let newConfiguration = updateResult.newConfiguration
        let message = OWSDisappearingMessagesConfigurationMessage(
            configuration: newConfiguration,
            thread: contactThread,
            transaction: transaction,
        )
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: message,
        )
        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)
    }

    // MARK: - Accept Invites

    public static func localAcceptInviteToGroupV2(
        groupModel: TSGroupModelV2,
        waitForMessageProcessing: Bool = false,
    ) async throws {
        if waitForMessageProcessing {
            try await GroupManager.waitForMessageFetchingAndProcessingWithTimeout()
        }
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            SSKEnvironment.shared.profileManagerRef.addGroupId(
                toProfileWhitelist: groupModel.groupId,
                userProfileWriter: .localUser,
                transaction: transaction,
            )
        }
        try await updateGroupV2(
            groupModel: groupModel,
            description: "Accept invite",
        ) { groupChangeSet in
            groupChangeSet.setLocalShouldAcceptInvite()
        }
    }

    // MARK: - Leave Group / Decline Invite

    public static func localLeaveGroupOrDeclineInvite(
        groupThread: TSGroupThread,
        replacementAdminAci: Aci? = nil,
        waitForMessageProcessing: Bool = false,
        isDeletingAccount: Bool = false,
        tx: DBWriteTransaction,
    ) -> Promise<[Promise<Void>]> {
        return SSKEnvironment.shared.localUserLeaveGroupJobQueueRef.addJob(
            groupThread: groupThread,
            replacementAdminAci: replacementAdminAci,
            waitForMessageProcessing: waitForMessageProcessing,
            isDeletingAccount: isDeletingAccount,
            tx: tx,
        )
    }

    public static func leaveGroupOrDeclineInviteAsyncWithoutUI(groupThread: TSGroupThread, tx: DBWriteTransaction) {
        guard groupThread.groupModel.groupMembership.isLocalUserMemberOfAnyKind else {
            owsFailDebug("unexpectedly trying to leave group for which we're not a member.")
            return
        }

        tx.addSyncCompletion {
            Task {
                let databaseStorage = SSKEnvironment.shared.databaseStorageRef
                let leavePromise = await databaseStorage.awaitableWrite { tx in
                    return self.localLeaveGroupOrDeclineInvite(groupThread: groupThread, tx: tx)
                }
                do {
                    _ = try await leavePromise.awaitable()
                } catch {
                    owsFailDebug("Couldn't leave group: \(error)")
                }
            }
        }
    }

    // MARK: - Remove From Group / Revoke Invite

    public static func removeFromGroupOrRevokeInviteV2(
        groupModel: TSGroupModelV2,
        serviceIds: [ServiceId],
    ) async throws {
        try await updateGroupV2(groupModel: groupModel, description: "Remove from group or revoke invite") { groupChangeSet in
            for serviceId in serviceIds {
                owsAssertDebug(!groupModel.groupMembership.isRequestingMember(serviceId))
                groupChangeSet.removeMember(serviceId)
            }
        }
    }

    public static func revokeInvalidInvites(groupModel: TSGroupModelV2) async throws {
        try await updateGroupV2(groupModel: groupModel, description: "Revoke invalid invites") { groupChangeSet in
            groupChangeSet.revokeInvalidInvites()
        }
    }

    // MARK: - Change Member Role

    public static func changeMemberRoleV2(
        groupModel: TSGroupModelV2,
        aci: Aci,
        role: TSGroupMemberRole,
    ) async throws {
        try await updateGroupV2(groupModel: groupModel, description: "Change member role") { groupChangeSet in
            groupChangeSet.changeRoleForMember(aci, role: role)
        }
    }

    // MARK: - Change Group Access

    public static func changeGroupAttributesAccessV2(groupModel: TSGroupModelV2, access: GroupV2Access) async throws {
        try await updateGroupV2(groupModel: groupModel, description: "Change group attributes access") { groupChangeSet in
            groupChangeSet.setAccessForAttributes(access)
        }
    }

    public static func changeGroupMembershipAccessV2(groupModel: TSGroupModelV2, access: GroupV2Access) async throws {
        try await updateGroupV2(groupModel: groupModel, description: "Change group membership access") { groupChangeSet in
            groupChangeSet.setAccessForMembers(access)
        }
    }

    // MARK: - Group Links

    public static func updateLinkModeV2(groupModel: TSGroupModelV2, linkMode: GroupsV2LinkMode) async throws {
        try await updateGroupV2(groupModel: groupModel, description: "Change group link mode") { groupChangeSet in
            groupChangeSet.setLinkMode(linkMode)
        }
    }

    public static func resetLinkV2(groupModel: TSGroupModelV2) async throws {
        try await updateGroupV2(groupModel: groupModel, description: "Rotate invite link password") { groupChangeSet in
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
        secretParams: GroupSecretParams,
        inviteLinkPassword: Data,
        downloadedAvatar: (avatarUrlPath: String, avatarData: Data?)?,
    ) async throws {
        let groupId = try secretParams.getPublicParams().getGroupIdentifier()

        try await ensureLocalProfileHasCommitmentIfNecessary()
        try await SSKEnvironment.shared.groupsV2Ref.joinGroupViaInviteLink(
            secretParams: secretParams,
            inviteLinkPassword: inviteLinkPassword,
            downloadedAvatar: downloadedAvatar,
        )

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            SSKEnvironment.shared.profileManagerRef.addGroupId(
                toProfileWhitelist: groupId.serialize(),
                userProfileWriter: .localUser,
                transaction: transaction,
            )
        }
    }

    public static func acceptOrDenyMemberRequestsV2(
        groupModel: TSGroupModelV2,
        aci: Aci,
        shouldAccept: Bool,
    ) async throws {
        let description = (shouldAccept ? "Accept group member request" : "Deny group member request")
        try await updateGroupV2(groupModel: groupModel, description: description) { groupChangeSet in
            if shouldAccept {
                groupChangeSet.addMember(aci)
            } else {
                groupChangeSet.removeMember(aci)
            }
        }
    }

    public static func cancelRequestToJoin(groupModel: TSGroupModelV2) async throws {
        let description = "Cancel Request to Join"
        try await Promise.wrapAsync {
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
        try await updateGroupV2(groupModel: groupModel, description: "Update isAnnouncementsOnly") { groupChangeSet in
            groupChangeSet.setIsAnnouncementsOnly(isAnnouncementsOnly)
        }
    }

    // MARK: - Local profile key

    /// - Returns: A list of Promises for sending the group update message(s).
    /// Each Promise represents sending a message to one or more recipients.
    @discardableResult
    public static func updateLocalProfileKey(groupModel: TSGroupModelV2) async throws -> [Promise<Void>] {
        return try await updateGroupV2(groupModel: groupModel, description: "Update local profile key") { changes in
            changes.setShouldUpdateLocalProfileKey()
        }
    }

    // MARK: - Removed from Group or Invite Revoked

    public static func handleNotInGroup(groupId: GroupIdentifier) async {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef

        do {
            let groupThread = databaseStorage.read { tx in TSGroupThread.fetch(forGroupId: groupId, tx: tx) }
            guard let groupThread else {
                // We may be be trying to restore a group from storage service
                // that we are no longer a member of.
                Logger.warn("Missing group in database.")
                return
            }

            let groupModel = groupThread.groupModel

            // If this is a join request placeholder, we don't expect to have access to
            // the group, but we should have access to the invite link preview without
            // needing to provide an inviteLinkPassword.
            if
                let groupModelV2 = groupModel as? TSGroupModelV2,
                groupModelV2.isJoinRequestPlaceholder,
                groupModelV2.groupMembership.isLocalUserRequestingMember
            {
                do {
                    let secretParams = try groupModelV2.secretParams()
                    _ = try await SSKEnvironment.shared.groupsV2Ref.fetchGroupInviteLinkPreview(
                        inviteLinkPassword: nil,
                        groupSecretParams: secretParams,
                    )
                    // We still have access to the group, so do nothing.
                    return
                } catch GroupsV2Error.localUserIsNotARequestingMember {
                    // Expected if our request has been cancelled. In this scenario, we should
                    // remove ourselves from the local group state.
                } catch {
                    // We don't know what went wrong; do nothing.
                    owsFailDebug("Error: \(error)")
                    return
                }
            }
        }

        await databaseStorage.awaitableWrite { tx in
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
                owsFailDebug("Missing localIdentifiers.")
                return
            }
            guard let groupThread = TSGroupThread.fetch(forGroupId: groupId, tx: tx) else {
                owsFailDebug("Couldn't fetch thread that's guaranteed to exist.")
                return
            }

            let groupModel = groupThread.groupModel

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
                updateExistingGroupThreadInDatabaseAndCreateInfoMessage(
                    groupThread: groupThread,
                    newGroupModel: newGroupModel,
                    newDisappearingMessageToken: nil,
                    newlyLearnedPniToAciAssociations: [:],
                    groupUpdateSource: .unknown,
                    infoMessagePolicy: .insert,
                    localIdentifiers: localIdentifiers,
                    spamReportingMetadata: .createdByLocalAction,
                    transaction: tx,
                )
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
    }

    // MARK: - Messages

    public static func sendGroupUpdateMessage(
        groupId: GroupIdentifier,
        isUrgent: Bool = false,
        isDeletingAccount: Bool = false,
        groupChangeProtoData: Data? = nil,
    ) async -> Promise<Void> {
        return await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction -> Promise<Void> in
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore

            guard let thread = TSGroupThread.fetch(forGroupId: groupId, tx: transaction) else {
                return Promise(error: OWSAssertionError("couldn't send group update message to missing thread"))
            }

            let message = OutgoingGroupUpdateMessage(
                in: thread,
                groupMetaMessage: .update,
                expiresInSeconds: dmConfigurationStore.durationSeconds(for: thread, tx: transaction),
                groupChangeProtoData: groupChangeProtoData,
                additionalRecipients: Self.invitedMembers(in: thread),
                isUrgent: isUrgent,
                isDeletingAccount: isDeletingAccount,
                transaction: transaction,
            )
            // "changeActionsProtoData" is _not_ an attachment, it is just put on
            // the outgoing proto directly.
            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: message,
            )

            return SSKEnvironment.shared.messageSenderJobQueueRef.add(.promise, message: preparedMessage, transaction: transaction)
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
                expiresInSeconds: dmConfigurationStore.durationSeconds(for: thread, tx: tx),
                additionalRecipients: Self.invitedMembers(in: thread),
                isUrgent: true,
                transaction: tx,
            )
            // "changeActionsProtoData" is _not_ an attachment, it is just put on
            // the outgoing proto directly.
            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: message,
            )
            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
        }
    }

    private static func invitedMembers(in thread: TSGroupThread) -> some Sequence<ServiceId> {
        thread.groupModel.groupMembership.invitedMembers.compactMap(\.serviceId)
    }

    public static func shouldMessageHaveAdditionalRecipients(
        _ message: TSOutgoingMessage,
        groupThread: TSGroupThread,
    ) -> Bool {
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

    public enum InfoMessagePolicy {
        case insert
        case doNotInsert
    }

    // If disappearingMessageToken is nil, don't update the disappearing messages configuration.
    private static func insertGroupThreadInDatabaseAndCreateInfoMessage(
        groupModel: TSGroupModelV2,
        disappearingMessageToken: DisappearingMessageToken?,
        groupUpdateSource: GroupUpdateSource,
        infoMessagePolicy: InfoMessagePolicy,
        localIdentifiers: LocalIdentifiers,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        transaction: DBWriteTransaction,
    ) -> TSGroupThread {

        if let groupThread = TSGroupThread.fetch(groupId: groupModel.groupId, transaction: transaction) {
            owsFail("Inserting existing group thread: \(groupThread.logString).")
        }

        let groupThread = DependenciesBridge.shared.threadStore.createGroupThread(
            groupModel: groupModel,
            tx: transaction,
        )

        let newDisappearingMessageToken = disappearingMessageToken ?? DisappearingMessageToken.disabledToken
        _ = updateDisappearingMessageConfiguration(
            newToken: newDisappearingMessageToken,
            groupThread: groupThread,
            tx: transaction,
        )

        autoWhitelistGroupIfNecessary(
            oldGroupModel: nil,
            newGroupModel: groupModel,
            groupUpdateSource: groupUpdateSource,
            localIdentifiers: localIdentifiers,
            tx: transaction,
        )

        switch infoMessagePolicy {
        case .insert:
            insertGroupUpdateInfoMessageForNewGroup(
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: spamReportingMetadata,
                groupThread: groupThread,
                groupModel: groupModel,
                disappearingMessageToken: newDisappearingMessageToken,
                groupUpdateSource: groupUpdateSource,
                transaction: transaction,
            )
        case .doNotInsert:
            break
        }

        notifyStorageServiceOfInsertedGroup(
            groupModel: groupModel,
            transaction: transaction,
        )

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
        infoMessagePolicy: InfoMessagePolicy,
        localIdentifiers: LocalIdentifiers,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        transaction: DBWriteTransaction,
    ) -> TSGroupThread {
        if DebugFlags.internalLogging {
            let groupId = try? newGroupModel.secretParams().getPublicParams().getGroupIdentifier()
            Logger.info("Upserting thread for \(groupId as Optional); didAddLocalUser? \(didAddLocalUserToV2Group); groupUpdateSource: \(groupUpdateSource)")
        }

        if let groupThread = TSGroupThread.fetch(groupId: newGroupModel.groupId, transaction: transaction) {
            updateExistingGroupThreadInDatabaseAndCreateInfoMessage(
                groupThread: groupThread,
                newGroupModel: newGroupModel,
                newDisappearingMessageToken: newDisappearingMessageToken,
                newlyLearnedPniToAciAssociations: newlyLearnedPniToAciAssociations,
                groupUpdateSource: groupUpdateSource,
                infoMessagePolicy: infoMessagePolicy,
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: spamReportingMetadata,
                transaction: transaction,
            )
            return groupThread
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

            if DebugFlags.internalLogging {
                let groupId = try? newGroupModel.secretParams().getPublicParams().getGroupIdentifier()
                Logger.info("Inserting thread for \(groupId as Optional); shouldAttributeAuthor? \(shouldAttributeAuthor)")
            }

            insertRecipients(
                addedMembers: newGroupModel.groupMembership.allMembersOfAnyKindServiceIds,
                localIdentifiers: localIdentifiers,
                tx: transaction,
            )

            return insertGroupThreadInDatabaseAndCreateInfoMessage(
                groupModel: newGroupModel,
                disappearingMessageToken: newDisappearingMessageToken,
                groupUpdateSource: shouldAttributeAuthor ? groupUpdateSource : .unknown,
                infoMessagePolicy: infoMessagePolicy,
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: spamReportingMetadata,
                transaction: transaction,
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
        groupThread: TSGroupThread,
        newGroupModel: TSGroupModel,
        newDisappearingMessageToken: DisappearingMessageToken?,
        newlyLearnedPniToAciAssociations: [Pni: Aci],
        groupUpdateSource: GroupUpdateSource,
        infoMessagePolicy: InfoMessagePolicy = .insert,
        localIdentifiers: LocalIdentifiers,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        transaction: DBWriteTransaction,
    ) {
        guard
            let newGroupModel = newGroupModel as? TSGroupModelV2,
            let oldGroupModel = groupThread.groupModel as? TSGroupModelV2
        else {
            owsFail("[GV1] Should be impossible to update a V1 group!")
        }

        // Step 2: Update DM configuration in database, if necessary.
        let updateDMResult: DisappearingMessagesConfigurationStore.SetTokenResult
        if let newDisappearingMessageToken {
            // shouldInsertInfoMessage is false because we only want to insert a
            // single info message if we update both DM config and thread model.
            updateDMResult = updateDisappearingMessageConfiguration(
                newToken: newDisappearingMessageToken,
                groupThread: groupThread,
                tx: transaction,
            )
        } else {
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let dmConfiguration = dmConfigurationStore.fetchOrBuildDefault(for: .thread(groupThread), tx: transaction)

            updateDMResult = (
                oldConfiguration: dmConfiguration,
                newConfiguration: dmConfiguration,
            )
        }

        do {
            let oldMembers = oldGroupModel.membership.allMembersOfAnyKindServiceIds
            let newMembers = newGroupModel.membership.allMembersOfAnyKindServiceIds

            insertRecipients(
                addedMembers: newMembers.subtracting(oldMembers),
                localIdentifiers: localIdentifiers,
                tx: transaction,
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

            // If somebody else was removed, reset the sender key session.
            let removedMembers = oldMembers.subtracting(newMembers)
            if !removedMembers.subtracting([localIdentifiers.aci]).isEmpty {
                SSKEnvironment.shared.senderKeyStoreRef.resetSenderKeySession(for: groupThread, transaction: transaction)
            }

            if
                DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction).isPrimaryDevice ?? true,
                oldGroupModel.membership.hasProfileKeyInGroup(serviceId: localIdentifiers.aci),
                !newGroupModel.membership.hasProfileKeyInGroup(serviceId: localIdentifiers.aci)
            {
                // If our profile key is no longer exposed to the group - for
                // example, we've left the group - check if the group had any
                // blocked users to whom our profile key was exposed.
                var shouldRotateProfileKey = false
                for member in oldMembers {
                    let memberAddress = SignalServiceAddress(member)

                    if

                        SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(memberAddress, transaction: transaction)
                        || DependenciesBridge.shared.recipientHidingManager.isHiddenAddress(memberAddress, tx: transaction)
                        ,
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
                            localAci: localIdentifiers.aci,
                            tx: transaction,
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
        guard newGroupModel.revision >= oldGroupModel.revision else {
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
            return
        }

        autoWhitelistGroupIfNecessary(
            oldGroupModel: oldGroupModel,
            newGroupModel: newGroupModel,
            groupUpdateSource: groupUpdateSource,
            localIdentifiers: localIdentifiers,
            tx: transaction,
        )

        let hasUserFacingUpdate: Bool = (
            newGroupModel.hasUserFacingChangeCompared(to: oldGroupModel)
                || updateDMResult.newConfiguration != updateDMResult.oldConfiguration,
        )

        groupThread.update(
            with: newGroupModel,
            shouldUpdateChatListUi: hasUserFacingUpdate,
            transaction: transaction,
        )

        let shouldInsertInfoMessages: Bool
        switch infoMessagePolicy {
        case .insert:
            shouldInsertInfoMessages = true
        case .doNotInsert:
            shouldInsertInfoMessages = false
        }

        if hasUserFacingUpdate, shouldInsertInfoMessages {
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
                transaction: transaction,
            )
        }
    }

    private static func mutualGroupThreads(
        with member: ServiceId,
        localAci: Aci,
        tx: DBReadTransaction,
    ) -> [TSGroupThread] {
        return DependenciesBridge.shared.groupMemberStore
            .groupThreadIds(
                withFullMember: member,
                tx: tx,
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
        tx: DBReadTransaction,
    ) -> Bool {
        let mutualGroupThreads = Self.mutualGroupThreads(
            with: member,
            localAci: localAci,
            tx: tx,
        )
        return !mutualGroupThreads.isEmpty
    }

    private static func insertRecipients(addedMembers: Set<ServiceId>, localIdentifiers: LocalIdentifiers, tx: DBWriteTransaction) {
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        let recipientManager = DependenciesBridge.shared.recipientManager
        for addedMember in addedMembers {
            if localIdentifiers.contains(serviceId: addedMember) {
                continue
            }
            var (inserted, recipient) = recipientFetcher.fetchOrCreateImpl(serviceId: addedMember, tx: tx)
            if inserted {
                recipientManager.markAsRegisteredAndSave(&recipient, shouldUpdateStorageService: true, tx: tx)
            }
        }
    }

    // MARK: - Storage Service

    private static func notifyStorageServiceOfInsertedGroup(
        groupModel: TSGroupModel,
        transaction: DBReadTransaction,
    ) {
        guard let groupModel = groupModel as? TSGroupModelV2 else {
            // We only need to notify the storage service about v2 groups.
            return
        }
        guard
            !SSKEnvironment.shared.groupsV2Ref.isGroupKnownToStorageService(
                groupModel: groupModel,
                transaction: transaction,
            )
        else {
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
        tx: DBWriteTransaction,
    ) {
        let justAdded = wasLocalUserJustAddedToTheGroup(
            oldGroupModel: oldGroupModel,
            newGroupModel: newGroupModel,
            localIdentifiers: localIdentifiers,
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

        if DebugFlags.internalLogging {
            let groupId = try? (newGroupModel as? TSGroupModelV2)?.secretParams().getPublicParams().getGroupIdentifier()
            Logger.info("Checking if group should be auto whitelisted \(groupId as Optional); groupUpdateSource: \(groupUpdateSource); shouldAddToWhitelist? \(shouldAddToWhitelist)")
        }

        guard shouldAddToWhitelist else {
            return
        }

        // Ensure the thread is in our profile whitelist if we're a member of the group.
        // We don't want to do this if we're just a pending member or are leaving/have
        // already left the group.
        SSKEnvironment.shared.profileManagerRef.addGroupId(
            toProfileWhitelist: newGroupModel.groupId,
            userProfileWriter: .localUser,
            transaction: tx,
        )
    }

    private static func wasLocalUserJustAddedToTheGroup(
        oldGroupModel: TSGroupModel?,
        newGroupModel: TSGroupModel,
        localIdentifiers: LocalIdentifiers,
    ) -> Bool {
        let oldFullMember = oldGroupModel?.groupMembership.isFullMember(localIdentifiers.aci) == true
        let newFullMember = newGroupModel.groupMembership.isFullMember(localIdentifiers.aci)
        if DebugFlags.internalLogging {
            let groupId = try? (newGroupModel as? TSGroupModelV2)?.secretParams().getPublicParams().getGroupIdentifier()
            Logger.info("Checking if local user was added to \(groupId as Optional); oldGroupModel? \(oldGroupModel != nil); oldFullMember? \(oldFullMember); newFullMember: \(newFullMember)")
        }
        return !oldFullMember && newFullMember
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
        tx: DBWriteTransaction,
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
            tx: tx,
        )
    }

    private static let localProfileCommitmentQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    /// Ensure that we have a profile key commitment for our local profile
    /// available on the service.
    ///
    /// We (and other clients) need profile key credentials for group members in
    /// order to perform GV2 operations. However, other clients can't request
    /// our profile key credential from the service until we've uploaded a profile
    /// key commitment to the service.
    public static func ensureLocalProfileHasCommitmentIfNecessary() async throws {
        try await localProfileCommitmentQueue.run {
            try await _ensureLocalProfileHasCommitmentIfNecessary()
        }
    }

    private static func _ensureLocalProfileHasCommitmentIfNecessary() async throws {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let registeredState = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()

        func hasProfileKeyCredential() -> Bool {
            return SSKEnvironment.shared.databaseStorageRef.read { tx in
                let localAci = registeredState.localIdentifiers.aci
                return SSKEnvironment.shared.groupsV2Ref.hasProfileKeyCredential(for: localAci, transaction: tx)
            }
        }

        guard !hasProfileKeyCredential() else {
            return
        }

        // If we don't have a local profile key credential we should first
        // check if it is simply expired, by asking for a new one (which we
        // would get as part of fetching our local profile).
        _ = try await SSKEnvironment.shared.profileManagerRef.fetchLocalUsersProfile(authedAccount: .implicit())

        guard !hasProfileKeyCredential() else {
            return
        }

        guard registeredState.isPrimary, CurrentAppContext().isMainApp else {
            Logger.warn("Skipping upload of local profile key commitment, not in main app!")
            return
        }

        // We've never uploaded a profile key commitment - do so now.
        Logger.info("No profile key credential available for local account - uploading local profile!")
        let uploadAndFetchPromise = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            SSKEnvironment.shared.profileManagerRef.reuploadLocalProfile(
                unsavedRotatedProfileKey: nil,
                mustReuploadAvatar: false,
                authedAccount: .implicit(),
                tx: tx,
            )
        }
        try await uploadAndFetchPromise.awaitable()
    }
}

// MARK: -

public extension GroupManager {
    class func waitForMessageFetchingAndProcessingWithTimeout() async throws {
        do {
            return try await withCooperativeTimeout(seconds: GroupManager.groupUpdateTimeoutDuration) {
                try await SSKEnvironment.shared.messageProcessorRef.waitForFetchingAndProcessing()
            }
        } catch is CooperativeTimeoutError {
            throw GroupsV2Error.timeout
        }
    }
}

// MARK: - Add/Invite to group

extension GroupManager {
    public static func addOrInvite(
        serviceIds: [ServiceId],
        toExistingGroup existingGroupModel: TSGroupModel,
    ) async throws {
        guard let existingGroupModel = existingGroupModel as? TSGroupModelV2 else {
            owsFail("[GV1] Mutations on V1 groups should be impossible!")
        }

        try await updateGroupV2(
            groupModel: existingGroupModel,
            description: "Add/Invite new non-admin members",
        ) { groupChangeSet in
            for serviceId in serviceIds {
                groupChangeSet.addMember(serviceId)
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
        inExistingGroup existingGroupModel: TSGroupModel,
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
                groupSecretParams: try existingGroupModel.secretParams(),
            )
        }()

        var message = "Update attributes:"
        message += title != nil ? " title" : ""
        message += description != nil ? " description" : ""
        message += avatarData != nil ? " settingAvatarData" : " clearingAvatarData"

        try await self.updateGroupV2(
            groupModel: existingGroupModel,
            description: message,
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
                let avatarData,
                let avatarUrlPath
            {
                groupChangeSet.setAvatar((data: avatarData, urlPath: avatarUrlPath))
            } else if
                avatarData == nil,
                existingGroupModel.avatarUrlPath != nil
            {
                groupChangeSet.setAvatar(nil)
            }
        }
    }
}
