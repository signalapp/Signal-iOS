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
    public static let changeProtoEpoch: UInt32 = 4

    // This matches kOversizeTextMessageSizeThreshold.
    public static let maxEmbeddedChangeProtoLength: UInt = 2 * 1024

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
        guard groupId.count == kGroupIdLengthV1 ||
                groupId.count == kGroupIdLengthV2 else {
            Logger.warn("Invalid groupId: \(groupId.count) != \(kGroupIdLengthV1), \(kGroupIdLengthV2)")
            return false
        }
        return true
    }

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

    public static func canUseV2(for members: Set<SignalServiceAddress>) -> Bool {

        for recipientAddress in members {
            guard doesUserSupportGroupsV2(address: recipientAddress) else {
                Logger.warn("Creating legacy group; member missing UUID.")
                return false
            }
            // GroupsV2 TODO: We should finalize the exact decision-making process here.
            // Should having a profile key credential figure in? At least for a while?
        }
        return true
    }

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

    @objc
    public static var defaultGroupsVersion: GroupsVersion {
        .V2
    }

    // MARK: - Create New Group
    //
    // "New" groups are being created for the first time; they might need to be created on the service.

    // NOTE: groupId param should only be set for tests.
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
            // If we might create a v2 group,
            // try to obtain profile key credentials for all group members
            // including ourself, unless we already have them on hand.
            firstly { () -> Promise<Void> in
                self.groupsV2Swift.tryToFetchProfileKeyCredentials(
                    for: groupMembership.allMembersOfAnyKind.compactMap { $0.uuid },
                    ignoreMissingProfiles: false,
                    forceRefresh: false
                )
            }.map(on: DispatchQueue.global()) { _ -> GroupMembership in
                return groupMembership
            }
        }.map(on: DispatchQueue.global()) { (proposedGroupMembership: GroupMembership) throws -> TSGroupModel in
            let groupAccess = GroupAccess.defaultForV2
            let groupModel = try self.databaseStorage.read { (transaction) throws -> TSGroupModel in
                // Before we create a v2 group, we need to separate out the
                // pending and non-pending members.  If we already know we're
                // going to create a v1 group, we shouldn't separate them.
                let groupMembership = self.separateInvitedMembersForNewGroup(
                    withMembership: proposedGroupMembership,
                    transaction: transaction
                )

                guard groupMembership.isFullMember(localAddress) else {
                    throw OWSAssertionError("Missing localAddress.")
                }

                // Build the "initial" group model.
                // This will finalize the immutable aspects of the group, e.g.:
                //
                // * Is it v1 or v2?
                // * If it is v2, what is the group secret.
                //
                // This might not be the "final" model - the
                // avatar url path might be filled in below.
                var builder = TSGroupModelBuilder()
                builder.groupId = groupId
                builder.name = name
                builder.avatarData = avatarData
                builder.avatarUrlPath = nil
                builder.groupMembership = groupMembership
                builder.groupAccess = groupAccess
                builder.newGroupSeed = newGroupSeed
                return try builder.build()
            }
            return groupModel
        }.then(on: DispatchQueue.global()) { (proposedGroupModel: TSGroupModel) -> Promise<TSGroupModel> in
            guard let proposedGroupModelV2 = proposedGroupModel as? TSGroupModelV2 else {
                // We don't need to upload avatars for v1 groups.
                return Promise.value(proposedGroupModel)
            }
            guard let avatarData = avatarData else {
                // No avatar to upload.
                return Promise.value(proposedGroupModel)
            }
            // Upload avatar.
            return firstly {
                self.groupsV2Swift.uploadGroupAvatar(avatarData: avatarData,
                                                     groupSecretParamsData: proposedGroupModelV2.secretParamsData)
            }.map(on: DispatchQueue.global()) { (avatarUrlPath: String) -> TSGroupModel in
                // Fill in the avatarUrl on the group model.
                var builder = proposedGroupModel.asBuilder
                builder.avatarUrlPath = avatarUrlPath
                return try builder.build()
            }
        }.then(on: DispatchQueue.global()) { (proposedGroupModel: TSGroupModel) -> Promise<TSGroupModel> in
            guard let proposedGroupModelV2 = proposedGroupModel as? TSGroupModelV2 else {
                // v1 groups don't need to be created on the service.
                return Promise.value(proposedGroupModel)
            }
            return firstly {
                self.groupsV2Swift.createNewGroupOnService(groupModel: proposedGroupModelV2,
                                                           disappearingMessageToken: disappearingMessageToken)
            }.then(on: DispatchQueue.global()) { _ in
                self.groupsV2Swift.fetchCurrentGroupV2Snapshot(groupModel: proposedGroupModelV2)
            }.map(on: DispatchQueue.global()) { (groupV2Snapshot: GroupV2Snapshot) throws -> TSGroupModel in
                let createdGroupModel = try self.databaseStorage.write { (transaction) throws -> TSGroupModel in
                    var builder = try TSGroupModelBuilder.builderForSnapshot(groupV2Snapshot: groupV2Snapshot,
                                                                             transaction: transaction)
                    builder.wasJustCreatedByLocalUser = true
                    return try builder.build()
                }
                if proposedGroupModel != createdGroupModel {
                    Logger.verbose("proposedGroupModel: \(proposedGroupModel.debugDescription)")
                    Logger.verbose("createdGroupModel: \(createdGroupModel.debugDescription)")
                    if DebugFlags.groupsV2ignoreCorruptInvites {
                        Logger.warn("Proposed group model does not match created group model.")
                    } else {
                        owsFailDebug("Proposed group model does not match created group model.")
                    }
                }
                return createdGroupModel
            }
        }.then(on: DispatchQueue.global()) { (groupModelParam: TSGroupModel) -> Promise<TSGroupThread> in
            var groupModel = groupModelParam
            // We're creating this thread, we added ourselves
            if groupModel.groupsVersion == .V1 {
                groupModel = Self.setAddedByAddress(groupModel: groupModel,
                                                    addedByAddress: self.tsAccountManager.localAddress)
            }

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
    // * We know their UUID.
    // * We know their profile key.
    // * We have a profile key credential for them.
    private static func separateInvitedMembersForNewGroup(withMembership newGroupMembership: GroupMembership,
                                                          transaction: SDSAnyReadTransaction) -> GroupMembership {
        guard let localUuid = tsAccountManager.localUuid else {
            owsFailDebug("Missing localUuid.")
            return newGroupMembership
        }
        let localAddress = SignalServiceAddress(uuid: localUuid)
        var builder = GroupMembership.Builder()

        guard canUseV2(for: newGroupMembership.allMembersOfAnyKind) else {
            // We should never be in this position anymore, since V1 groups are
            // dead, but we do this just in case until we revisit the GV1 code
            // more holistically.
            //
            // If any member of a new group doesn't support groups v2,
            // we're going to create a v1 group.  In that case, we
            // don't want to separate out pending members.
            return newGroupMembership
        }

        let newMembers = newGroupMembership.allMembersOfAnyKind

        // We only need to separate new members.
        for address in newMembers {
            guard doesUserSupportGroupsV2(address: address) else {
                // Members of v2 groups must support groups v2.
                // This should never happen.  We prevent this
                // when creating new groups above by checking
                // canUseV2(...).  We will prevent this when
                // updating existing groups in the UI.
                //
                // GroupsV2 TODO: This should throw after we require
                // all new groups to be v2 groups.
                owsFailDebug("Invalid address: \(address)")
                continue
            }

            // We must call this _after_ we try to fetch profile key credentials for
            // all members.
            let isPending = !groupsV2Swift.hasProfileKeyCredential(for: address,
                                                                   transaction: transaction)
            guard let role = newGroupMembership.role(for: address) else {
                owsFailDebug("Missing role: \(address)")
                continue
            }

            // If groupsV2forceInvites is set, we invite other members
            // instead of adding them.
            if address != localAddress &&
                DebugFlags.groupsV2forceInvites.get() {
                builder.addInvitedMember(address, role: role, addedByUuid: localUuid)
            } else if isPending {
                builder.addInvitedMember(address, role: role, addedByUuid: localUuid)
            } else {
                builder.addFullMember(address, role: role)
            }
        }
        return builder.build()
    }

    // success and failure are invoked on the main thread.
    @objc
    public static func localCreateNewGroupObjc(members: [SignalServiceAddress],
                                               groupId: Data?,
                                               name: String,
                                               avatarData: Data?,
                                               disappearingMessageToken: DisappearingMessageToken,
                                               newGroupSeed: NewGroupSeed?,
                                               shouldSendMessage: Bool,
                                               success: @escaping (TSGroupThread) -> Void,
                                               failure: @escaping (Error) -> Void) {
        firstly {
            localCreateNewGroup(members: members,
                                groupId: groupId,
                                name: name,
                                avatarData: avatarData,
                                disappearingMessageToken: disappearingMessageToken,
                                newGroupSeed: newGroupSeed,
                                shouldSendMessage: shouldSendMessage)
        }.done { thread in
            success(thread)
        }.catch { error in
            failure(error)
        }
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
    public static let shouldForceV1Groups = AtomicBool(false)

    @objc
    public class func forceV1Groups() {
        shouldForceV1Groups.set(true)
    }

    @objc
    public static func createGroupForTestsObjc(members: [SignalServiceAddress],
                                               name: String? = nil,
                                               avatarData: Data? = nil,
                                               transaction: SDSAnyWriteTransaction) -> TSGroupThread {
        do {
            let groupsVersion = (shouldForceV1Groups.get()
                                    ? .V1
                                    : self.defaultGroupsVersion)
            return try createGroupForTests(members: members,
                                           name: name,
                                           avatarData: avatarData,
                                           groupsVersion: groupsVersion,
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
                                           groupsVersion: GroupsVersion? = nil,
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
        return try remoteUpsertExistingGroup(groupModel: groupModel,
                                             disappearingMessageToken: nil,
                                             groupUpdateSourceAddress: localAddress,
                                             transaction: transaction).groupThread
    }

    #endif

    // MARK: - Upsert Existing Group
    //
    // "Existing" groups have already been created, we just need to make sure they're in the database.
    //
    // If disappearingMessageToken is nil, don't update the disappearing messages configuration.
    @objc
    public static func remoteUpsertExistingGroupV1(groupId: Data,
                                                   name: String? = nil,
                                                   avatarData: Data? = nil,
                                                   members: [SignalServiceAddress],
                                                   disappearingMessageToken: DisappearingMessageToken?,
                                                   groupUpdateSourceAddress: SignalServiceAddress?,
                                                   infoMessagePolicy: InfoMessagePolicy = .always,
                                                   transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {

        guard isValidGroupId(groupId, groupsVersion: .V1) else {
            throw OWSAssertionError("Invalid group id.")
        }

        let groupMembership = GroupMembership(v1Members: Set(members))

        var builder = TSGroupModelBuilder()
        builder.groupId = groupId
        builder.name = name
        builder.avatarData = avatarData
        builder.avatarUrlPath = nil
        builder.groupMembership = groupMembership
        builder.groupsVersion = .V1
        let groupModel = try builder.build()

        return try remoteUpsertExistingGroup(groupModel: groupModel,
                                             disappearingMessageToken: disappearingMessageToken,
                                             groupUpdateSourceAddress: groupUpdateSourceAddress,
                                             infoMessagePolicy: infoMessagePolicy,
                                             transaction: transaction)
    }

    // If disappearingMessageToken is nil, don't update the disappearing messages configuration.
    public static func remoteUpsertExistingGroup(groupModel: TSGroupModel,
                                                 disappearingMessageToken: DisappearingMessageToken?,
                                                 groupUpdateSourceAddress: SignalServiceAddress?,
                                                 infoMessagePolicy: InfoMessagePolicy = .always,
                                                 transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {
        return try self.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: groupModel,
                                                                                     newDisappearingMessageToken: disappearingMessageToken,
                                                                                     groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                     canInsert: true,
                                                                                     didAddLocalUserToV2Group: false,
                                                                                     infoMessagePolicy: infoMessagePolicy,
                                                                                     transaction: transaction)
    }

    // MARK: - Update Existing Group (Remote)

    // Unlike remoteUpsertExistingGroupV1(), this method never inserts.
    //
    // If disappearingMessageToken is nil, don't update the disappearing messages configuration.
    @objc
    public static func remoteUpdateToExistingGroupV1(groupModel proposedGroupModel: TSGroupModel,
                                                     disappearingMessageToken: DisappearingMessageToken?,
                                                     groupUpdateSourceAddress: SignalServiceAddress?,
                                                     transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {
        let groupId = proposedGroupModel.groupId
        let updateInfo: UpdateInfoV1
        do {
            updateInfo = try updateInfoV1(groupModel: proposedGroupModel,
                                          transaction: transaction)
        } catch GroupsV2Error.redundantChange {
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("Missing groupThread.")
            }
            return UpsertGroupResult(action: .unchanged, groupThread: groupThread)
        }
        let newGroupModel = updateInfo.newGroupModel
        return try self.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                     newDisappearingMessageToken: disappearingMessageToken,
                                                                                     groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                     canInsert: false,
                                                                                     didAddLocalUserToV2Group: false,
                                                                                     transaction: transaction)
    }

    @objc
    public static func remoteUpdateAvatarToExistingGroupV1(groupModel oldGroupModel: TSGroupModel,
                                                           avatarData: Data?,
                                                           groupUpdateSourceAddress: SignalServiceAddress?,
                                                           transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {
        var builder = oldGroupModel.asBuilder
        builder.avatarData = avatarData
        builder.avatarUrlPath = nil
        let newGroupModel = try builder.build()
        return try remoteUpdateToExistingGroupV1(groupModel: newGroupModel,
                                                 disappearingMessageToken: nil,
                                                 groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                 transaction: transaction)

    }

    // MARK: - Update Existing Group

    private struct UpdateInfoV1 {
        let groupId: Data
        let newGroupModel: TSGroupModel
    }

    fileprivate static func localUpdateExistingGroupV1(
        groupModel proposedGroupModel: TSGroupModel,
        groupUpdateSourceAddress: SignalServiceAddress?
    ) -> Promise<TSGroupThread> {

        return self.databaseStorage.write(.promise) { (transaction) throws -> UpsertGroupResult in
            let updateInfo = try self.updateInfoV1(groupModel: proposedGroupModel,
                                                   transaction: transaction)
            let newGroupModel = updateInfo.newGroupModel
            let upsertGroupResult = try self.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                                          newDisappearingMessageToken: nil,
                                                                                                          groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                                          canInsert: false,
                                                                                                          didAddLocalUserToV2Group: false,
                                                                                                          transaction: transaction)

            return upsertGroupResult
        }.then(on: DispatchQueue.global()) { (upsertGroupResult: UpsertGroupResult) throws -> Promise<TSGroupThread> in
            let groupThread = upsertGroupResult.groupThread
            guard upsertGroupResult.action != .unchanged else {
                // Don't bother sending a message if the update was redundant.
                return Promise.value(groupThread)
            }
            return self.sendGroupUpdateMessage(thread: groupThread)
                .map(on: DispatchQueue.global()) { _ in
                    return groupThread
                }
        }
    }

    private static func updateInfoV1(groupModel proposedGroupModel: TSGroupModel,
                                     transaction: SDSAnyReadTransaction) throws -> UpdateInfoV1 {
        let groupId = proposedGroupModel.groupId
        guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            throw OWSAssertionError("Thread does not exist.")
        }
        let currentGroupModel = thread.groupModel
        guard currentGroupModel.groupsVersion == .V1 else {
            throw OWSAssertionError("Invalid groupsVersion.")
        }
        guard let localAddress = tsAccountManager.localAddress else {
            throw OWSAssertionError("Missing localAddress.")
        }

        // Always ensure we're a member of any v1 group we're updating.
        var builder = proposedGroupModel.groupMembership.asBuilder
        builder.remove(localAddress)
        builder.addFullMember(localAddress, role: .normal)
        let groupMembership = builder.build()

        var groupModelBuilder = proposedGroupModel.asBuilder
        groupModelBuilder.groupMembership = groupMembership
        let newGroupModel = try groupModelBuilder.build()

        if currentGroupModel.isEqual(to: newGroupModel, comparisonMode: .compareAll) {
            // Skip redundant update.
            throw GroupsV2Error.redundantChange
        }

        return UpdateInfoV1(groupId: groupId, newGroupModel: newGroupModel)
    }

    // MARK: - Disappearing Messages

    // This method works with v1 group threads and contact threads.
    @objc
    public static func remoteUpdateDisappearingMessages(withContactOrV1GroupThread thread: TSThread,
                                                        disappearingMessageToken: DisappearingMessageToken,
                                                        groupUpdateSourceAddress: SignalServiceAddress?,

                                                        transaction: SDSAnyWriteTransaction) {
        guard !thread.isGroupV2Thread else {
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
        enum Action: UInt {
            case updated
            case unchanged
        }

        let action: Action
        let oldDisappearingMessageToken: DisappearingMessageToken?
        let newDisappearingMessageToken: DisappearingMessageToken
        let newConfiguration: OWSDisappearingMessagesConfiguration
    }

    private static func updateDisappearingMessagesInDatabaseAndCreateMessages(token newToken: DisappearingMessageToken,
                                                                              thread: TSThread,
                                                                              shouldInsertInfoMessage: Bool,
                                                                              groupUpdateSourceAddress: SignalServiceAddress?,
                                                                              transaction: SDSAnyWriteTransaction) -> UpdateDMConfigurationResult {

        let oldConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: thread, transaction: transaction)
        let oldToken = oldConfiguration.asToken
        let hasUnsavedChanges = oldToken != newToken
        guard hasUnsavedChanges else {
            // Skip redundant updates.
            return UpdateDMConfigurationResult(action: .unchanged,
                                               oldDisappearingMessageToken: oldToken,
                                               newDisappearingMessageToken: newToken,
                                               newConfiguration: oldConfiguration)
        }
        let newConfiguration = oldConfiguration.applyToken(newToken, transaction: transaction)

        if shouldInsertInfoMessage {
            var remoteContactName: String?
            if let groupUpdateSourceAddress = groupUpdateSourceAddress,
               groupUpdateSourceAddress.isValid,
               !groupUpdateSourceAddress.isLocalAddress {
                remoteContactName = contactsManager.displayName(for: groupUpdateSourceAddress, transaction: transaction)
            }
            let infoMessage = OWSDisappearingConfigurationUpdateInfoMessage(thread: thread,
                                                                            configuration: newConfiguration,
                                                                            createdByRemoteName: remoteContactName,
                                                                            createdInExistingGroup: false)
            infoMessage.anyInsert(transaction: transaction)
        }

        databaseStorage.touch(thread: thread, shouldReindex: false, transaction: transaction)

        return UpdateDMConfigurationResult(action: .updated,
                                           oldDisappearingMessageToken: oldToken,
                                           newDisappearingMessageToken: newToken,
                                           newConfiguration: newConfiguration)
    }

    private static func sendDisappearingMessagesConfigurationMessage(updateResult: UpdateDMConfigurationResult,
                                                                     thread: TSThread,
                                                                     transaction: SDSAnyWriteTransaction) {
        guard updateResult.action == .updated else {
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
            guard let localUuid = tsAccountManager.localUuid else {
                throw OWSAssertionError("Missing localUuid.")
            }

            return updateGroupV2(groupModel: groupModel,
                                 description: "Accept invite") { groupChangeSet in
                groupChangeSet.promoteInvitedMember(localUuid)
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
            assert(replacementAdminUuid == nil)
            do {
                return Promise.value(try localLeaveGroupV1(
                    groupId: groupThread.groupId,
                    transaction: transaction
                ))
            } catch let error {
                return Promise(error: error)
            }
        }

        return localLeaveGroupV2OrDeclineInvite(
            groupThreadId: groupThread.uniqueId,
            replacementAdminUuid: replacementAdminUuid,
            waitForMessageProcessing: waitForMessageProcessing,
            transaction: transaction
        )
    }

    private static func localLeaveGroupV1(groupId: Data, transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {
        guard let localAddress = self.tsAccountManager.localAddress else {
            throw OWSAssertionError("Missing localAddress.")
        }

        guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            throw OWSAssertionError("Missing group.")
        }
        let oldGroupModel = groupThread.groupModel
        // Note that we consult allUsers which includes pending members.
        guard oldGroupModel.groupMembership.isMemberOfAnyKind(localAddress) else {
            throw OWSAssertionError("Local user is not a member of the group.")
        }

        sendGroupQuitMessage(inThread: groupThread, transaction: transaction)

        let hasMessages = groupThread.numberOfInteractions(transaction: transaction) > 0
        let infoMessagePolicy: InfoMessagePolicy = hasMessages ? .always : .never

        var groupMembershipBuilder = oldGroupModel.groupMembership.asBuilder
        groupMembershipBuilder.remove(localAddress)
        let newGroupMembership = groupMembershipBuilder.build()

        var builder = oldGroupModel.asBuilder
        builder.groupMembership = newGroupMembership
        var newGroupModel = try builder.build()

        // We're leaving, so clear out who added us. If we're re-added it may change.
        if newGroupModel.groupsVersion == .V1 {
            newGroupModel = Self.setAddedByAddress(groupModel: newGroupModel,
                                                   addedByAddress: nil)
        }

        let groupUpdateSourceAddress = localAddress
        let result = try self.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                      newDisappearingMessageToken: nil,
                                                                                      groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                      infoMessagePolicy: infoMessagePolicy,
                                                                                      transaction: transaction)
        return result.groupThread
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

    @objc
    public static func sendGroupUpdateMessageObjc(thread: TSGroupThread) -> AnyPromise {
        return AnyPromise(self.sendGroupUpdateMessage(thread: thread))
    }

    @objc
    public static func sendGroupUpdateMessageObjc(thread: TSGroupThread,
                                                  singleRecipient: SignalServiceAddress) {
        firstly {
            self.sendGroupUpdateMessage(thread: thread, singleRecipient: singleRecipient)
        }.done(on: DispatchQueue.global()) {
            Logger.verbose("")
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    public static func sendGroupUpdateMessage(thread: TSGroupThread,
                                              changeActionsProtoData: Data? = nil,
                                              singleRecipient: SignalServiceAddress? = nil) -> Promise<Void> {
        guard thread.isGroupV2Thread, !DebugFlags.groupsV2dontSendUpdates.get() else {
            return Promise.value(())
        }

        return databaseStorage.write(.promise) { transaction in
            let message = OutgoingGroupUpdateMessage(
                in: thread,
                groupMetaMessage: .update,
                expiresInSeconds: thread.disappearingMessagesDuration(with: transaction),
                changeActionsProtoData: changeActionsProtoData,
                additionalRecipients: singleRecipient == nil ? Self.invitedMembers(in: thread) : [],
                transaction: transaction
            )

            if let singleRecipient = singleRecipient {
                message.updateWithSending(toSingleGroupRecipient: singleRecipient, transaction: transaction)
            }

            Self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
        }
    }

    private static func sendDurableNewGroupMessage(forThread thread: TSGroupThread) -> Promise<Void> {
        guard thread.isGroupV2Thread, !DebugFlags.groupsV2dontSendUpdates.get() else {
            return Promise.value(())
        }

        return databaseStorage.write(.promise) { transaction in
            let message = OutgoingGroupUpdateMessage(
                in: thread,
                groupMetaMessage: .new,
                expiresInSeconds: thread.disappearingMessagesDuration(with: transaction),
                additionalRecipients: Self.invitedMembers(in: thread),
                transaction: transaction
            )
            Self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
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

    private static func sendGroupQuitMessage(inThread groupThread: TSGroupThread,
                                             transaction: SDSAnyWriteTransaction) {

        guard groupThread.groupModel.groupsVersion == .V1 else {
            return
        }

        let message = OutgoingGroupUpdateMessage(in: groupThread,
                                                 groupMetaMessage: .quit,
                                                 transaction: transaction)
        sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
    }

    public static func resendInvite(groupThread: TSGroupThread,
                                    transaction: SDSAnyWriteTransaction) {

        guard groupThread.groupModel.groupsVersion == .V2 else {
            return
        }

        let message = OutgoingGroupUpdateMessage(
            in: groupThread,
            groupMetaMessage: .update,
            additionalRecipients: Self.invitedOrRequestedMembers(in: groupThread),
            transaction: transaction
        )

        sskJobQueues.messageSenderJobQueue.add(
            .promise,
            message: message.asPreparer,
            isHighPriority: true,
            transaction: transaction
        ).done {
            Logger.info("Successfully sent message.")
        }.catch { error in
            owsFailDebug("Failed to send message with error: \(error)")
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
                                         groupUpdateSourceAddress: sourceAddress,
                                         transaction: transaction)
        default:
            break
        }

        notifyStorageServiceOfInsertedGroup(groupModel: groupModel,
                                            transaction: transaction)

        if DebugFlags.internalLogging {
            let dmConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: groupThread,
                                                                                           transaction: transaction)
            owsAssertDebug(dmConfiguration.asToken == newDisappearingMessageToken)
        }

        return groupThread
    }

    public static func replaceMigratedGroup(groupIdV1: Data,
                                            groupModelV2: TSGroupModelV2,
                                            disappearingMessageToken: DisappearingMessageToken,
                                            groupUpdateSourceAddress: SignalServiceAddress?,
                                            shouldSendMessage: Bool) -> Promise<TSGroupThread> {

        return firstly(on: DispatchQueue.global()) { () -> TSGroupThread in
            try databaseStorage.write { (transaction: SDSAnyWriteTransaction) -> TSGroupThread in
                try migrateGroupInDatabaseAndCreateInfoMessage(groupIdV1: groupIdV1,
                                                               groupModelV2: groupModelV2,
                                                               disappearingMessageToken: disappearingMessageToken,
                                                               groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                               transaction: transaction)
            }
        }.then(on: DispatchQueue.global()) { (groupThread: TSGroupThread) -> Promise<TSGroupThread> in
            guard shouldSendMessage else {
                return Promise.value(groupThread)
            }

            return firstly {
                sendGroupUpdateMessage(thread: groupThread)
            }.map(on: DispatchQueue.global()) { _ in
                return groupThread
            }
        }
    }

    private static func migrateGroupInDatabaseAndCreateInfoMessage(groupIdV1: Data,
                                                                   groupModelV2 proposedGroupModel: TSGroupModelV2,
                                                                   disappearingMessageToken: DisappearingMessageToken,
                                                                   groupUpdateSourceAddress: SignalServiceAddress?,
                                                                   transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {
        guard isV1GroupId(groupIdV1) else {
            throw OWSAssertionError("Invalid v1 group id.")
        }
        guard let groupThreadV1 = TSGroupThread.fetch(groupId: groupIdV1,
                                                      transaction: transaction) else {
            throw OWSAssertionError("Missing v1 thread.")
        }
        guard groupThreadV1.isGroupV1Thread else {
            throw OWSAssertionError("Invalid v1 thread.")
        }
        let oldGroupModelV1 = groupThreadV1.groupModel
        guard oldGroupModelV1.groupsVersion == .V1 else {
            throw OWSAssertionError("Invalid v1 group model.")
        }

        var groupModelBuilder = proposedGroupModel.asBuilder
        // Set the wasJustMigrated flag on the model.
        groupModelBuilder.wasJustMigrated = true
        // Check for dropped members.
        let droppedMembers = Set(oldGroupModelV1.groupMembership.allMembersOfAnyKind).subtracting(proposedGroupModel.groupMembership.allMembersOfAnyKind)
        if !droppedMembers.isEmpty {
            // Set droppedMembers on the model.
            groupModelBuilder.droppedMembers = Array(droppedMembers)
        }
        let newGroupModelV2 = try groupModelBuilder.buildAsV2()

        guard newGroupModelV2.groupsVersion == .V2 else {
            throw OWSAssertionError("Invalid v2 group model.")
        }
        let inProfileWhitelist = profileManager.isThread(inProfileWhitelist: groupThreadV1,
                                                         transaction: transaction)
        let isBlocked = blockingManager.isGroupIdBlocked(groupIdV1, transaction: transaction)

        // We re-use the same model.
        let groupThreadV2 = groupThreadV1

        // Ensure that both the old and new groupIds map to the same unique id.
        TSGroupThread.setGroupIdMapping(groupThreadV1.uniqueId,
                                        forGroupId: oldGroupModelV1.groupId,
                                        transaction: transaction)
        TSGroupThread.setGroupIdMapping(groupThreadV1.uniqueId,
                                        forGroupId: newGroupModelV2.groupId,
                                        transaction: transaction)

        groupThreadV2.update(with: newGroupModelV2, transaction: transaction)

        // Update the disappearing messages configuration.
        let oldDMConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: groupThreadV2,
                                                                                          transaction: transaction)
        let newDMConfiguration = oldDMConfiguration.applyToken(disappearingMessageToken,
                                                               transaction: transaction)

        if inProfileWhitelist {
            profileManager.addThread(toProfileWhitelist: groupThreadV2)
        }
        if isBlocked {
            blockingManager.addBlockedGroup(groupModel: newGroupModelV2,
                                            blockMode: .remote,
                                            transaction: transaction)
        }

        // Always insert a "group update" info message.
        insertGroupUpdateInfoMessage(groupThread: groupThreadV2,
                                     oldGroupModel: oldGroupModelV1,
                                     newGroupModel: newGroupModelV2,
                                     oldDisappearingMessageToken: oldDMConfiguration.asToken,
                                     newDisappearingMessageToken: newDMConfiguration.asToken,
                                     groupUpdateSourceAddress: groupUpdateSourceAddress,
                                     transaction: transaction)

        storageServiceManager.recordPendingDeletions(deletedGroupV1Ids: [groupIdV1])
        notifyStorageServiceOfInsertedGroup(groupModel: newGroupModelV2,
                                            transaction: transaction)

        if DebugFlags.internalLogging {
            let dmConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: groupThreadV2,
                                                                                           transaction: transaction)
            owsAssertDebug(dmConfiguration.asToken == disappearingMessageToken)
        }

        return groupThreadV2
    }

    // If newDisappearingMessageToken is nil, don't update the disappearing messages configuration.
    public static func tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel newGroupModelParam: TSGroupModel,
                                                                                    newDisappearingMessageToken: DisappearingMessageToken?,
                                                                                    groupUpdateSourceAddress: SignalServiceAddress?,
                                                                                    canInsert: Bool,
                                                                                    didAddLocalUserToV2Group: Bool,
                                                                                    infoMessagePolicy: InfoMessagePolicy = .always,
                                                                                    transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {

        var newGroupModel = newGroupModelParam

        // We might be trying to upsert a v1 group model for
        // an existing v2 group. Therefore we need to ensure
        // that the group-id-to-thread-unique-id mapping is
        // up-to-date before proceeding.
        TSGroupThread.ensureGroupIdMapping(forGroupId: newGroupModel.groupId,
                                           transaction: transaction)

        let threadId = TSGroupThread.threadId(forGroupId: newGroupModel.groupId,
                                              transaction: transaction)

        guard TSGroupThread.anyExists(uniqueId: threadId, transaction: transaction) else {
            guard canInsert else {
                throw OWSAssertionError("Missing groupThread.")
            }

            newGroupModel = updateAddedByAddressIfNecessary(oldGroupModel: nil,
                                                            newGroupModel: newGroupModel,
                                                            groupUpdateSourceAddress: groupUpdateSourceAddress)

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
                                                                           groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                           infoMessagePolicy: infoMessagePolicy,
                                                                           transaction: transaction)
    }

    // If newDisappearingMessageToken is nil, don't update the disappearing messages configuration.
    public static func updateExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel newGroupModelParam: TSGroupModel,
                                                                               newDisappearingMessageToken: DisappearingMessageToken?,
                                                                               groupUpdateSourceAddress: SignalServiceAddress?,
                                                                               infoMessagePolicy: InfoMessagePolicy = .always,
                                                                               transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {

        var newGroupModel = newGroupModelParam

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

        if newGroupModel.groupsVersion == .V1,
           groupThread.groupModel.groupsVersion == .V2 {
            Logger.warn("Cannot downgrade migrated group from v2 to v1.")
            throw GroupsV2Error.groupDowngradeNotAllowed
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
            let oldConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: groupThread, transaction: transaction)
            let oldToken = oldConfiguration.asToken
            updateDMResult = UpdateDMConfigurationResult(action: .unchanged,
                                                         oldDisappearingMessageToken: oldToken,
                                                         newDisappearingMessageToken: oldToken,
                                                         newConfiguration: oldConfiguration)
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

            newGroupModel = updateAddedByAddressIfNecessary(oldGroupModel: oldGroupModel,
                                                            newGroupModel: newGroupModel,
                                                            groupUpdateSourceAddress: groupUpdateSourceAddress)

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

        if updateDMResult.action == .unchanged &&
            (updateThreadResult.action == .unchanged ||
                updateThreadResult.action == .updatedWithoutUserFacingChanges) {
            // Neither DM config nor thread model had user-facing changes.
            return updateThreadResult
        }

        switch infoMessagePolicy {
        case .always, .updatesOnly:
            let infoMessage = insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                           oldGroupModel: oldGroupModel,
                                                           newGroupModel: newGroupModel,
                                                           oldDisappearingMessageToken: updateDMResult.oldDisappearingMessageToken,
                                                           newDisappearingMessageToken: updateDMResult.newDisappearingMessageToken,
                                                           groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                           transaction: transaction)
            if let infoMessage = infoMessage,
               DebugFlags.internalLogging {
                owsAssertDebug(!infoMessage.isEmptyGroupUpdate(transaction: transaction))
            }
        default:
            break
        }

        if DebugFlags.internalLogging {
            let dmConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: groupThread,
                                                                                           transaction: transaction)
            owsAssertDebug(dmConfiguration.asToken == updateDMResult.newDisappearingMessageToken)
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

    private static func updateAddedByAddressIfNecessary(oldGroupModel: TSGroupModel?,
                                                        newGroupModel: TSGroupModel,
                                                        groupUpdateSourceAddress: SignalServiceAddress?) -> TSGroupModel {
        guard newGroupModel.groupsVersion == .V1 else {
            return newGroupModel
        }
        guard let groupUpdateSourceAddress = groupUpdateSourceAddress else {
            return newGroupModel
        }
        guard wasLocalUserJustAddedToTheGroup(oldGroupModel: oldGroupModel,
                                              newGroupModel: newGroupModel) else {
            return newGroupModel
        }
        return setAddedByAddress(groupModel: newGroupModel, addedByAddress: groupUpdateSourceAddress)
    }

    private static func setAddedByAddress(groupModel: TSGroupModel,
                                          addedByAddress: SignalServiceAddress?) -> TSGroupModel {
        do {
            var groupModelBuilder = groupModel.asBuilder
            groupModelBuilder.addedByAddress = addedByAddress
            return try groupModelBuilder.buildForMinorChanges()
        } catch {
            owsFailDebug("Could not update addedByAddress.")
            return groupModel
        }
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

// MARK: - Updating V1 Group Errors

private extension Promise {
    static var cannotUpdateV1GroupPromise: Promise {
        Promise(error: OWSAssertionError("V1 groups cannot be updated!"))
    }
}

// MARK: - Add/Invite to group

extension GroupManager {
    public static func addOrInvite(
        aciOrPniUuids: [UUID],
        toExistingGroup existingGroupModel: TSGroupModel
    ) -> Promise<TSGroupThread> {
        guard let existingGroupModel = existingGroupModel as? TSGroupModelV2 else {
            return .cannotUpdateV1GroupPromise
        }

        guard let localUuid = tsAccountManager.localUuid else {
            return Promise(error: OWSAssertionError("Missing local UUID"))
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

                        if isPending || (uuid != localUuid && DebugFlags.groupsV2forceInvites.get()) {
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
            return .cannotUpdateV1GroupPromise
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
