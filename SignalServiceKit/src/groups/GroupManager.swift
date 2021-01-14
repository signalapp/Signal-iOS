//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

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

    // MARK: - Dependencies

    private class var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private class var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    private class var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    private class var groupsV2: GroupsV2Swift {
        return SSKEnvironment.shared.groupsV2 as! GroupsV2Swift
    }

    private class var contactsManager: ContactsManagerProtocol {
        return SSKEnvironment.shared.contactsManager
    }

    private class var profileManager: ProfileManagerProtocol {
        return SSKEnvironment.shared.profileManager
    }

    private class var storageServiceManager: StorageServiceManagerProtocol {
        return SSKEnvironment.shared.storageServiceManager
    }

    fileprivate class var messageProcessing: MessageProcessing {
        return SSKEnvironment.shared.messageProcessing
    }

    private class var bulkProfileFetch: BulkProfileFetch {
        return SSKEnvironment.shared.bulkProfileFetch
    }

    private class var bulkUUIDLookup: BulkUUIDLookup {
        return SSKEnvironment.shared.bulkUUIDLookup
    }

    private class var blockingManager: OWSBlockingManager {
        return .shared()
    }

    // MARK: -

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

    @objc
    public static var canManuallyMigrate: Bool {
        RemoteConfig.groupsV2MigrationManualMigrations
    }

    @objc
    public static var canAutoMigrate: Bool {
        RemoteConfig.groupsV2MigrationAutoMigrations
    }

    @objc
    public static var areManualMigrationsAggressive: Bool {
        true
    }

    @objc
    public static var areAutoMigrationsAggressive: Bool {
        false
    }

    @objc
    public static var areMigrationsBlocking: Bool {
        RemoteConfig.groupsV2MigrationBlockingMigrations
    }

    public static let maxGroupNameCharactersCount: Int = 32

    // Epoch 1: Group Links
    public static let changeProtoEpoch: UInt32 = 1

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

    // This should only be used for certain legacy edge cases.
    @objc
    public static func fakeGroupModel(groupId: Data?,
                                      transaction: SDSAnyReadTransaction) -> TSGroupModel? {
        do {
            var builder = TSGroupModelBuilder()
            builder.groupId = groupId
            builder.groupsVersion = .V1
            return try builder.build(transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    public static func canUseV2(for members: Set<SignalServiceAddress>,
                                transaction: SDSAnyReadTransaction) -> Bool {

        for recipientAddress in members {
            guard doesUserSupportGroupsV2(address: recipientAddress, transaction: transaction) else {
                Logger.warn("Creating legacy group; member missing UUID or Groups v2 capability.")
                return false
            }
            // GroupsV2 TODO: We should finalize the exact decision-making process here.
            // Should having a profile key credential figure in? At least for a while?
        }
        return true
    }

    public static func doesUserSupportGroupsV2(address: SignalServiceAddress,
                                               transaction: SDSAnyReadTransaction) -> Bool {

        guard address.isValid else {
            Logger.warn("Invalid address: \(address).")
            return false
        }
        guard address.uuid != nil else {
            Logger.warn("Member without UUID.")
            return false
        }
        guard doesUserHaveGroupsV2Capability(address: address,
                                             transaction: transaction) else {
                                                Logger.warn("Member without Groups v2 capability.")
                                                return false
        }
        // NOTE: We do consider users to support groups v2 even if:
        //
        // * We don't know their profile key.
        // * They've never done a versioned profile update.
        // * We don't have a profile key credential for them.
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
    public static func localCreateNewGroup(members: [SignalServiceAddress],
                                           groupId: Data? = nil,
                                           name: String? = nil,
                                           avatarImage: UIImage?,
                                           newGroupSeed: NewGroupSeed? = nil,
                                           shouldSendMessage: Bool) -> Promise<TSGroupThread> {

        return DispatchQueue.global().async(.promise) {
            return TSGroupModel.data(forGroupAvatar: avatarImage)
        }.then(on: .global()) { avatarData in
            return localCreateNewGroup(members: members,
                                       groupId: groupId,
                                       name: name,
                                       avatarData: avatarData,
                                       newGroupSeed: newGroupSeed,
                                       shouldSendMessage: shouldSendMessage)
        }
    }

    // NOTE: groupId param should only be set for tests.
    public static func localCreateNewGroup(members membersParam: [SignalServiceAddress],
                                           groupId: Data? = nil,
                                           name: String? = nil,
                                           avatarData: Data? = nil,
                                           newGroupSeed: NewGroupSeed? = nil,
                                           shouldSendMessage: Bool) -> Promise<TSGroupThread> {

        guard let localAddress = tsAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Missing localAddress."))
        }

        // By default, DMs are disable for new groups.
        let disappearingMessageToken = DisappearingMessageToken.disabledToken

        return firstly { () -> Promise<Void> in
            return self.ensureLocalProfileHasCommitmentIfNecessary()
        }.then(on: .global()) { () -> Promise<Void> in
            var memberSet = Set(membersParam)
            memberSet.insert(localAddress)
            return self.tryToEnableGroupsV2(for: Array(memberSet), isBlocking: true, ignoreErrors: true)
        }.map(on: .global()) { () throws -> GroupMembership in
            // Build member list.
            //
            // The group creator is an administrator;
            // the other members are normal users.
            var builder = GroupMembership.Builder()
            builder.addFullMembers(Set(membersParam), role: .normal)
            builder.remove(localAddress)
            builder.addFullMember(localAddress, role: .administrator)
            return builder.build()
        }.then(on: .global()) { (groupMembership: GroupMembership) -> Promise<GroupMembership> in
            // If we might create a v2 group,
            // try to obtain profile key credentials for all group members
            // including ourself, unless we already have them on hand.
            firstly { () -> Promise<Void> in
                self.groupsV2.tryToEnsureProfileKeyCredentials(for: Array(groupMembership.allMembersOfAnyKind))
            }.map(on: .global()) { (_) -> GroupMembership in
                return groupMembership
            }
        }.map(on: .global()) { (proposedGroupMembership: GroupMembership) throws -> TSGroupModel in
            let groupAccess = GroupAccess.defaultForV2
            let groupModel = try self.databaseStorage.read { (transaction) throws -> TSGroupModel in
                // Before we create a v2 group, we need to separate out the
                // pending and non-pending members.  If we already know we're
                // going to create a v1 group, we shouldn't separate them.
                let groupMembership = self.separateInvitedMembers(in: proposedGroupMembership,
                                                                  oldGroupModel: nil,
                                                                  transaction: transaction)

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
                return try builder.build(transaction: transaction)
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
                self.groupsV2.uploadGroupAvatar(avatarData: avatarData,
                                                groupSecretParamsData: proposedGroupModelV2.secretParamsData)
            }.map(on: DispatchQueue.global()) { (avatarUrlPath: String) -> TSGroupModel in
                // Fill in the avatarUrl on the group model.
                return try self.databaseStorage.read { transaction in
                    var builder = proposedGroupModel.asBuilder
                    builder.avatarUrlPath = avatarUrlPath
                    return try builder.build(transaction: transaction)
                }
            }
        }.then(on: .global()) { (proposedGroupModel: TSGroupModel) -> Promise<TSGroupModel> in
            guard let proposedGroupModelV2 = proposedGroupModel as? TSGroupModelV2 else {
                // v1 groups don't need to be created on the service.
                return Promise.value(proposedGroupModel)
            }
            return firstly {
                self.groupsV2.createNewGroupOnService(groupModel: proposedGroupModelV2,
                                                      disappearingMessageToken: disappearingMessageToken)
            }.then(on: .global()) { _ in
                self.groupsV2.fetchCurrentGroupV2Snapshot(groupModel: proposedGroupModelV2)
            }.map(on: .global()) { (groupV2Snapshot: GroupV2Snapshot) throws -> TSGroupModel in
                let createdGroupModel = try self.databaseStorage.write { (transaction) throws -> TSGroupModel in
                    var builder = try TSGroupModelBuilder.builderForSnapshot(groupV2Snapshot: groupV2Snapshot,
                                                                             transaction: transaction)
                    builder.wasJustCreatedByLocalUser = true
                    return try builder.build(transaction: transaction)
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
        }.then(on: .global()) { (groupModelParam: TSGroupModel) -> Promise<TSGroupThread> in
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
                }.map(on: .global()) { _ in
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
    // * Their account has the "groups v2" capability
    //   (e.g. all of their clients support groups v2.
    private static func separateInvitedMembers(in newGroupMembership: GroupMembership,
                                               oldGroupModel: TSGroupModel?,
                                               transaction: SDSAnyReadTransaction) -> GroupMembership {
        guard let localUuid = tsAccountManager.localUuid else {
            owsFailDebug("Missing localUuid.")
            return newGroupMembership
        }
        let localAddress = SignalServiceAddress(uuid: localUuid)
        var newMembers: Set<SignalServiceAddress>
        var builder = GroupMembership.Builder()
        if let oldGroupModel = oldGroupModel {
            // Updating existing group
            let oldGroupMembership = oldGroupModel.groupMembership

            builder.copyInvalidInvites(from: oldGroupMembership)

            assert(oldGroupModel.groupsVersion == .V2)
            newMembers = newGroupMembership.allMembersOfAnyKind.subtracting(oldGroupMembership.allMembersOfAnyKind)

            // Carry over existing members as they stand.
            let existingMembers = oldGroupMembership.allMembersOfAnyKind.intersection(newGroupMembership.allMembersOfAnyKind)
            for address in existingMembers {
                if oldGroupMembership.isInvitedMember(address),
                    newGroupMembership.isFullMember(address) {
                    // If we're adding a pending member, treat them as a new member.
                    newMembers.insert(address)
                } else if oldGroupMembership.isRequestingMember(address),
                    newGroupMembership.isFullMember(address) {
                    // If we're adding a requesting member, treat them as a new member.
                    newMembers.insert(address)
                } else {
                    builder.copyMember(address, from: oldGroupMembership)
                }
            }
        } else {
            // Creating new group

            // First, skip separation when creating v1 groups.
            guard canUseV2(for: newGroupMembership.allMembersOfAnyKind, transaction: transaction) else {
                // If any member of a new group doesn't support groups v2,
                // we're going to create a v1 group.  In that case, we
                // don't want to separate out pending members.
                return newGroupMembership
            }

            newMembers = newGroupMembership.allMembersOfAnyKind
        }

        // We only need to separate new members.
        for address in newMembers {
            guard doesUserSupportGroupsV2(address: address, transaction: transaction) else {
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
            let isPending = !groupsV2.hasProfileKeyCredential(for: address,
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
                                               avatarImage: UIImage?,
                                               newGroupSeed: NewGroupSeed?,
                                               shouldSendMessage: Bool,
                                               success: @escaping (TSGroupThread) -> Void,
                                               failure: @escaping (Error) -> Void) {
        firstly {
            self.localCreateNewGroup(members: members,
                                     groupId: groupId,
                                     name: name,
                                     avatarImage: avatarImage,
                                     newGroupSeed: newGroupSeed,
                                     shouldSendMessage: shouldSendMessage)
        }.done { thread in
            success(thread)
        }.catch { error in
            failure(error)
        }
    }

    // success and failure are invoked on the main thread.
    @objc
    public static func localCreateNewGroupObjc(members: [SignalServiceAddress],
                                               groupId: Data?,
                                               name: String,
                                               avatarData: Data?,
                                               newGroupSeed: NewGroupSeed?,
                                               shouldSendMessage: Bool,
                                               success: @escaping (TSGroupThread) -> Void,
                                               failure: @escaping (Error) -> Void) {
        firstly {
            localCreateNewGroup(members: members,
                                groupId: groupId,
                                name: name,
                                avatarData: avatarData,
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

    #if TESTABLE_BUILD
    @objc
    public static let shouldForceV1Groups = AtomicBool(false)

    @objc
    public class func forceV1Groups() {
        shouldForceV1Groups.set(true)
    }
    #endif

    @objc
    public static func createGroupForTestsObjc(members: [SignalServiceAddress],
                                               name: String? = nil,
                                               avatarData: Data? = nil,
                                               transaction: SDSAnyWriteTransaction) -> TSGroupThread {
        do {
            #if TESTABLE_BUILD
            let groupsVersion = (shouldForceV1Groups.get()
                ? .V1
                : self.defaultGroupsVersion)
            #else
            let groupsVersion = self.defaultGroupsVersion
            #endif
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
        builder.avatarData = avatarData
        builder.avatarUrlPath = nil
        builder.groupMembership = groupMembership
        builder.groupAccess = groupAccess
        builder.groupsVersion = groupsVersion
        let groupModel = try builder.build(transaction: transaction)

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
        let groupModel = try builder.build(transaction: transaction)

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
        let updateInfo: UpdateInfo
        do {
            updateInfo = try updateInfoV1(groupModel: proposedGroupModel,
                                          dmConfiguration: nil,
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
        let newGroupModel = try builder.build(transaction: transaction)
        return try remoteUpdateToExistingGroupV1(groupModel: newGroupModel,
                                                 disappearingMessageToken: nil,
                                                 groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                 transaction: transaction)

    }

    // MARK: - Update Existing Group

    private struct UpdateInfo {
        let groupId: Data
        let newGroupModel: TSGroupModel
        let oldDMConfiguration: OWSDisappearingMessagesConfiguration
        let newDMConfiguration: OWSDisappearingMessagesConfiguration
    }

    // If dmConfiguration is nil, don't change the disappearing messages configuration.
    public static func localUpdateExistingGroup(oldGroupModel: TSGroupModel?,
                                                newGroupModel: TSGroupModel,
                                                dmConfiguration: OWSDisappearingMessagesConfiguration?,
                                                groupUpdateSourceAddress: SignalServiceAddress?) -> Promise<TSGroupThread> {

        if let newGroupModel = newGroupModel as? TSGroupModelV2 {
            return localUpdateExistingGroupV2(oldGroupModel: oldGroupModel,
                                              newGroupModel: newGroupModel,
                                              dmConfiguration: dmConfiguration,
                                              groupUpdateSourceAddress: groupUpdateSourceAddress)
        } else {
            return localUpdateExistingGroupV1(groupModel: newGroupModel,
                                              dmConfiguration: dmConfiguration,
                                              groupUpdateSourceAddress: groupUpdateSourceAddress)
        }
    }

    // If dmConfiguration is nil, don't change the disappearing messages configuration.
    private static func localUpdateExistingGroupV1(groupModel proposedGroupModel: TSGroupModel,
                                                   dmConfiguration: OWSDisappearingMessagesConfiguration?,
                                                   groupUpdateSourceAddress: SignalServiceAddress?) -> Promise<TSGroupThread> {

        return self.databaseStorage.write(.promise) { (transaction) throws -> UpsertGroupResult in
            let updateInfo = try self.updateInfoV1(groupModel: proposedGroupModel,
                                                   dmConfiguration: dmConfiguration,
                                                   transaction: transaction)
            let newGroupModel = updateInfo.newGroupModel
            let upsertGroupResult = try self.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                                          newDisappearingMessageToken: dmConfiguration?.asToken,
                                                                                                          groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                                          canInsert: false,
                                                                                                          didAddLocalUserToV2Group: false,
                                                                                                          transaction: transaction)

            if let dmConfiguration = dmConfiguration {
                let groupThread = upsertGroupResult.groupThread
                let updateResult = self.updateDisappearingMessagesInDatabaseAndCreateMessages(token: dmConfiguration.asToken,
                                                                                              thread: groupThread,
                                                                                              shouldInsertInfoMessage: true,
                                                                                              groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                              transaction: transaction)
                self.sendDisappearingMessagesConfigurationMessage(updateResult: updateResult,
                                                                  thread: groupThread,
                                                                  transaction: transaction)
            }

            return upsertGroupResult
        }.then(on: .global()) { (upsertGroupResult: UpsertGroupResult) throws -> Promise<TSGroupThread> in
            let groupThread = upsertGroupResult.groupThread
            guard upsertGroupResult.action != .unchanged else {
                // Don't bother sending a message if the update was redundant.
                return Promise.value(groupThread)
            }
            return self.sendGroupUpdateMessage(thread: groupThread)
                .map(on: .global()) { _ in
                    return groupThread
            }
        }
    }

    // If dmConfiguration is nil, don't change the disappearing messages configuration.
    private static func localUpdateExistingGroupV2(oldGroupModel: TSGroupModel?,
                                                   newGroupModel proposedGroupModel: TSGroupModelV2,
                                                   dmConfiguration: OWSDisappearingMessagesConfiguration?,
                                                   groupUpdateSourceAddress: SignalServiceAddress?) -> Promise<TSGroupThread> {

        guard let oldGroupModel = oldGroupModel as? TSGroupModelV2 else {
            return Promise(error: OWSAssertionError("Invalid group model."))
        }

        return firstly { () -> Promise<Void> in
            self.tryToEnableGroupsV2(for: Array(proposedGroupModel.groupMembership.allMembersOfAnyKind), isBlocking: true, ignoreErrors: true)
        }.then(on: .global()) { () -> Promise<Void> in
            return self.ensureLocalProfileHasCommitmentIfNecessary()
        }.then(on: DispatchQueue.global()) { () -> Promise<String?> in
            guard let avatarData = proposedGroupModel.groupAvatarData else {
                // No avatar to upload.
                return Promise.value(nil)
            }
            if oldGroupModel.groupAvatarData == avatarData && oldGroupModel.avatarUrlPath != nil {
                // Skip redundant upload; the avatar hasn't changed.
                return Promise.value(oldGroupModel.avatarUrlPath)
            }
            return firstly {
                // Upload avatar.
                return self.groupsV2.uploadGroupAvatar(avatarData: avatarData,
                                                       groupSecretParamsData: oldGroupModel.secretParamsData)
            }.map(on: .global()) { (avatarUrlPath: String) throws -> String? in
                // Convert Promise<String> to Promise<String?>
                return avatarUrlPath
            }
        }.map(on: .global()) { (avatarUrlPath: String?) throws -> (UpdateInfo, GroupsV2ChangeSet) in
            return try databaseStorage.read { transaction in
                var proposedGroupModel = proposedGroupModel
                if let avatarUrlPath = avatarUrlPath {
                    var builder = proposedGroupModel.asBuilder
                    builder.avatarUrlPath = avatarUrlPath
                    proposedGroupModel = try builder.buildAsV2(transaction: transaction)
                }
                let updateInfo = try self.updateInfoV2(oldGroupModel: oldGroupModel,
                                                       newGroupModel: proposedGroupModel,
                                                       newDMConfiguration: dmConfiguration,
                                                       transaction: transaction)
                guard let newGroupModel = updateInfo.newGroupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid group model.")
                }

                // When building the change set, it's important that we
                // diff the "new/proposed" group model against the "old"
                // group model, not the "current" group model. This avoids
                // reverting changes from other users.
                //
                // The "old" group model reflects the group model the user
                // used as a point of departure for their updates. The
                // "current" group model reflects the state of the database
                // which may have changed since the user started editing.
                // The "new" group model is the "old" model, updated to
                // reflect the user intent.
                //
                // Let's say Alice and Bob edit the group at the same time.
                // Alice changes the group name and Bob changes the group
                // avatar.  Alice updates the group first.  When Bob's
                // client tries to update, it should only reflect Bob's
                // intent - to change the group avatar.
                let changeSet = try self.groupsV2.buildChangeSet(oldGroupModel: oldGroupModel,
                                                                 newGroupModel: newGroupModel,
                                                                 oldDMConfiguration: updateInfo.oldDMConfiguration,
                                                                 newDMConfiguration: updateInfo.newDMConfiguration,
                                                                 transaction: transaction)
                return (updateInfo, changeSet)
            }
        }.then(on: .global()) { (_: UpdateInfo, changeSet: GroupsV2ChangeSet) throws -> Promise<TSGroupThread> in
            return self.groupsV2.updateExistingGroupOnService(changeSet: changeSet)
        }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                  description: "Update existing group") {
            GroupsV2Error.timeout
        }
    }

    // If dmConfiguration is nil, don't change the disappearing messages configuration.
    private static func updateInfoV1(groupModel proposedGroupModel: TSGroupModel,
                                     dmConfiguration: OWSDisappearingMessagesConfiguration?,
                                     transaction: SDSAnyReadTransaction) throws -> UpdateInfo {
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

        let oldDMConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: thread, transaction: transaction)
        let newDMConfiguration = dmConfiguration ?? oldDMConfiguration

        // Always ensure we're a member of any v1 group we're updating.
        var builder = proposedGroupModel.groupMembership.asBuilder
        builder.remove(localAddress)
        builder.addFullMember(localAddress, role: .normal)
        let groupMembership = builder.build()

        var groupModelBuilder = proposedGroupModel.asBuilder
        groupModelBuilder.groupMembership = groupMembership
        let newGroupModel = try groupModelBuilder.build(transaction: transaction)

        if currentGroupModel.isEqual(to: newGroupModel, comparisonMode: .compareAll) {
            // Skip redundant update.
            throw GroupsV2Error.redundantChange
        }

        return UpdateInfo(groupId: groupId,
                          newGroupModel: newGroupModel,
                          oldDMConfiguration: oldDMConfiguration,
                          newDMConfiguration: newDMConfiguration)
    }

    // If dmConfiguration is nil, don't change the disappearing messages configuration.
    private static func updateInfoV2(oldGroupModel: TSGroupModelV2,
                                     newGroupModel proposedGroupModel: TSGroupModelV2,
                                     newDMConfiguration dmConfiguration: OWSDisappearingMessagesConfiguration?,
                                     transaction: SDSAnyReadTransaction) throws -> UpdateInfo {

        let groupId = proposedGroupModel.groupId
        let proposedGroupMembership = proposedGroupModel.groupMembership
        guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            throw OWSAssertionError("Thread does not exist.")
        }
        guard let currentGroupModel = thread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Invalid groupModel.")
        }
        guard let localAddress = tsAccountManager.localAddress else {
            throw OWSAssertionError("Missing localAddress.")
        }

        let oldDMConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: thread, transaction: transaction)
        let newDMConfiguration = dmConfiguration ?? oldDMConfiguration

        for address in proposedGroupMembership.allMembersOfAnyKind {
            guard address.uuid != nil else {
                throw OWSAssertionError("Group v2 member missing uuid.")
            }
        }
        // Before we update a v2 group, we need to separate out the
        // pending and non-pending members.
        let groupMembership = self.separateInvitedMembers(in: proposedGroupMembership,
                                                          oldGroupModel: oldGroupModel,
                                                          transaction: transaction)

        // Don't try to modify a v2 group if we're not a member.
        guard groupMembership.isFullMember(localAddress) else {
            throw OWSAssertionError("Missing localAddress.")
        }

        let hasAvatarUrlPath = proposedGroupModel.avatarUrlPath != nil
        let hasAvatarData = proposedGroupModel.groupAvatarData != nil
        guard hasAvatarUrlPath == hasAvatarData else {
            throw OWSAssertionError("hasAvatarUrlPath: \(hasAvatarData) != hasAvatarData.")
        }

        // We don't need to increment the revision here,
        // this is a "proposed" new group model; we'll
        // eventually derive a new group model from
        // protos received from the service and apply
        // that the to the local database.
        let newRevision = currentGroupModel.revision

        var builder = proposedGroupModel.asBuilder
        builder.groupMembership = groupMembership
        builder.groupV2Revision = newRevision
        let newGroupModel = try builder.build(transaction: transaction)

        if currentGroupModel.isEqual(to: newGroupModel, comparisonMode: .compareAll) {
            // Skip redundant update.
            throw GroupsV2Error.redundantChange
        }

        return UpdateInfo(groupId: groupId,
                          newGroupModel: newGroupModel,
                          oldDMConfiguration: oldDMConfiguration,
                          newDMConfiguration: newDMConfiguration)
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
        let message = OWSDisappearingMessagesConfigurationMessage(configuration: newConfiguration, thread: thread)
        messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
    }

    // MARK: - Accept Invites

    public static func localAcceptInviteToGroupV2(groupModel: TSGroupModelV2) -> Promise<TSGroupThread> {
        return firstly { () -> Promise<Void> in
            return self.databaseStorage.write(.promise) { transaction in
                self.profileManager.addGroupId(toProfileWhitelist: groupModel.groupId,
                                               wasLocallyInitiated: true,
                                               transaction: transaction)
            }
        }.then(on: .global()) { _ -> Promise<TSGroupThread> in
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

    public static func localLeaveGroupOrDeclineInvite(groupThread: TSGroupThread,
                                                      replacementAdminUuid: UUID? = nil) -> Promise<TSGroupThread> {
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            assert(replacementAdminUuid == nil)
            return localLeaveGroupV1(groupId: groupThread.groupModel.groupId)
        }
        return localLeaveGroupV2OrDeclineInvite(groupModel: groupModel,
                                                replacementAdminUuid: replacementAdminUuid)
    }

    private static func localLeaveGroupV1(groupId: Data) -> Promise<TSGroupThread> {
        guard let localAddress = self.tsAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Missing localAddress."))
        }
        return databaseStorage.write(.promise) { transaction in
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("Missing group.")
            }
            let oldGroupModel = groupThread.groupModel
            // Note that we consult allUsers which includes pending members.
            guard oldGroupModel.groupMembership.isMemberOfAnyKind(localAddress) else {
                throw OWSAssertionError("Local user is not a member of the group.")
            }

            sendGroupQuitMessage(inThread: groupThread, transaction: transaction)

            let hasMessages = groupThread.numberOfInteractions(with: transaction) > 0
            let infoMessagePolicy: InfoMessagePolicy = hasMessages ? .always : .never

            var groupMembershipBuilder = oldGroupModel.groupMembership.asBuilder
            groupMembershipBuilder.remove(localAddress)
            let newGroupMembership = groupMembershipBuilder.build()

            var builder = oldGroupModel.asBuilder
            builder.groupMembership = newGroupMembership
            var newGroupModel = try builder.build(transaction: transaction)

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
    }

    private static func localLeaveGroupV2OrDeclineInvite(groupModel: TSGroupModelV2,
                                                         replacementAdminUuid: UUID? = nil) -> Promise<TSGroupThread> {
        return updateGroupV2(groupModel: groupModel,
                             description: "Leave group or decline invite") { groupChangeSet in
                                groupChangeSet.setShouldLeaveGroupDeclineInvite()

                                // Sometimes when we leave a group we take care to assign a new admin.
                                if let replacementAdminUuid = replacementAdminUuid {
                                    groupChangeSet.changeRoleForMember(replacementAdminUuid, role: .administrator)
                                }
        }
    }

    @objc
    public static func leaveGroupOrDeclineInviteAsyncWithoutUI(groupThread: TSGroupThread,
                                                               transaction: SDSAnyWriteTransaction,
                                                               success: (() -> Void)?) {

        guard groupThread.isLocalUserMemberOfAnyKind else {
            owsFailDebug("unexpectedly trying to leave group for which we're not a member.")
            return
        }

        transaction.addAsyncCompletion {
            firstly {
                self.localLeaveGroupOrDeclineInvite(groupThread: groupThread).asVoid()
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
        return updateGroupV2(groupModel: groupModel,
                             description: "Remove from group or revoke invite") { groupChangeSet in
                                for uuid in uuids {
                                    groupChangeSet.removeMember(uuid)
                                }
        }
    }

    public static func revokeInvalidInvites(groupModel: TSGroupModelV2) -> Promise<TSGroupThread> {
        return updateGroupV2(groupModel: groupModel,
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
        return updateGroupV2(groupModel: groupModel,
                             description: "Change member role") { groupChangeSet in
                                for uuid in uuids {
                                    groupChangeSet.changeRoleForMember(uuid, role: role)
                                }
        }
    }

    // MARK: - Change Group Access

    public static func changeGroupAttributesAccessV2(groupModel: TSGroupModelV2,
                                                     access: GroupV2Access) -> Promise<TSGroupThread> {
        return updateGroupV2(groupModel: groupModel,
                             description: "Change group attributes access") { groupChangeSet in
                                groupChangeSet.setAccessForAttributes(access)
        }
    }

    public static func changeGroupMembershipAccessV2(groupModel: TSGroupModelV2,
                                                     access: GroupV2Access) -> Promise<TSGroupThread> {
        return updateGroupV2(groupModel: groupModel,
                             description: "Change group membership access") { groupChangeSet in
                                groupChangeSet.setAccessForMembers(access)
        }
    }

    // MARK: - Group Links

    public static func updateLinkModeV2(groupModel: TSGroupModelV2,
                                        linkMode: GroupsV2LinkMode) -> Promise<TSGroupThread> {
        return updateGroupV2(groupModel: groupModel,
                             description: "Change group link mode") { groupChangeSet in
                                groupChangeSet.setLinkMode(linkMode)
        }
    }

    public static func resetLinkV2(groupModel: TSGroupModelV2) -> Promise<TSGroupThread> {
        return updateGroupV2(groupModel: groupModel,
                             description: "Rotate invite link password") { groupChangeSet in
                                groupChangeSet.rotateInviteLinkPassword()
        }
    }

    public static let inviteLinkPasswordLengthV2: UInt = 16

    public static func generateInviteLinkPasswordV2() -> Data {
        Cryptography.generateRandomBytes(inviteLinkPasswordLengthV2)
    }

    public static func groupInviteLink(forGroupModelV2 groupModelV2: TSGroupModelV2) throws -> URL {
        try groupsV2.groupInviteLink(forGroupModelV2: groupModelV2)
    }

    @objc
    public static func isPossibleGroupInviteLink(_ url: URL) -> Bool {
        guard RemoteConfig.groupsV2InviteLinks else {
            return false
        }
        return groupsV2.isPossibleGroupInviteLink(url)
    }

    @objc
    public static func parseGroupInviteLink(_ url: URL) -> GroupInviteLinkInfo? {
        guard RemoteConfig.groupsV2InviteLinks else {
            return nil
        }
        return groupsV2.parseGroupInviteLink(url)
    }

    @objc
    public static func isGroupInviteLink(_ url: URL) -> Bool {
        nil != groupsV2.parseGroupInviteLink(url)
    }

    public static func joinGroupViaInviteLink(groupId: Data,
                                              groupSecretParamsData: Data,
                                              inviteLinkPassword: Data,
                                              groupInviteLinkPreview: GroupInviteLinkPreview,
                                              avatarData: Data?) -> Promise<TSGroupThread> {
        let description = "Join Group Invite Link"

        return firstly(on: .global()) {
            self.ensureLocalProfileHasCommitmentIfNecessary()
        }.then(on: .global()) { () throws -> Promise<TSGroupThread> in
            self.groupsV2.joinGroupViaInviteLink(groupId: groupId,
                                                 groupSecretParamsData: groupSecretParamsData,
                                                 inviteLinkPassword: inviteLinkPassword,
                                                 groupInviteLinkPreview: groupInviteLinkPreview,
                                                 avatarData: avatarData)
        }.map(on: .global()) { (groupThread: TSGroupThread) -> TSGroupThread in
            self.databaseStorage.write { transaction in
                self.profileManager.addGroupId(toProfileWhitelist: groupId,
                                               wasLocallyInitiated: true,
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
                                    }
                                }
        }
    }

    public static func cancelMemberRequestsV2(groupModel: TSGroupModelV2) -> Promise<TSGroupThread> {

        let description = "Cancel Member Request"

        return firstly(on: .global()) {
            self.groupsV2.cancelMemberRequests(groupModel: groupModel)
        }.timeout(seconds: Self.groupUpdateTimeoutDuration, description: description) {
            GroupsV2Error.timeout
        }
    }

    private static func tryToUpdatePlaceholderGroupModelUsingInviteLinkPreview(groupModel: TSGroupModelV2) {
        groupsV2.tryToUpdatePlaceholderGroupModelUsingInviteLinkPreview(groupModel: groupModel)
    }

    @objc
    public static func cachedGroupInviteLinkPreview(groupInviteLinkInfo: GroupInviteLinkInfo) -> GroupInviteLinkPreview? {
        do {
            let groupContextInfo = try self.groupsV2.groupV2ContextInfo(forMasterKeyData: groupInviteLinkInfo.masterKey)
            return groupsV2.cachedGroupInviteLinkPreview(groupSecretParamsData: groupContextInfo.groupSecretParamsData)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    // MARK: - Generic Group Change

    public static func updateGroupV2(groupModel: TSGroupModelV2,
                                     description: String,
                                     changeSetBlock: @escaping (GroupsV2ChangeSet) -> Void) -> Promise<TSGroupThread> {
        return firstly {
            self.ensureLocalProfileHasCommitmentIfNecessary()
        }.then(on: .global()) { () throws -> Promise<TSGroupThread> in
            self.groupsV2.updateGroupV2(groupModel: groupModel, changeSetBlock: changeSetBlock)
        }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                  description: description) {
                    GroupsV2Error.timeout
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

        if let groupModelV2 = groupThread.groupModel as? TSGroupModelV2,
            groupModelV2.isPlaceholderModel {
            Logger.warn("Ignoring 403 for placeholder group.")
            GroupManager.tryToUpdatePlaceholderGroupModelUsingInviteLinkPreview(groupModel: groupModelV2)
            return
        }

        Logger.info("")

        // Remove local user from group.
        // We do _not_ bump the revision number since this (unlike all other
        // changes to group state) is inferred from a 403. This is fine; if
        // we're ever re-added to the group the groups v2 machinery will
        // recover.
        var groupMembershipBuilder = groupThread.groupModel.groupMembership.asBuilder
        groupMembershipBuilder.remove(localAddress)
        var groupModelBuilder = groupThread.groupModel.asBuilder
        do {
            groupModelBuilder.groupMembership = groupMembershipBuilder.build()
            let newGroupModel = try groupModelBuilder.build(transaction: transaction)

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

    // MARK: - UUIDs

    public static func tryToEnableGroupsV2(for addresses: [SignalServiceAddress],
                                           isBlocking: Bool,
                                           ignoreErrors: Bool) -> Promise<Void> {
        let promise = tryToEnableGroupsV2(for: addresses, isBlocking: isBlocking)
        if ignoreErrors {
            return promise.recover { error -> Guarantee<Void> in
                Logger.warn("Error: \(error).")
                return Guarantee.value(())
            }
        } else {
            return promise
        }
    }

    private static func tryToEnableGroupsV2(for addresses: [SignalServiceAddress],
                                            isBlocking: Bool) -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            for address in addresses {
                guard address.isValid else {
                    throw OWSAssertionError("Invalid address: \(address).")
                }
            }
            return Promise.value(())
        }.then(on: .global()) { _ -> Promise<Void> in
            return self.tryToFillInMissingUuids(for: addresses, isBlocking: isBlocking)
        }.then(on: .global()) { _ -> Promise<Void> in
            return self.tryToEnableGroupsV2Capability(for: addresses, isBlocking: isBlocking)
        }
    }

    public static func tryToFillInMissingUuids(for addresses: [SignalServiceAddress],
                                               isBlocking: Bool) -> Promise<Void> {

        let phoneNumbersWithoutUuids = addresses.filter { $0.uuid == nil }.compactMap { $0.phoneNumber }
        guard phoneNumbersWithoutUuids.count > 0 else {
            return Promise.value(())
        }

        if isBlocking {
            // Block on the outcome.
            let discoveryTask = ContactDiscoveryTask(phoneNumbers: Set(phoneNumbersWithoutUuids))
            return discoveryTask.perform(at: .userInitiated).asVoid()
        } else {
            // This will throttle, de-bounce, etc.
            self.bulkUUIDLookup.lookupUuids(phoneNumbers: phoneNumbersWithoutUuids)
            return Promise.value(())
        }
    }

    private static func tryToEnableGroupsV2Capability(for addresses: [SignalServiceAddress],
                                                      isBlocking: Bool) -> Promise<Void> {
        return firstly { () -> Promise<[SignalServiceAddress]> in
            let validAddresses = addresses.filter { $0.isValid }
            if validAddresses.count < addresses.count {
                owsFailDebug("Invalid addresses.")
            }
            return Promise.value(validAddresses)
        }.then(on: .global()) { (addresses: [SignalServiceAddress]) -> Promise<Void> in
            // Try to ensure groups v2 capability.
            var addressesWithoutCapability = [SignalServiceAddress]()
            self.databaseStorage.read { transaction in
                for address in addresses {
                    if !GroupManager.doesUserHaveGroupsV2Capability(address: address, transaction: transaction) {
                        addressesWithoutCapability.append(address)
                    }
                }
            }
            guard !addressesWithoutCapability.isEmpty else {
                return Promise.value(())
            }
            if isBlocking {
                // Block on the outcome of the profile updates.
                var promises = [Promise<Void>]()
                for address in addressesWithoutCapability {
                    promises.append(self.profileManager.fetchProfile(forAddressPromise: address).asVoid())
                }
                return when(fulfilled: promises)
            } else {
                // This will throttle, de-bounce, etc.
                self.bulkProfileFetch.fetchProfiles(addresses: addressesWithoutCapability)
                return Promise.value(())
            }
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
        }.done(on: .global()) {
            Logger.verbose("")
        }.catch(on: .global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    public static func sendGroupUpdateMessage(thread: TSGroupThread,
                                              changeActionsProtoData: Data? = nil,
                                              singleRecipient: SignalServiceAddress? = nil) -> Promise<Void> {

        // Only honor groupsV2dontSendUpdates for v2 groups.
        let shouldSkipUpdate = thread.isGroupV2Thread && DebugFlags.groupsV2dontSendUpdates.get()
        if shouldSkipUpdate {
            return Promise.value(())
        }

        return databaseStorage.read(.promise) { transaction in
            let expiresInSeconds = thread.disappearingMessagesDuration(with: transaction)
            let messageBuilder = TSOutgoingMessageBuilder(thread: thread)
            messageBuilder.expiresInSeconds = expiresInSeconds
            // V2 group update messages mostly ignore groupMetaMessage,
            // but we set it to get the right behavior in shouldBeSaved.
            // i.e. we need to flag this message as a group update that
            // is "durable but transient" - it should not be saved.
            messageBuilder.groupMetaMessage = .update

            if thread.isGroupV2Thread {
                if FeatureFlags.groupsV2embedProtosInGroupUpdates {
                    messageBuilder.changeActionsProtoData = changeActionsProtoData
                }
                if singleRecipient == nil {
                    self.addAdditionalRecipients(to: messageBuilder,
                                                 groupThread: thread,
                                                 transaction: transaction)
                }
            }
            return messageBuilder.build()
        }.then(on: .global()) { (message: TSOutgoingMessage) throws -> Promise<Void> in

            if let singleRecipient = singleRecipient {
                Self.databaseStorage.write { transaction in
                    message.updateWithSending(toSingleGroupRecipient: singleRecipient, transaction: transaction)
                }
            }

            let groupModel = thread.groupModel
            // V1 group updates need to include the group avatar (if any)
            // as an attachment.
            if thread.isGroupV1Thread,
               let avatarData = groupModel.groupAvatarData,
               avatarData.count > 0 {
                if let dataSource = DataSourceValue.dataSource(with: avatarData, fileExtension: "png") {
                    let attachment = GroupUpdateMessageAttachment(contentType: OWSMimeTypeImagePng, dataSource: dataSource)
                    return self.sendGroupUpdateMessage(message, thread: thread, attachment: attachment)
                }
            }

            return self.sendGroupUpdateMessage(message, thread: thread)
        }
    }

    private struct GroupUpdateMessageAttachment {
        let contentType: String
        let dataSource: DataSource
    }

    // v1 group update messages should be non-durable and have specific error handling.
    // v2 group update messages should be durable.
    private static func sendGroupUpdateMessage(_ message: TSOutgoingMessage,
                                               thread: TSGroupThread,
                                               attachment: GroupUpdateMessageAttachment? = nil) -> Promise<Void> {
        if thread.isGroupV1Thread {
            return firstly(on: .global()) { () -> Promise<Void> in
                if let attachment = attachment {
                    // v1 group update with avatar.
                    return self.messageSender.sendTemporaryAttachment(.promise,
                                                                      dataSource: attachment.dataSource,
                                                                      contentType: attachment.contentType,
                                                                      message: message)
                } else {
                    // v1 group update without avatar.
                    return self.messageSender.sendMessage(.promise, message.asPreparer)
                }
            }.recover(on: .global()) { error in
                if isNetworkFailureOrTimeout(error) {
                    Logger.error("Error sending v1 group update: \(error)")
                } else {
                    owsFailDebug("Error sending v1 group update: \(error)")
                }
                if message.wasSentToAnyRecipient {
                    // If a v1 group update was successfully sent to any
                    // group member, consider it a success. The group update
                    // is "out in the wild". If some members did not receive
                    // the update, we rely on other mechanisms for group state
                    // to converge.
                } else {
                    throw error
                }
            }
        } else {
            // v2 group update.
            //
            // Enqueue the message for a durable send.
            return databaseStorage.write(.promise) { transaction in
                self.messageSenderJobQueue.add(message: message.asPreparer,
                                               transaction: transaction)
            }
        }
    }

    private static func sendDurableNewGroupMessage(forThread thread: TSGroupThread) -> Promise<Void> {
        // Only honor groupsV2dontSendUpdates for v2 groups.
        let shouldSkipUpdate = thread.isGroupV2Thread && DebugFlags.groupsV2dontSendUpdates.get()
        if shouldSkipUpdate {
            return Promise.value(())
        }

        return firstly {
            databaseStorage.write(.promise) { transaction in
                let expiresInSeconds = thread.disappearingMessagesDuration(with: transaction)
                let messageBuilder = TSOutgoingMessageBuilder(thread: thread)
                messageBuilder.groupMetaMessage = .new
                messageBuilder.expiresInSeconds = expiresInSeconds
                self.addAdditionalRecipients(to: messageBuilder,
                                             groupThread: thread,
                                             transaction: transaction)
                let message = messageBuilder.build()
                self.messageSenderJobQueue.add(message: message.asPreparer,
                                               transaction: transaction)
            }
        }.then(on: .global()) { _ -> Promise<Void> in
            // The "new group" update message for v1 groups doesn't support avatars.
            // So, if a new v1 group has an avatar, we need to send a group update
            // message.
            guard thread.groupModel.groupsVersion == .V1,
                thread.groupModel.groupAvatarData != nil else {
                    return Promise.value(())
            }
            return self.sendGroupUpdateMessage(thread: thread)
        }
    }

    private static func addAdditionalRecipients(to messageBuilder: TSOutgoingMessageBuilder,
                                                groupThread: TSGroupThread,
                                                transaction: SDSAnyReadTransaction) {
        guard groupThread.groupModel.groupsVersion == .V2 else {
            // No need to add "additional recipients" to v1 groups.
            return
        }
        // We need to send v2 group updates to pending members
        // as well.  Normal group sends only include "full members".
        assert(messageBuilder.additionalRecipients == nil)
        let groupMembership = groupThread.groupModel.groupMembership
        let additionalRecipients = groupMembership.invitedMembers.filter { address in
            return doesUserSupportGroupsV2(address: address,
                                           transaction: transaction)
        }
        messageBuilder.additionalRecipients = Array(additionalRecipients)
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

        let message = TSOutgoingMessage(in: groupThread,
                                        groupMetaMessage: .quit,
                                        expiresInSeconds: 0)
        messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
    }

    public static func resendInvite(groupThread: TSGroupThread,
                                    transaction: SDSAnyWriteTransaction) {

        guard groupThread.groupModel.groupsVersion == .V2 else {
            return
        }

        let messageBuilder = TSOutgoingMessageBuilder(thread: groupThread)
        // V2 group update messages mostly ignore groupMetaMessage,
        // but we set it to get the right behavior in shouldBeSaved.
        // i.e. we need to flag this message as a group update that
        // is "durable but transient" - it should not be saved.
        messageBuilder.groupMetaMessage = .update
        // We need to send v2 group updates to pending members
        // as well.  Normal group sends only include "full members".
        assert(messageBuilder.additionalRecipients == nil)
        let groupMembership = groupThread.groupModel.groupMembership
        let additionalRecipients = groupMembership.invitedOrRequestMembers.filter { address in
            return doesUserSupportGroupsV2(address: address,
                                           transaction: transaction)
        }
        messageBuilder.additionalRecipients = Array(additionalRecipients)
        let message = messageBuilder.build()
        messageSender.sendMessage(message.asPreparer,
                                  success: {
                                    Logger.info("Successfully sent message.")
        },
                                  failure: { error in
                                    owsFailDebug("Failed to send message with error: \(error)")
        })
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

        return firstly(on: .global()) { () -> TSGroupThread in
            try databaseStorage.write { (transaction: SDSAnyWriteTransaction) -> TSGroupThread in
                try migrateGroupInDatabaseAndCreateInfoMessage(groupIdV1: groupIdV1,
                                                               groupModelV2: groupModelV2,
                                                               disappearingMessageToken: disappearingMessageToken,
                                                               groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                               transaction: transaction)
            }
        }.then(on: .global()) { (groupThread: TSGroupThread) -> Promise<TSGroupThread> in
            guard shouldSendMessage else {
                return Promise.value(groupThread)
            }

            return firstly {
                sendGroupUpdateMessage(thread: groupThread)
            }.map(on: .global()) { _ in
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
        let newGroupModelV2 = try groupModelBuilder.buildAsV2(transaction: transaction)

        guard newGroupModelV2.groupsVersion == .V2 else {
            throw OWSAssertionError("Invalid v2 group model.")
        }
        let inProfileWhitelist = profileManager.isThread(inProfileWhitelist: groupThreadV1,
                                                         transaction: transaction)
        let isBlocked = blockingManager.isGroupIdBlocked(groupIdV1)

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
            blockingManager.addBlockedGroup(newGroupModelV2, blockMode: .remote, transaction: transaction)
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

        // Step 3: Update group in database, if necessary.
        let oldGroupModel = groupThread.groupModel
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
            insertGroupUpdateInfoMessage(groupThread: groupThread,
                                         oldGroupModel: oldGroupModel,
                                         newGroupModel: newGroupModel,
                                         oldDisappearingMessageToken: updateDMResult.oldDisappearingMessageToken,
                                         newDisappearingMessageToken: updateDMResult.newDisappearingMessageToken,
                                         groupUpdateSourceAddress: groupUpdateSourceAddress,
                                         transaction: transaction)
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
        guard !groupsV2.isGroupKnownToStorageService(groupModel: groupModel,
                                                     transaction: transaction) else {
            // To avoid redundant storage service writes,
            // don't bother notifying the storage service
            // about v2 groups it already knows about.
            return
        }

        storageServiceManager.recordPendingUpdates(groupModel: groupModel)
    }

    // MARK: - "Group Update" Info Messages

    // NOTE: This should only be called by GroupManager and by DebugUI.
    public static func insertGroupUpdateInfoMessage(groupThread: TSGroupThread,
                                                    oldGroupModel: TSGroupModel?,
                                                    newGroupModel: TSGroupModel,
                                                    oldDisappearingMessageToken: DisappearingMessageToken?,
                                                    newDisappearingMessageToken: DisappearingMessageToken,
                                                    groupUpdateSourceAddress: SignalServiceAddress?,
                                                    transaction: SDSAnyWriteTransaction) {

        guard let localAddress = tsAccountManager.localAddress else {
            return owsFailDebug("missing local address")
        }

        var userInfo: [InfoMessageUserInfoKey: Any] = [
            .newGroupModel: newGroupModel,
            .newDisappearingMessageToken: newDisappearingMessageToken
        ]
        if let oldGroupModel = oldGroupModel {
            userInfo[.oldGroupModel] = oldGroupModel
        }
        if let oldDisappearingMessageToken = oldDisappearingMessageToken {
            userInfo[.oldDisappearingMessageToken] = oldDisappearingMessageToken
        }
        if let groupUpdateSourceAddress = groupUpdateSourceAddress {
            userInfo[.groupUpdateSourceAddress] = groupUpdateSourceAddress
        }
        let infoMessage = TSInfoMessage(thread: groupThread,
                                        messageType: .typeGroupUpdate,
                                        infoMessageUserInfo: userInfo)
        infoMessage.anyInsert(transaction: transaction)

        let wasLocalUserInGroup = oldGroupModel?.groupMembership.isMemberOfAnyKind(localAddress) ?? false
        let isLocalUserInGroup = newGroupModel.groupMembership.isMemberOfAnyKind(localAddress)

        if let groupUpdateSourceAddress = groupUpdateSourceAddress,
            groupUpdateSourceAddress.isLocalAddress {
            infoMessage.markAsRead(atTimestamp: NSDate.ows_millisecondTimeStamp(),
                                   thread: groupThread,
                                   circumstance: .readOnThisDevice,
                                   transaction: transaction)
        } else if !wasLocalUserInGroup && isLocalUserInGroup {
            // Notify when the local user is added or invited to a group.
            SSKEnvironment.shared.notificationsManager.notifyUser(
                for: infoMessage,
                thread: groupThread,
                wantsSound: true,
                transaction: transaction
            )
        }
    }

    // MARK: - Capabilities

    private static let groupsV2CapabilityStore = SDSKeyValueStore(collection: "GroupManager.groupsV2Capability")
    private static let groupsV2MigrationCapabilityStore = SDSKeyValueStore(collection: "GroupManager.groupsV2MigrationCapability")

    @objc
    public static func doesUserHaveGroupsV2Capability(address: SignalServiceAddress,
                                                      transaction: SDSAnyReadTransaction) -> Bool {
        if DebugFlags.groupsV2IgnoreCapability {
            return true
        }
        guard let uuid = address.uuid else {
            return false
        }
        return groupsV2CapabilityStore.getBool(uuid.uuidString, defaultValue: false, transaction: transaction)
    }

    @objc
    public static func doesUserHaveGroupsV2MigrationCapability(address: SignalServiceAddress,
                                                               transaction: SDSAnyReadTransaction) -> Bool {
        if DebugFlags.groupsV2migrationsIgnoreMigrationCapability {
            return true
        }
        guard let uuid = address.uuid else {
            return false
        }
        return groupsV2MigrationCapabilityStore.getBool(uuid.uuidString, defaultValue: false, transaction: transaction)
    }

    @objc
    public static func setUserCapabilities(address: SignalServiceAddress,
                                           hasGroupsV2Capability: Bool,
                                           hasGroupsV2MigrationCapability: Bool,
                                           transaction: SDSAnyWriteTransaction) {
        guard let uuid = address.uuid else {
            Logger.warn("Address without uuid: \(address)")
            return
        }
        let key = uuid.uuidString
        groupsV2CapabilityStore.setBoolIfChanged(hasGroupsV2Capability,
                                                 defaultValue: false,
                                                 key: key,
                                                 transaction: transaction)
        groupsV2MigrationCapabilityStore.setBoolIfChanged(hasGroupsV2MigrationCapability,
                                                          defaultValue: false,
                                                          key: key,
                                                          transaction: transaction)
    }

    // MARK: - Profiles

    private static func autoWhitelistGroupIfNecessary(oldGroupModel: TSGroupModel?,
                                                      newGroupModel: TSGroupModel,
                                                      groupUpdateSourceAddress: SignalServiceAddress?,
                                                      transaction: SDSAnyWriteTransaction) {

        guard wasLocalUserJustAddedToTheGroup(oldGroupModel: oldGroupModel,
                                              newGroupModel: newGroupModel) else {
                                                return
        }

        guard let groupUpdateSourceAddress = groupUpdateSourceAddress else {
            Logger.verbose("No groupUpdateSourceAddress.")
            return
        }

        let shouldAddToWhitelist = (groupUpdateSourceAddress.isLocalAddress ||
            contactsManager.isSystemContact(address: groupUpdateSourceAddress) ||
            profileManager.isUser(inProfileWhitelist: groupUpdateSourceAddress, transaction: transaction))
        guard shouldAddToWhitelist else {
            Logger.verbose("Not adding to whitelist.")
            return
        }

        // Ensure the thread is in our profile whitelist if we're a member of the group.
        // We don't want to do this if we're just a pending member or are leaving/have
        // already left the group.
        self.profileManager.addGroupId(toProfileWhitelist: newGroupModel.groupId,
                                       wasLocallyInitiated: true,
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
        profileManager.fillInMissingProfileKeys(profileKeysByAddress)
    }

    public static func ensureLocalProfileHasCommitmentIfNecessary() -> Promise<Void> {
        guard tsAccountManager.isOnboarded() else {
            return Promise.value(())
        }
        guard let localAddress = self.tsAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Missing localAddress."))
        }

        return databaseStorage.read(.promise) { transaction -> Bool in
            return self.groupsV2.hasProfileKeyCredential(for: localAddress,
                                                         transaction: transaction)
        }.then(on: .global()) { hasLocalCredential -> Promise<Void> in
            guard !hasLocalCredential else {
                return Promise.value(())
            }
            guard tsAccountManager.isRegisteredPrimaryDevice else {
                // On secondary devices, just re-fetch the local
                // profile.
                return self.profileManager.fetchLocalUsersProfilePromise().asVoid()
            }

            // We (and other clients) need a profile key credential for
            // all group members to use groups v2.  Other clients can't
            // request our profile key credential from the service until
            // until we've uploaded a profile key commitment to the service.
            //
            // If we've never done a versioned profile update, try to do so now.
            // This step might or might not be necessary. It's simpler and safer
            // to always do it. It won't amount to much extra work and we'll
            // probably do it at most once.  Once we have a profile key credential
            // for the local user (which should last forever) we'll abort above.
            // Group v2 actions will use tryToEnsureProfileKeyCredentials()
            // and we want to set them up to succeed.
            return self.groupsV2.reuploadLocalProfilePromise()
        }
    }

    // MARK: - Network Errors

    static func isNetworkFailureOrTimeout(_ error: Error) -> Bool {
        if IsNetworkConnectivityFailure(error) {
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
            self.messageProcessing.allMessageFetchingAndProcessingPromise()
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
