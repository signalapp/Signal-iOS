//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class UpsertGroupResult: NSObject {
    @objc
    public enum Action: UInt {
        case inserted
        case updated
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
        return TSAccountManager.sharedInstance()
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

    // MARK: -

    // Never instantiate this class.
    private override init() {}

    // MARK: -

    // GroupsV2 TODO: Finalize this value with the designers.
    public static let KGroupUpdateTimeoutDuration: TimeInterval = 30

    private static func groupIdLength(for groupsVersion: GroupsVersion) -> Int32 {
        switch groupsVersion {
        case .V1:
            return kGroupIdLengthV1
        case .V2:
            return kGroupIdLengthV2
        }
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
                owsFailDebug("Invalid groupId: \(groupId.count) != \(kGroupIdLengthV1), \(kGroupIdLengthV2)")
                return false
        }
        return true
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
        // * We don't know their UUID.
        // * We don't know their profile key.
        // * They've never done a versioned profile update.
        // * We don't have a profile key credential for them.
        return true
    }

    @objc
    public static var defaultGroupsVersion: GroupsVersion {
        guard RemoteConfig.groupsV2CreateGroups else {
            return .V1
        }
        return .V2
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

        return firstly {
            return self.ensureLocalProfileHasCommitmentIfNecessary()
        }.map(on: .global()) { () throws -> GroupMembership in
            // Build member list.
            //
            // GroupsV2 TODO: Handle roles, etc.
            var builder = GroupMembership.Builder()
            builder.addNonPendingMembers(Set(membersParam), role: .normal)
            builder.remove(localAddress)
            builder.addNonPendingMember(localAddress, role: .administrator)
            return builder.build()
        }.then(on: .global()) { (groupMembership: GroupMembership) -> Promise<GroupMembership> in
            // If we might create a v2 group,
            // try to obtain profile key credentials for all group members
            // including ourself, unless we already have them on hand.
            guard RemoteConfig.groupsV2CreateGroups else {
                return Promise.value(groupMembership)
            }
            return firstly {
                self.groupsV2.tryToEnsureProfileKeyCredentials(for: Array(groupMembership.allUsers))
            }.map(on: .global()) { (_) -> GroupMembership in
                return groupMembership
            }
        }.map(on: .global()) { (proposedGroupMembership: GroupMembership) throws -> TSGroupModel in
            // GroupsV2 TODO: Let users specify access levels in the "new group" view.
            let groupAccess = GroupAccess.defaultV2Access
            let groupModel = try self.databaseStorage.read { (transaction) throws -> TSGroupModel in
                // Before we create a v2 group, we need to separate out the
                // pending and non-pending members.  If we already know we're
                // going to create a v1 group, we shouldn't separate them.
                let groupMembership = self.separatePendingMembers(in: proposedGroupMembership,
                                                                  oldGroupModel: nil,
                                                                  transaction: transaction)

                guard groupMembership.nonPendingMembers.contains(localAddress) else {
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
            guard proposedGroupModel.groupsVersion == .V2 else {
                // v1 groups don't need to be created on the service.
                return Promise.value(proposedGroupModel)
            }
            return firstly {
                self.groupsV2.createNewGroupOnService(groupModel: proposedGroupModel)
            }.then(on: .global()) { _ in
                self.groupsV2.fetchCurrentGroupV2Snapshot(groupModel: proposedGroupModel)
            }.map(on: .global()) { (groupV2Snapshot: GroupV2Snapshot) -> TSGroupModel in
                let createdGroupModel = try self.databaseStorage.read { transaction in
                    return try TSGroupModelBuilder(groupV2Snapshot: groupV2Snapshot).build(transaction: transaction)
                }
                if proposedGroupModel != createdGroupModel {
                    Logger.verbose("proposedGroupModel: \(proposedGroupModel.debugDescription)")
                    Logger.verbose("createdGroupModel: \(createdGroupModel.debugDescription)")
                    owsFailDebug("Proposed group model does not match created group model.")
                }
                return createdGroupModel
            }
        }.then(on: .global()) { (groupModel: TSGroupModel) -> Promise<TSGroupThread> in
            let thread = databaseStorage.write { (transaction: SDSAnyWriteTransaction) -> TSGroupThread in
                return self.insertGroupThreadInDatabaseAndCreateInfoMessage(groupModel: groupModel,
                                                                            disappearingMessageToken: disappearingMessageToken,
                                                                            groupUpdateSourceAddress: localAddress,
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
        }.timeout(seconds: GroupManager.KGroupUpdateTimeoutDuration) {
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
    private static func separatePendingMembers(in newGroupMembership: GroupMembership,
                                               oldGroupModel: TSGroupModel?,
                                               transaction: SDSAnyReadTransaction) -> GroupMembership {
        guard let localUuid = tsAccountManager.localUuid else {
            owsFailDebug("Missing localUuid.")
            return newGroupMembership
        }
        let localAddress = SignalServiceAddress(uuid: localUuid)
        let newMembers: Set<SignalServiceAddress>
        var builder = GroupMembership.Builder()
        if let oldGroupModel = oldGroupModel {
            // Updating existing group
            let oldGroupMembership = oldGroupModel.groupMembership

            assert(oldGroupModel.groupsVersion == .V2)
            newMembers = newGroupMembership.allUsers.subtracting(oldGroupMembership.allUsers)

            // Carry over existing members as they stand.
            let existingMembers = oldGroupMembership.allUsers.intersection(newGroupMembership.allUsers)
            for address in existingMembers {
                builder.copyMember(address, from: oldGroupMembership)
            }
        } else {
            // Creating new group

            // First, skip separation when creating v1 groups.
            guard canUseV2(for: newGroupMembership.allUsers, transaction: transaction) else {
                // If any member of a new group doesn't support groups v2,
                // we're going to create a v1 group.  In that case, we
                // don't want to separate out pending members.
                return newGroupMembership
            }

            newMembers = newGroupMembership.allUsers
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
                // GroupsV2 TODO: This should probably throw after we rework
                // the create and update group views.
                owsFailDebug("Invalid address: \(address)")
                continue
            }

            // We must call this _after_ we try to fetch profile key credentials for
            // all members.
            //
            // GroupsV2 TODO: We may need to consult the user's capabilities.
            let isPending = !groupsV2.hasProfileKeyCredential(for: address,
                                                              transaction: transaction)
            guard let role = newGroupMembership.role(for: address) else {
                owsFailDebug("Missing role: \(address)")
                continue
            }

            // If groupsV2forceInvites is set, we invite other members
            // instead of adding them.
            if address != localAddress &&
                DebugFlags.groupsV2forceInvites {
                builder.addPendingMember(address, role: role, addedByUuid: localUuid)
            } else if isPending {
                builder.addPendingMember(address, role: role, addedByUuid: localUuid)
            } else {
                builder.addNonPendingMember(address, role: role)
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
        localCreateNewGroup(members: members,
                            groupId: groupId,
                            name: name,
                            avatarImage: avatarImage,
                            newGroupSeed: newGroupSeed,
                            shouldSendMessage: shouldSendMessage).done { thread in
                                success(thread)
        }.catch { error in
            failure(error)
        }.retainUntilComplete()
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
        localCreateNewGroup(members: members,
                            groupId: groupId,
                            name: name,
                            avatarData: avatarData,
                            newGroupSeed: newGroupSeed,
                            shouldSendMessage: shouldSendMessage).done { thread in
                                success(thread)
        }.catch { error in
            failure(error)
        }.retainUntilComplete()
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
            let groupsVersion = self.defaultGroupsVersion
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
        let groupAccess = GroupAccess.allAccess
        // Use buildGroupModel() to fill in defaults, like it was a new group.

        var builder = TSGroupModelBuilder()
        builder.groupId = groupId
        builder.name = name
        builder.avatarData = avatarData
        builder.groupMembership = groupMembership
        builder.groupAccess = groupAccess
        builder.groupsVersion = groupsVersion
        let groupModel = try builder.build(transaction: transaction)

        // Just create it in the database, don't create it on the service.
        //
        // GroupsV2 TODO: Update method to handle admins, pending members, etc.
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
                                                   transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {

        guard isValidGroupId(groupId, groupsVersion: .V1) else {
            throw OWSAssertionError("Invalid group id.")
        }

        let groupMembership = GroupMembership(v1Members: Set(members))

        var builder = TSGroupModelBuilder()
        builder.groupId = groupId
        builder.name = name
        builder.avatarData = avatarData
        builder.groupMembership = groupMembership
        builder.groupsVersion = .V1
        let groupModel = try builder.build(transaction: transaction)

        return try remoteUpsertExistingGroup(groupModel: groupModel,
                                             disappearingMessageToken: disappearingMessageToken,
                                             groupUpdateSourceAddress: groupUpdateSourceAddress,
                                             transaction: transaction)
    }

    // If disappearingMessageToken is nil, don't update the disappearing messages configuration.
    public static func remoteUpsertExistingGroup(groupModel: TSGroupModel,
                                                 disappearingMessageToken: DisappearingMessageToken?,
                                                 groupUpdateSourceAddress: SignalServiceAddress?,
                                                 transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {

        return try self.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: groupModel,
                                                                                     newDisappearingMessageToken: disappearingMessageToken,
                                                                                     groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                     canInsert: true,
                                                                                     transaction: transaction)
    }

    // MARK: - Update Existing Group

    // Unlike remoteUpsertExistingGroupV1(), this method never inserts.
    //
    // If disappearingMessageToken is nil, don't update the disappearing messages configuration.
    @objc
    public static func remoteUpdateToExistingGroupV1(groupId: Data,
                                                     name: String? = nil,
                                                     avatarData: Data? = nil,
                                                     groupMembership: GroupMembership,
                                                     disappearingMessageToken: DisappearingMessageToken?,
                                                     groupUpdateSourceAddress: SignalServiceAddress?,
                                                     transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {

        let updateInfo: UpdateInfo
        do {
            updateInfo = try self.updateInfoV1(groupId: groupId,
                                               name: name,
                                               avatarData: avatarData,
                                               groupMembership: groupMembership,
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
                                                                                     transaction: transaction)
    }

    // MARK: - Update Existing Group

    private struct UpdateInfo {
        let groupId: Data
        let oldGroupModel: TSGroupModel
        let newGroupModel: TSGroupModel
        let oldDMConfiguration: OWSDisappearingMessagesConfiguration
        let newDMConfiguration: OWSDisappearingMessagesConfiguration
    }

    // If dmConfiguration is nil, don't change the disappearing messages configuration.
    public static func localUpdateExistingGroup(groupId: Data,
                                                name: String? = nil,
                                                avatarData: Data? = nil,
                                                groupMembership: GroupMembership,
                                                groupAccess: GroupAccess,
                                                groupsVersion: GroupsVersion,
                                                dmConfiguration: OWSDisappearingMessagesConfiguration?,
                                                groupUpdateSourceAddress: SignalServiceAddress?) -> Promise<TSGroupThread> {

        switch groupsVersion {
        case .V1:
            return localUpdateExistingGroupV1(groupId: groupId,
                                              name: name,
                                              avatarData: avatarData,
                                              groupMembership: groupMembership,
                                              dmConfiguration: dmConfiguration,
                                              groupUpdateSourceAddress: groupUpdateSourceAddress)
        case .V2:
            return localUpdateExistingGroupV2(groupId: groupId,
                                              name: name,
                                              avatarData: avatarData,
                                              groupMembership: groupMembership,
                                              groupAccess: groupAccess,
                                              dmConfiguration: dmConfiguration,
                                              groupUpdateSourceAddress: groupUpdateSourceAddress)

        }
    }

    // If dmConfiguration is nil, don't change the disappearing messages configuration.
    private static func localUpdateExistingGroupV1(groupId: Data,
                                                   name: String? = nil,
                                                   avatarData: Data? = nil,
                                                   groupMembership: GroupMembership,
                                                   dmConfiguration: OWSDisappearingMessagesConfiguration?,
                                                   groupUpdateSourceAddress: SignalServiceAddress?) -> Promise<TSGroupThread> {

        return self.databaseStorage.write(.promise) { (transaction) throws -> UpsertGroupResult in
            let updateInfo = try self.updateInfoV1(groupId: groupId,
                                                   name: name,
                                                   avatarData: avatarData,
                                                   groupMembership: groupMembership,
                                                   dmConfiguration: dmConfiguration,
                                                   transaction: transaction)
            let newGroupModel = updateInfo.newGroupModel
            let upsertGroupResult = try self.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                                          newDisappearingMessageToken: dmConfiguration?.asToken,
                                                                                                          groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                                          canInsert: false,
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
    //
    // GroupsV2 TODO: This should block on message processing.
    private static func localUpdateExistingGroupV2(groupId: Data,
                                                   name: String? = nil,
                                                   avatarData: Data? = nil,
                                                   groupMembership: GroupMembership,
                                                   groupAccess: GroupAccess,
                                                   dmConfiguration: OWSDisappearingMessagesConfiguration?,
                                                   groupUpdateSourceAddress: SignalServiceAddress?) -> Promise<TSGroupThread> {

        return firstly {
            return self.ensureLocalProfileHasCommitmentIfNecessary()
        }.then(on: DispatchQueue.global()) { () -> Promise<String?> in
            guard let avatarData = avatarData else {
                // No avatar to upload.
                return Promise.value(nil)
            }
            let groupModel = try self.databaseStorage.read { (transaction: SDSAnyReadTransaction) throws -> TSGroupModelV2 in
                guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                    throw OWSAssertionError("Thread does not exist.")
                }
                guard let groupModel = thread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid groupModel")
                }
                return groupModel
            }
            if groupModel.groupAvatarData == avatarData && groupModel.groupAvatarUrlPath != nil {
                // Skip redundant upload; the avatar hasn't changed.
                return Promise.value(groupModel.groupAvatarUrlPath)
            }
            return firstly {
                // Upload avatar.
                return self.groupsV2.uploadGroupAvatar(avatarData: avatarData,
                                                       groupSecretParamsData: groupModel.secretParamsData)
            }.map(on: .global()) { (avatarUrlPath: String) throws -> String? in
                // Convert Promise<String> to Promise<String?>
                return avatarUrlPath
            }
        }.map(on: .global()) { (avatarUrlPath: String?) throws -> (UpdateInfo, GroupsV2ChangeSet) in
            return try databaseStorage.read { transaction in
                let updateInfo = try self.updateInfoV2(groupId: groupId,
                                                       name: name,
                                                       avatarData: avatarData,
                                                       avatarUrlPath: avatarUrlPath,
                                                       groupMembership: groupMembership,
                                                       groupAccess: groupAccess,
                                                       newDMConfiguration: dmConfiguration,
                                                       transaction: transaction)
                let changeSet = try self.groupsV2.buildChangeSet(oldGroupModel: updateInfo.oldGroupModel,
                                                                 newGroupModel: updateInfo.newGroupModel,
                                                                 oldDMConfiguration: updateInfo.oldDMConfiguration,
                                                                 newDMConfiguration: updateInfo.newDMConfiguration,
                                                                 transaction: transaction)
                return (updateInfo, changeSet)
            }
        }.then(on: .global()) { (_: UpdateInfo, changeSet: GroupsV2ChangeSet) throws -> Promise<TSGroupThread> in
            return self.groupsV2.updateExistingGroupOnService(changeSet: changeSet)
        }.timeout(seconds: GroupManager.KGroupUpdateTimeoutDuration) {
            GroupsV2Error.timeout
        }
        // GroupsV2 TODO: Handle redundant change error.
    }

    // If dmConfiguration is nil, don't change the disappearing messages configuration.
    private static func updateInfoV1(groupId: Data,
                                     name: String? = nil,
                                     avatarData: Data? = nil,
                                     groupMembership proposedGroupMembership: GroupMembership,
                                     dmConfiguration: OWSDisappearingMessagesConfiguration?,
                                     transaction: SDSAnyReadTransaction) throws -> UpdateInfo {
        guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            throw OWSAssertionError("Thread does not exist.")
        }
        let oldGroupModel = thread.groupModel
        guard oldGroupModel.groupsVersion == .V1 else {
            throw OWSAssertionError("Invalid groupsVersion.")
        }
        guard let localAddress = tsAccountManager.localAddress else {
            throw OWSAssertionError("Missing localAddress.")
        }

        let oldDMConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: thread, transaction: transaction)
        let newDMConfiguration = dmConfiguration ?? oldDMConfiguration

        // Always ensure we're a member of any v1 group we're updating.
        var builder = proposedGroupMembership.asBuilder
        builder.remove(localAddress)
        builder.addNonPendingMember(localAddress, role: .normal)
        let groupMembership = builder.build()

        var groupModelBuilder = oldGroupModel.asBuilder
        groupModelBuilder.name = name
        groupModelBuilder.avatarData = avatarData
        groupModelBuilder.groupMembership = groupMembership
        groupModelBuilder.name = name
        let newGroupModel = try groupModelBuilder.build(transaction: transaction)

        if oldGroupModel.isEqual(to: newGroupModel) {
            // Skip redundant update.
            throw GroupsV2Error.redundantChange
        }

        return UpdateInfo(groupId: groupId,
                          oldGroupModel: oldGroupModel,
                          newGroupModel: newGroupModel,
                          oldDMConfiguration: oldDMConfiguration,
                          newDMConfiguration: newDMConfiguration)
    }

    // If dmConfiguration is nil, don't change the disappearing messages configuration.
    private static func updateInfoV2(groupId: Data,
                                     name: String? = nil,
                                     avatarData: Data? = nil,
                                     avatarUrlPath: String?,
                                     groupMembership proposedGroupMembership: GroupMembership,
                                     groupAccess: GroupAccess,
                                     newDMConfiguration dmConfiguration: OWSDisappearingMessagesConfiguration?,
                                     transaction: SDSAnyReadTransaction) throws -> UpdateInfo {

        guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            throw OWSAssertionError("Thread does not exist.")
        }
        guard let oldGroupModel = thread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Invalid groupModel.")
        }
        guard let localAddress = tsAccountManager.localAddress else {
            throw OWSAssertionError("Missing localAddress.")
        }

        let oldDMConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: thread, transaction: transaction)
        let newDMConfiguration = dmConfiguration ?? oldDMConfiguration

        for address in proposedGroupMembership.allUsers {
            guard address.uuid != nil else {
                throw OWSAssertionError("Group v2 member missing uuid.")
            }
        }
        // Before we update a v2 group, we need to separate out the
        // pending and non-pending members.
        let groupMembership = self.separatePendingMembers(in: proposedGroupMembership,
                                                          oldGroupModel: oldGroupModel,
                                                          transaction: transaction)

        guard groupMembership.nonPendingMembers.contains(localAddress) else {
            throw OWSAssertionError("Missing localAddress.")
        }

        // Don't try to modify a v2 group if we're not a member.
        guard groupMembership.nonPendingMembers.contains(localAddress) else {
            throw OWSAssertionError("Missing localAddress.")
        }

        let hasAvatarUrlPath = avatarUrlPath != nil
        let hasAvatarData = avatarData != nil
        guard hasAvatarUrlPath == hasAvatarData else {
            throw OWSAssertionError("hasAvatarUrlPath: \(hasAvatarData) != hasAvatarData.")
        }

        // GroupsV2 TODO: Eventually we won't need to increment the revision here,
        //                since we'll probably be updating the TSGroupThread's
        //                group models with one derived from the service.
        let newRevision = oldGroupModel.groupV2Revision + 1

        var builder = TSGroupModelBuilder()
        builder.groupId = oldGroupModel.groupId
        builder.name = name
        builder.avatarData = avatarData
        builder.groupMembership = groupMembership
        builder.groupAccess = groupAccess
        builder.groupsVersion = oldGroupModel.groupsVersion
        builder.groupV2Revision = newRevision
        builder.groupSecretParamsData = oldGroupModel.groupSecretParamsData
        builder.avatarUrlPath = avatarUrlPath
        let newGroupModel = try builder.build(transaction: transaction)

        if oldGroupModel.isEqual(to: newGroupModel) {
            // Skip redundant update.
            throw GroupsV2Error.redundantChange
        }

        return UpdateInfo(groupId: groupId,
                          oldGroupModel: oldGroupModel,
                          newGroupModel: newGroupModel,
                          oldDMConfiguration: oldDMConfiguration,
                          newDMConfiguration: newDMConfiguration)
    }

    @objc
    public static func remoteUpdateToExistingGroupV1(groupId: Data,
                                                     name: String? = nil,
                                                     avatarData: Data? = nil,
                                                     groupMembership: GroupMembership,
                                                     groupUpdateSourceAddress: SignalServiceAddress?,
                                                     transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {

        let updateInfo: UpdateInfo
        do {
            updateInfo = try self.updateInfoV1(groupId: groupId,
                                               name: name,
                                               avatarData: avatarData,
                                               groupMembership: groupMembership,
                                               dmConfiguration: nil,
                                               transaction: transaction)
        } catch GroupsV2Error.redundantChange {
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("Missing groupThread.")
            }
            return UpsertGroupResult(action: .unchanged, groupThread: groupThread)
        }
        let newGroupModel = updateInfo.newGroupModel
        // newDisappearingMessageToken is nil, don't update the disappearing messages configuration.
        return try self.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                     newDisappearingMessageToken: nil,
                                                                                     groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                     canInsert: false,
                                                                                     transaction: transaction)
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
        guard groupThread.groupModel.groupsVersion == .V2 else {
            return simpleUpdate()
        }

        return firstly {
            return self.ensureLocalProfileHasCommitmentIfNecessary()
        }.then(on: .global()) { () throws -> Promise<TSGroupThread> in
            return groupsV2.updateDisappearingMessageStateOnService(groupThread: groupThread,
                                                                    disappearingMessageToken: disappearingMessageToken)
        }.timeout(seconds: GroupManager.KGroupUpdateTimeoutDuration) {
            GroupsV2Error.timeout
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
        let newConfiguration: OWSDisappearingMessagesConfiguration
        if newToken.isEnabled {
            newConfiguration = oldConfiguration.copyAsEnabled(withDurationSeconds: newToken.durationSeconds)
        } else {
            newConfiguration = oldConfiguration.copy(withIsEnabled: false)
        }
        newConfiguration.anyUpsert(transaction: transaction)

        if shouldInsertInfoMessage {
            var remoteContactName: String?
            if let groupUpdateSourceAddress = groupUpdateSourceAddress,
                groupUpdateSourceAddress.isValid,
                !groupUpdateSourceAddress.isLocalAddress {
                remoteContactName = contactsManager.displayName(for: groupUpdateSourceAddress, transaction: transaction)
            }
            let infoMessage = OWSDisappearingConfigurationUpdateInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(),
                                                                            thread: thread,
                                                                            configuration: newConfiguration,
                                                                            createdByRemoteName: remoteContactName,
                                                                            createdInExistingGroup: false)
            infoMessage.anyInsert(transaction: transaction)
        }

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

    public static func localAcceptInviteToGroupV2(groupThread: TSGroupThread) -> Promise<TSGroupThread> {

        return firstly {
            return self.ensureLocalProfileHasCommitmentIfNecessary()
        }.then(on: .global()) { () throws -> Promise<TSGroupThread> in
            return self.groupsV2.acceptInviteToGroupV2(groupThread: groupThread)
        }.timeout(seconds: GroupManager.KGroupUpdateTimeoutDuration) {
            GroupsV2Error.timeout
        }
    }

    // MARK: - Leave Group / Decline Invite

    public static func localLeaveGroupOrDeclineInvite(groupThread: TSGroupThread) -> Promise<TSGroupThread> {
        switch groupThread.groupModel.groupsVersion {
        case .V1:
            return localLeaveGroupV1(groupId: groupThread.groupModel.groupId)
        case .V2:
            return localLeaveGroupV2OrDeclineInvite(groupThread: groupThread)
        }
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
            guard oldGroupModel.groupMembership.allUsers.contains(localAddress) else {
                throw OWSAssertionError("Local user is not a member of the group.")
            }

            let messageBuilder = TSOutgoingMessageBuilder(thread: groupThread)
            messageBuilder.groupMetaMessage = .quit
            let message = messageBuilder.build()
            self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)

            let threadMessageCount = groupThread.numberOfInteractions(with: transaction)
            let skipInfoMessage = threadMessageCount == 0

            var groupMembershipBuilder = oldGroupModel.groupMembership.asBuilder
            groupMembershipBuilder.remove(localAddress)
            let newGroupMembership = groupMembershipBuilder.build()

            var builder = oldGroupModel.asBuilder
            builder.groupMembership = newGroupMembership
            let newGroupModel = try builder.build(transaction: transaction)

            let groupUpdateSourceAddress = localAddress
            let result = try self.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                          newDisappearingMessageToken: nil,
                                                                                          groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                          skipInfoMessage: skipInfoMessage,
                                                                                          transaction: transaction)
            return result.groupThread
        }
    }

    private static func localLeaveGroupV2OrDeclineInvite(groupThread: TSGroupThread) -> Promise<TSGroupThread> {
        return firstly {
            return self.ensureLocalProfileHasCommitmentIfNecessary()
        }.then(on: .global()) { () throws -> Promise<TSGroupThread> in
            return self.groupsV2.leaveGroupV2OrDeclineInvite(groupThread: groupThread)
        }.timeout(seconds: GroupManager.KGroupUpdateTimeoutDuration) {
            GroupsV2Error.timeout
        }
    }

    // MARK: - Messages

    @objc
    public static func sendGroupUpdateMessageObjc(thread: TSGroupThread) -> AnyPromise {
        return AnyPromise(self.sendGroupUpdateMessage(thread: thread))
    }

    public static func sendGroupUpdateMessage(thread: TSGroupThread,
                                              changeActionsProtoData: Data? = nil) -> Promise<Void> {

        guard !DebugFlags.groupsV2dontSendUpdates else {
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
                self.addAdditionalRecipients(to: messageBuilder,
                                             groupThread: thread,
                                             transaction: transaction)
            }
            return messageBuilder.build()
        }.then(on: .global()) { (message: TSOutgoingMessage) throws -> Promise<Void> in
            let groupModel = thread.groupModel
            // V1 group updates need to include the group avatar (if any)
            // as an attachment.
            if thread.isGroupV1Thread,
                let avatarData = groupModel.groupAvatarData,
                avatarData.count > 0 {
                if let dataSource = DataSourceValue.dataSource(with: avatarData, fileExtension: "png") {
                    // DURABLE CLEANUP - currently one caller uses the completion handler to delete the tappable error message
                    // which causes this code to be called. Once we're more aggressive about durable sending retry,
                    // we could get rid of this "retryable tappable error message".
                    return self.messageSender.sendTemporaryAttachment(.promise,
                                                                      dataSource: dataSource,
                                                                      contentType: OWSMimeTypeImagePng,
                                                                      message: message)
                        .done(on: .global()) { _ in
                            Logger.debug("Successfully sent group update with avatar")
                    }.recover(on: .global()) { error in
                        owsFailDebug("Failed to send group avatar update with error: \(error)")
                        throw error
                    }
                }
            }

            // DURABLE CLEANUP - currently one caller uses the completion handler to delete the tappable error message
            // which causes this code to be called. Once we're more aggressive about durable sending retry,
            // we could get rid of this "retryable tappable error message".
            return self.messageSender.sendMessage(.promise, message.asPreparer)
        }
    }

    private static func sendDurableNewGroupMessage(forThread thread: TSGroupThread) -> Promise<Void> {
        guard !DebugFlags.groupsV2dontSendUpdates else {
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
        let additionalRecipients = groupThread.groupModel.pendingMembers.filter { address in
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

    // MARK: - Group Database

    // If disappearingMessageToken is nil, don't update the disappearing messages configuration.
    public static func insertGroupThreadInDatabaseAndCreateInfoMessage(groupModel: TSGroupModel,
                                                                       disappearingMessageToken: DisappearingMessageToken?,
                                                                       groupUpdateSourceAddress: SignalServiceAddress?,
                                                                       transaction: SDSAnyWriteTransaction) -> TSGroupThread {
        let groupThread = TSGroupThread(groupModelPrivate: groupModel)
        groupThread.anyInsert(transaction: transaction)

        let newDisappearingMessageToken = disappearingMessageToken ?? DisappearingMessageToken.disabledToken

        insertGroupUpdateInfoMessage(groupThread: groupThread,
                                     oldGroupModel: nil,
                                     newGroupModel: groupModel,
                                     oldDisappearingMessageToken: nil,
                                     newDisappearingMessageToken: newDisappearingMessageToken,
                                     groupUpdateSourceAddress: groupUpdateSourceAddress,
                                     transaction: transaction)

        return groupThread
    }

    // If newDisappearingMessageToken is nil, don't update the disappearing messages configuration.
    public static func tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: TSGroupModel,
                                                                                    newDisappearingMessageToken: DisappearingMessageToken?,
                                                                                    groupUpdateSourceAddress: SignalServiceAddress?,
                                                                                    canInsert: Bool,
                                                                                    transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {

        let threadId = TSGroupThread.threadId(fromGroupId: newGroupModel.groupId)
        guard TSGroupThread.anyExists(uniqueId: threadId, transaction: transaction) else {
            guard canInsert else {
                throw OWSAssertionError("Missing groupThread.")
            }
            let thread = insertGroupThreadInDatabaseAndCreateInfoMessage(groupModel: newGroupModel,
                                                                         disappearingMessageToken: newDisappearingMessageToken,
                                                                         groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                         transaction: transaction)
            return UpsertGroupResult(action: .inserted, groupThread: thread)
        }

        return try updateExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                           newDisappearingMessageToken: newDisappearingMessageToken,
                                                                           groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                           transaction: transaction)
    }

    // If newDisappearingMessageToken is nil, don't update the disappearing messages configuration.
    public static func updateExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: TSGroupModel,
                                                                               newDisappearingMessageToken: DisappearingMessageToken?,
                                                                               groupUpdateSourceAddress: SignalServiceAddress?,
                                                                               skipInfoMessage: Bool = false,
                                                                               transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {

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
            guard !oldGroupModel.isEqual(to: newGroupModel) else {
                // Skip redundant update.
                return UpsertGroupResult(action: .unchanged, groupThread: groupThread)
            }

            if groupThread.groupModel.groupsVersion == .V2 {
                guard newGroupModel.groupV2Revision >= groupThread.groupModel.groupV2Revision else {
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

            groupThread.update(with: newGroupModel, transaction: transaction)

            return UpsertGroupResult(action: .updated, groupThread: groupThread)
        }()

        if updateDMResult.action == .unchanged &&
            updateThreadResult.action == .unchanged {
            // Neither DM config nor thread model changed.
            return updateThreadResult
        }

        if !skipInfoMessage {
            insertGroupUpdateInfoMessage(groupThread: groupThread,
                                         oldGroupModel: oldGroupModel,
                                         newGroupModel: newGroupModel,
                                         oldDisappearingMessageToken: updateDMResult.oldDisappearingMessageToken,
                                         newDisappearingMessageToken: updateDMResult.newDisappearingMessageToken,
                                         groupUpdateSourceAddress: groupUpdateSourceAddress,
                                         transaction: transaction)
        }

        return UpsertGroupResult(action: .updated, groupThread: groupThread)
    }

    private static func insertGroupUpdateInfoMessage(groupThread: TSGroupThread,
                                                     oldGroupModel: TSGroupModel?,
                                                     newGroupModel: TSGroupModel,
                                                     oldDisappearingMessageToken: DisappearingMessageToken?,
                                                     newDisappearingMessageToken: DisappearingMessageToken,
                                                     groupUpdateSourceAddress: SignalServiceAddress?,
                                                     transaction: SDSAnyWriteTransaction) {

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
    }

    // MARK: - Group Database

    @objc
    public static let groupsV2CapabilityStore = SDSKeyValueStore(collection: "GroupManager.groupsV2Capability")

    @objc
    public static func doesUserHaveGroupsV2Capability(address: SignalServiceAddress,
                                                      transaction: SDSAnyReadTransaction) -> Bool {
        if DebugFlags.groupsV2IgnoreCapability {
            return true
        }

        if let uuid = address.uuid {
            if groupsV2CapabilityStore.getBool(uuid.uuidString, defaultValue: false, transaction: transaction) {
                return true
            }
        }
        return false
    }

    @objc
    public static func setUserHasGroupsV2Capability(address: SignalServiceAddress,
                                                    value: Bool,
                                                    transaction: SDSAnyWriteTransaction) {
        if let uuid = address.uuid {
            groupsV2CapabilityStore.setBool(value, key: uuid.uuidString, transaction: transaction)
        }
    }

    // MARK: - Profiles

    @objc
    public static func updateProfileWhitelist(withGroupThread groupThread: TSGroupThread) {
        guard let localAddress = self.tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return
        }

        // Ensure the thread and all members of the group are in our profile whitelist
        // if we're a member of the group. We don't want to do this if we're just a
        // pending member or are leaving/have already left the group.
        let groupMembership = groupThread.groupModel.groupMembership
        guard groupMembership.isNonPendingMember(localAddress) else {
            return
        }
        profileManager.addThread(toProfileWhitelist: groupThread)
    }

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

        guard FeatureFlags.versionedProfiledUpdate else {
            // We don't need a profile key credential for the local user
            // if we're not even going to try to create a v2 group.
            if RemoteConfig.groupsV2CreateGroups {
                owsFailDebug("Can't participate in v2 groups without a profile key commitment.")
            }
            return Promise.value(())
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
}
