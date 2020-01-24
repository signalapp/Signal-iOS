//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class EnsureGroupResult: NSObject {
    @objc
    public enum Action: UInt {
        case inserted
        case updated
        case unchanged
    }

    @objc
    public let action: Action

    @objc
    public let thread: TSGroupThread

    public required init(action: Action, thread: TSGroupThread) {
        self.action = action
        self.thread = thread
    }
}

// MARK: -

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

    private class var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
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

    public static func buildGroupModel(groupId groupIdParam: Data?,
                                       name nameParam: String?,
                                       avatarData: Data?,
                                       groupMembership: GroupMembership,
                                       groupAccess: GroupAccess,
                                       groupsVersion groupsVersionParam: GroupsVersion? = nil,
                                       groupV2Revision: UInt32,
                                       groupSecretParamsData groupSecretParamsDataParam: Data? = nil,
                                       newGroupSeed newGroupSeedParam: NewGroupSeed? = nil,
                                       transaction: SDSAnyReadTransaction) throws -> TSGroupModel {

        let newGroupSeed: NewGroupSeed
        if let newGroupSeedParam = newGroupSeedParam {
            newGroupSeed = newGroupSeedParam
        } else {
            newGroupSeed = NewGroupSeed()
        }

        let allUsers = groupMembership.allUsers
        for recipientAddress in allUsers {
            guard recipientAddress.isValid else {
                throw OWSAssertionError("Invalid address.")
            }
        }
        var name: String?
        if let strippedName = nameParam?.stripped,
            strippedName.count > 0 {
            name = strippedName
        }

        let groupsVersion: GroupsVersion
        if let groupsVersionParam = groupsVersionParam {
            groupsVersion = groupsVersionParam
        } else {
            groupsVersion = self.groupsVersion(for: allUsers,
                                               transaction: transaction)
        }

        var groupSecretParamsData: Data?
        if groupsVersion == .V2 {
            if let groupSecretParamsDataParam = groupSecretParamsDataParam {
                groupSecretParamsData = groupSecretParamsDataParam
            } else {
                groupSecretParamsData = newGroupSeed.groupSecretParamsData
            }
        }

        let groupId: Data
        if let groupIdParam = groupIdParam {
            groupId = groupIdParam
        } else {
            switch groupsVersion {
            case .V1:
                groupId = newGroupSeed.groupIdV1
            case .V2:
                guard let groupIdV2 = newGroupSeed.groupIdV2 else {
                    throw OWSAssertionError("Missing groupIdV2.")
                }
                groupId = groupIdV2
            }
        }
        guard isValidGroupId(groupId, groupsVersion: groupsVersion) else {
            throw OWSAssertionError("Invalid groupId.")
        }

        let allMembers = groupMembership.allMembers
        let administrators = groupMembership.administrators
        var groupsV2MemberRoles = [UUID: NSNumber]()
        for member in allMembers {
            guard let uuid = member.uuid else {
                continue
            }
            let isAdmin = administrators.contains(member)
            let role: TSGroupMemberRole = isAdmin ? .administrator : .normal
            groupsV2MemberRoles[uuid] = NSNumber(value: role.rawValue)
        }

        let allPendingMembers = groupMembership.allPendingMembers
        let pendingAdministrators = groupMembership.pendingAdministrators
        var groupsV2PendingMemberRoles = [UUID: NSNumber]()
        for pendingMember in allPendingMembers {
            guard let uuid = pendingMember.uuid else {
                continue
            }
            let isAdmin = pendingAdministrators.contains(pendingMember)
            let role: TSGroupMemberRole = isAdmin ? .administrator : .normal
            groupsV2PendingMemberRoles[uuid] = NSNumber(value: role.rawValue)
        }

        return TSGroupModel(groupId: groupId,
                            name: name,
                            avatarData: avatarData,
                            members: GroupMembership.normalize(Array(allMembers)),
                            groupsV2MemberRoles: groupsV2MemberRoles,
                            groupsV2PendingMemberRoles: groupsV2PendingMemberRoles,
                            groupAccess: groupAccess,
                            groupsVersion: groupsVersion,
                            groupV2Revision: groupV2Revision,
                            groupSecretParamsData: groupSecretParamsData)
    }

    // Convert a group state proto received from the service
    // into a group model.
    public static func buildGroupModel(groupV2State: GroupV2State,
                                       transaction: SDSAnyReadTransaction) throws -> TSGroupModel {
        let groupSecretParamsData = groupV2State.groupSecretParamsData
        let groupId = try groupsV2.groupId(forGroupSecretParamsData: groupSecretParamsData)
        let name: String = groupV2State.title
        let groupMembership = groupV2State.groupMembership
        let groupAccess = groupV2State.groupAccess
        // GroupsV2 TODO: Avatar.
        let avatarData: Data? = nil
        let groupsVersion = GroupsVersion.V2
        let revision = groupV2State.revision

        return try buildGroupModel(groupId: groupId,
                                   name: name,
                                   avatarData: avatarData,
                                   groupMembership: groupMembership,
                                   groupAccess: groupAccess,
                                   groupsVersion: groupsVersion,
                                   groupV2Revision: revision,
                                   groupSecretParamsData: groupSecretParamsData,
                                   transaction: transaction)
    }

    // This should only be used for certain legacy edge cases.
    @objc
    public static func fakeGroupModel(groupId: Data?,
                                      transaction: SDSAnyReadTransaction) -> TSGroupModel? {
        do {
            let groupMembership = GroupMembership.empty
            let groupAccess = GroupAccess.allAccess
            return try buildGroupModel(groupId: groupId,
                                       name: nil,
                                       avatarData: nil,
                                       groupMembership: groupMembership,
                                       groupAccess: groupAccess,
                                       groupsVersion: .V1,
                                       groupV2Revision: 0,
                                       groupSecretParamsData: nil,
                                       transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    private static func groupsVersion(for members: Set<SignalServiceAddress>,
                                      transaction: SDSAnyReadTransaction) -> GroupsVersion {

        guard FeatureFlags.tryToCreateNewGroupsV2 else {
            return .V1
        }
        let canUseV2 = self.canUseV2(for: members, transaction: transaction)
        return canUseV2 ? defaultGroupsVersion : .V1
    }

    private static func canUseV2(for members: Set<SignalServiceAddress>,
                                 transaction: SDSAnyReadTransaction) -> Bool {

        for recipientAddress in members {
            guard let uuid = recipientAddress.uuid else {
                Logger.warn("Creating legacy group; member without UUID.")
                return false
            }
            let address = SignalServiceAddress(uuid: uuid)
            let hasCredential = self.groupsV2.hasProfileKeyCredential(for: address,
                                                                      transaction: transaction)
            guard hasCredential else {
                Logger.warn("Creating legacy group; member missing credential.")
                return false
            }
            // GroupsV2 TODO: Check capability.
        }
        return true
    }

    @objc
    public static var defaultGroupsVersion: GroupsVersion {
        guard FeatureFlags.tryToCreateNewGroupsV2 else {
            return .V1
        }
        return .V2
    }

    // MARK: - Create New Group
    //
    // "New" groups are being created for the first time; they might need to be created on the service.

    public static func createNewGroup(members: [SignalServiceAddress],
                                      groupId: Data? = nil,
                                      name: String? = nil,
                                      avatarImage: UIImage?,
                                      newGroupSeed: NewGroupSeed? = nil,
                                      shouldSendMessage: Bool) -> Promise<TSGroupThread> {

        return DispatchQueue.global().async(.promise) {
            return TSGroupModel.data(forGroupAvatar: avatarImage)
        }.then(on: .global()) { avatarData in
            return createNewGroup(members: members,
                                  groupId: groupId,
                                  name: name,
                                  avatarData: avatarData,
                                  newGroupSeed: newGroupSeed,
                                  shouldSendMessage: shouldSendMessage)
        }
    }

    public static func createNewGroup(members membersParam: [SignalServiceAddress],
                                      groupId: Data? = nil,
                                      name: String? = nil,
                                      avatarData: Data? = nil,
                                      newGroupSeed: NewGroupSeed? = nil,
                                      shouldSendMessage: Bool) -> Promise<TSGroupThread> {

        guard let localAddress = self.tsAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Missing localAddress."))
        }
        guard let groupsV2Swift = self.groupsV2 as? GroupsV2Swift else {
            return Promise(error: OWSAssertionError("Invalid groupsV2 instance."))
        }

        return DispatchQueue.global().async(.promise) { () -> GroupMembership in
            guard let localAddress = self.tsAccountManager.localAddress else {
                throw OWSAssertionError("Missing localAddress.")
            }
            // Build member list.
            //
            // GroupsV2 TODO: Separate out pending members here.
            var nonAdminMembers = Set(membersParam)
            nonAdminMembers.remove(localAddress)
            let administrators = Set([localAddress])
            let pendingNonAdminMembers = Set<SignalServiceAddress>()
            let pendingAdministrators = Set<SignalServiceAddress>()
            return GroupMembership(nonAdminMembers: nonAdminMembers,
                                   administrators: administrators,
                                   pendingNonAdminMembers: pendingNonAdminMembers,
                                   pendingAdministrators: pendingAdministrators)
        }.then(on: .global()) { (groupMembership: GroupMembership) -> Promise<GroupMembership> in
            // We will need a profile key credential for all users including
            // ourself.  If we've never done a versioned profile update,
            // try to do so now.
            guard FeatureFlags.tryToCreateNewGroupsV2 else {
                return Promise.value(groupMembership)
            }
            let hasLocalCredential = self.databaseStorage.read { transaction in
                return self.groupsV2.hasProfileKeyCredential(for: localAddress,
                                                             transaction: transaction)
            }
            guard !hasLocalCredential else {
                return Promise.value(groupMembership)
            }
            return groupsV2Swift.reuploadLocalProfilePromise()
                .map(on: .global()) { (_) -> GroupMembership in
                    return groupMembership
            }
        }.then(on: .global()) { (groupMembership: GroupMembership) -> Promise<GroupMembership> in
            // Try to obtain profile key credentials for all group members
            // including ourself, unless we already have them on hand.
            guard FeatureFlags.tryToCreateNewGroupsV2 else {
                return Promise.value(groupMembership)
            }
            return groupsV2Swift.tryToEnsureProfileKeyCredentials(for: Array(groupMembership.allUsers))
                .map(on: .global()) { (_) -> GroupMembership in
                    return groupMembership
            }
        }.then(on: .global()) { (groupMembership: GroupMembership) throws -> Promise<TSGroupModel> in
            // GroupsV2 TODO: Let users specify access levels in the "new group" view.
            let groupAccess = GroupAccess.allAccess
            let groupModel = try self.databaseStorage.read { transaction in
                return try self.buildGroupModel(groupId: groupId,
                                                name: name,
                                                avatarData: avatarData,
                                                groupMembership: groupMembership,
                                                groupAccess: groupAccess,
                                                groupV2Revision: 0,
                                                newGroupSeed: newGroupSeed,
                                                transaction: transaction)
            }
            return self.createNewGroupOnServiceIfNecessary(groupModel: groupModel)
        }.then(on: .global()) { (groupModel: TSGroupModel) -> Promise<TSGroupThread> in
            let thread = databaseStorage.write { (transaction: SDSAnyWriteTransaction) -> TSGroupThread in
                return self.insertGroupThreadInDatabaseAndCreateInfoMessage(groupModel: groupModel,
                                                                            groupUpdateSourceAddress: localAddress,
                                                                            transaction: transaction)
            }

            self.profileManager.addThread(toProfileWhitelist: thread)

            if shouldSendMessage {
                return sendDurableNewGroupMessage(forThread: thread)
                    .map(on: .global()) { _ in
                        return thread
                }
            } else {
                return Promise.value(thread)
            }
        }
    }

    private static func createNewGroupOnServiceIfNecessary(groupModel: TSGroupModel) -> Promise<TSGroupModel> {
        guard groupModel.groupsVersion == .V2 else {
            return Promise.value(groupModel)
        }
        guard let groupsV2Swift = self.groupsV2 as? GroupsV2Swift else {
            return Promise(error: OWSAssertionError("Invalid groupsV2 instance."))
        }
        return groupsV2Swift.createNewGroupOnService(groupModel: groupModel)
            .map(on: .global()) { _ in
                return groupModel
        }
    }

    // success and failure are invoked on the main thread.
    @objc
    public static func createNewGroupObjc(members: [SignalServiceAddress],
                                          groupId: Data?,
                                          name: String,
                                          avatarImage: UIImage?,
                                          newGroupSeed: NewGroupSeed?,
                                          shouldSendMessage: Bool,
                                          success: @escaping (TSGroupThread) -> Void,
                                          failure: @escaping (Error) -> Void) {
        createNewGroup(members: members,
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
    public static func createNewGroupObjc(members: [SignalServiceAddress],
                                          groupId: Data?,
                                          name: String,
                                          avatarData: Data?,
                                          newGroupSeed: NewGroupSeed?,
                                          shouldSendMessage: Bool,
                                          success: @escaping (TSGroupThread) -> Void,
                                          failure: @escaping (Error) -> Void) {
        createNewGroup(members: members,
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

        // GroupsV2 TODO: Elaborate tests to include admins, pending members, etc.
        let groupMembership = GroupMembership(nonAdminMembers: Set(members), administrators: Set(), pendingNonAdminMembers: Set(), pendingAdministrators: Set())
        // GroupsV2 TODO: Let tests specify access levels.
        let groupAccess = GroupAccess.allAccess
        // Use buildGroupModel() to fill in defaults, like it was a new group.
        let groupModel = try buildGroupModel(groupId: groupId,
                                             name: name,
                                             avatarData: avatarData,
                                             groupMembership: groupMembership,
                                             groupAccess: groupAccess,
                                             groupsVersion: groupsVersion,
                                             groupV2Revision: 0,
                                             transaction: transaction)

        // Just create it in the database, don't create it on the service.
        //
        // GroupsV2 TODO: Update method to handle admins, pending members, etc.
        return try upsertExistingGroup(groupModel: groupModel,
                                       groupUpdateSourceAddress: tsAccountManager.localAddress!,
                                       transaction: transaction).thread
    }

    #endif

    // MARK: - Upsert Existing Group
    //
    // "Existing" groups have already been created, we just need to make sure they're in the database.

    @objc(upsertExistingGroupV1WithGroupId:name:avatarData:members:groupUpdateSourceAddress:transaction:error:)
    public static func upsertExistingGroupV1(groupId: Data,
                                             name: String? = nil,
                                             avatarData: Data? = nil,
                                             members: [SignalServiceAddress],
                                             groupUpdateSourceAddress: SignalServiceAddress?,
                                             transaction: SDSAnyWriteTransaction) throws -> EnsureGroupResult {

        let groupMembership = GroupMembership(v1Members: Set(members))
        let groupAccess = GroupAccess.forV1
        return try upsertExistingGroup(groupId: groupId,
                                       name: name,
                                       avatarData: avatarData,
                                       groupMembership: groupMembership,
                                       groupAccess: groupAccess,
                                       groupsVersion: .V1,
                                       groupV2Revision: 0,
                                       groupSecretParamsData: nil,
                                       groupUpdateSourceAddress: groupUpdateSourceAddress,
                                       transaction: transaction)
    }

    public static func upsertExistingGroup(groupId: Data,
                                           name: String? = nil,
                                           avatarData: Data? = nil,
                                           groupMembership: GroupMembership,
                                           groupAccess: GroupAccess,
                                           groupsVersion: GroupsVersion,
                                           groupV2Revision: UInt32,
                                           groupSecretParamsData: Data? = nil,
                                           groupUpdateSourceAddress: SignalServiceAddress?,
                                           transaction: SDSAnyWriteTransaction) throws -> EnsureGroupResult {

        let groupModel = try buildGroupModel(groupId: groupId,
                                             name: name,
                                             avatarData: avatarData,
                                             groupMembership: groupMembership,
                                             groupAccess: groupAccess,
                                             groupsVersion: groupsVersion,
                                             groupV2Revision: groupV2Revision,
                                             groupSecretParamsData: groupSecretParamsData,
                                             transaction: transaction)

        return try upsertExistingGroup(groupModel: groupModel,
                                       groupUpdateSourceAddress: groupUpdateSourceAddress,
                                       transaction: transaction)
    }

    public static func upsertExistingGroup(groupModel: TSGroupModel,
                                           groupUpdateSourceAddress: SignalServiceAddress?,
                                           transaction: SDSAnyWriteTransaction) throws -> EnsureGroupResult {

        let groupId = groupModel.groupId
        let groupAccess: GroupAccess
        if let modelAccess = groupModel.groupAccess {
            groupAccess = modelAccess
        } else {
            switch groupModel.groupsVersion {
            case .V1:
                groupAccess = GroupAccess.allAccess
            case .V2:
                throw OWSAssertionError("Missing groupAccess.")
            }
        }

        // GroupsV2 TODO: Audit all callers too see if they should include local uuid.

        guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            // GroupsV2 TODO: Can we use upsertGroupThread(...) here and above?
            let thread = self.insertGroupThreadInDatabaseAndCreateInfoMessage(groupModel: groupModel,
                                                                              groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                              transaction: transaction)
            return EnsureGroupResult(action: .inserted, thread: thread)
        }

        guard !groupModel.isEqual(to: thread.groupModel) else {
            // GroupsV2 TODO: We might want to throw GroupsV2Error.redundantChange
            return EnsureGroupResult(action: .unchanged, thread: thread)
        }

        let updateInfo = try self.updateInfo(groupId: groupId,
                                             name: groupModel.groupName,
                                             avatarData: groupModel.groupAvatarData,
                                             groupMembership: groupModel.groupMembership,
                                             groupAccess: groupAccess,
                                             transaction: transaction)
        let updatedThread = self.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(groupThread: thread,
                                                                                         newGroupModel: updateInfo.newGroupModel,
                                                                                         groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                         transaction: transaction)
        return EnsureGroupResult(action: .updated, thread: updatedThread)
    }

    // MARK: - Update Existing Group

    private struct UpdateInfo {
        let groupId: Data
        let oldGroupModel: TSGroupModel
        let newGroupModel: TSGroupModel
        let changeSet: GroupsV2ChangeSet?
    }

    public static func updateExistingGroup(groupId: Data,
                                           name: String? = nil,
                                           avatarData: Data? = nil,
                                           groupMembership: GroupMembership,
                                           groupAccess: GroupAccess,
                                           groupsVersion: GroupsVersion,
                                           groupUpdateSourceAddress: SignalServiceAddress?) -> Promise<TSGroupThread> {

        let shouldSendMessage = true

        switch groupsVersion {
        case .V1:
            return updateExistingGroupV1(groupId: groupId,
                                         name: name,
                                         avatarData: avatarData,
                                         groupMembership: groupMembership,
                                         groupAccess: groupAccess,
                                         shouldSendMessage: shouldSendMessage,
                                         groupUpdateSourceAddress: groupUpdateSourceAddress)
        case .V2:
            return updateExistingGroupV2(groupId: groupId,
                                         name: name,
                                         avatarData: avatarData,
                                         groupMembership: groupMembership,
                                         groupAccess: groupAccess,
                                         shouldSendMessage: shouldSendMessage,
                                         groupUpdateSourceAddress: groupUpdateSourceAddress)

        }
    }

    private static func updateExistingGroupV1(groupId: Data,
                                              name: String? = nil,
                                              avatarData: Data? = nil,
                                              groupMembership: GroupMembership,
                                              groupAccess: GroupAccess,
                                              shouldSendMessage: Bool,
                                              groupUpdateSourceAddress: SignalServiceAddress?) -> Promise<TSGroupThread> {

        return self.databaseStorage.write(.promise) { (transaction) throws -> (UpdateInfo, TSGroupThread) in
            let updateInfo = try self.updateInfo(groupId: groupId,
                                                 name: name,
                                                 avatarData: avatarData,
                                                 groupMembership: groupMembership,
                                                 groupAccess: groupAccess,
                                                 transaction: transaction)
            guard updateInfo.changeSet == nil else {
                throw OWSAssertionError("Unexpected changeSet.")
            }
            let newGroupModel = updateInfo.newGroupModel
            let groupThread = try self.tryToUpdateExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                                    groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                                    transaction: transaction)
            return (updateInfo, groupThread)
        }.then(on: .global()) { (updateInfo: UpdateInfo, groupThread: TSGroupThread) throws -> Promise<TSGroupThread> in
            guard shouldSendMessage else {
                return Promise.value(groupThread)
            }

            return self.sendGroupUpdateMessage(thread: groupThread,
                                               oldGroupModel: updateInfo.oldGroupModel,
                                               newGroupModel: updateInfo.newGroupModel)
                .map(on: .global()) { _ in
                    return groupThread
            }
        }
    }

    private static func updateExistingGroupV2(groupId: Data,
                                              name: String? = nil,
                                              avatarData: Data? = nil,
                                              groupMembership: GroupMembership,
                                              groupAccess: GroupAccess,
                                              shouldSendMessage: Bool,
                                              groupUpdateSourceAddress: SignalServiceAddress?) -> Promise<TSGroupThread> {

        guard let groupsV2Swift = self.groupsV2 as? GroupsV2Swift else {
            return Promise(error: OWSAssertionError("Invalid groupsV2 instance."))
        }

        return DispatchQueue.global().async(.promise) { () throws -> UpdateInfo in
            let updateInfo: UpdateInfo = try databaseStorage.read { transaction in
                return try self.updateInfo(groupId: groupId,
                                           name: name,
                                           avatarData: avatarData,
                                           groupMembership: groupMembership,
                                           groupAccess: groupAccess,
                                           transaction: transaction)
            }
            return updateInfo
        }.then(on: .global()) { (updateInfo: UpdateInfo) throws -> Promise<(UpdateInfo, ChangedGroupModel)> in
            guard let changeSet = updateInfo.changeSet else {
                throw OWSAssertionError("Missing changeSet.")
            }
            return groupsV2Swift.updateExistingGroupOnService(changeSet: changeSet)
                .map(on: .global()) { (changedGroupModel) -> (UpdateInfo, ChangedGroupModel) in
                    return (updateInfo, changedGroupModel)
            }
        }.map(on: .global()) { (updateInfo: UpdateInfo, changedGroupModel: ChangedGroupModel) throws -> ChangedGroupModel in
            let newGroupModel = changedGroupModel.newGroupModel
            guard newGroupModel.groupV2Revision > changedGroupModel.oldGroupModel.groupV2Revision else {
                throw OWSAssertionError("Invalid groupV2Revision: \(newGroupModel.groupV2Revision).")
            }
            guard newGroupModel.groupV2Revision > updateInfo.oldGroupModel.groupV2Revision else {
                throw OWSAssertionError("Invalid groupV2Revision: \(newGroupModel.groupV2Revision).")
            }
            guard newGroupModel.groupV2Revision >= updateInfo.newGroupModel.groupV2Revision else {
                throw OWSAssertionError("Invalid groupV2Revision: \(newGroupModel.groupV2Revision).")
            }
            // GroupsV2 TODO: v2 groups must be modified in step-wise fashion,
            //                creating local messages for each revision.
            return changedGroupModel
        }.then(on: .global()) { (changedGroupModel: ChangedGroupModel) throws -> Promise<TSGroupThread> in
            let groupThread = changedGroupModel.groupThread

            // We need to plumb through the _actual_ "old" and "new" group models
            // to sendGroupUpdateMessage(), e.g. the copies from ChangedGroupModel
            // which reflect the actual update rather than from UpdateInfo()
            // which reflect the proposed update.
            guard shouldSendMessage else {
                return Promise.value(groupThread)
            }

            return self.sendGroupUpdateMessage(thread: groupThread,
                                               oldGroupModel: changedGroupModel.oldGroupModel,
                                               newGroupModel: changedGroupModel.newGroupModel,
                                               changeActionsProtoData: changedGroupModel.changeActionsProtoData)
                .map(on: .global()) { _ in
                    return groupThread
            }
        }
        // GroupsV2 TODO: Handle redundant change error.
    }

    private static func updateInfo(groupId: Data,
                                   name: String? = nil,
                                   avatarData: Data? = nil,
                                   groupMembership groupMembershipParam: GroupMembership,
                                   groupAccess: GroupAccess,
                                   transaction: SDSAnyReadTransaction) throws -> UpdateInfo {
        guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            throw OWSAssertionError("Thread does not exist.")
        }
        let oldGroupModel = thread.groupModel
        guard let localAddress = self.tsAccountManager.localAddress else {
            throw OWSAssertionError("Missing localAddress.")
        }
        guard let groupsV2Swift = self.groupsV2 as? GroupsV2Swift else {
            throw OWSAssertionError("Invalid groupsV2 instance.")
        }

        let groupMembership: GroupMembership
        if oldGroupModel.groupsVersion == .V1 {
            // Always ensure we're a member of any v1 group we're updating.
            groupMembership = groupMembershipParam.withNonAdminMember(address: localAddress)
        } else {
            groupMembership = groupMembershipParam

            // Don't try to modify a v2 group if we're not a member.
            guard groupMembership.allMembers.contains(localAddress) else {
                throw OWSAssertionError("Missing localAddress.")
            }
        }

        // GroupsV2 TODO: Eventually we won't need to increment the revision here,
        //                since we'll probably be updating the TSGroupThread's
        //                group models with one derived from the service.
        let newRevision = oldGroupModel.groupV2Revision + 1
        let newGroupModel = try buildGroupModel(groupId: oldGroupModel.groupId,
                                                name: name,
                                                avatarData: avatarData,
                                                groupMembership: groupMembership,
                                                groupAccess: groupAccess,
                                                groupsVersion: oldGroupModel.groupsVersion,
                                                groupV2Revision: newRevision,
                                                groupSecretParamsData: oldGroupModel.groupSecretParamsData,
                                                transaction: transaction)
        if oldGroupModel.isEqual(to: newGroupModel) {
            // Skip redundant update.
            throw GroupsV2Error.redundantChange
        }

        // GroupsV2 TODO: Convert this method and callers to return a promise.
        //                We need to audit usage of upsertExistingGroup();
        //                It's possible that it should only be used for v1 groups?
        switch oldGroupModel.groupsVersion {
        case .V1:
            return UpdateInfo(groupId: groupId, oldGroupModel: oldGroupModel, newGroupModel: newGroupModel, changeSet: nil)
        case .V2:
            let changeSet = try groupsV2Swift.buildChangeSet(from: oldGroupModel,
                                                             to: newGroupModel,
                                                             transaction: transaction)
            return UpdateInfo(groupId: groupId, oldGroupModel: oldGroupModel, newGroupModel: newGroupModel, changeSet: changeSet)
        }
    }

    // MARK: - Messages

    @objc
    public static func sendGroupUpdateMessageObjc(thread: TSGroupThread,
                                                  oldGroupModel: TSGroupModel,
                                                  newGroupModel: TSGroupModel) -> AnyPromise {
        return AnyPromise(self.sendGroupUpdateMessage(thread: thread,
                                                      oldGroupModel: oldGroupModel,
                                                      newGroupModel: newGroupModel))
    }

    public static func sendGroupUpdateMessage(thread: TSGroupThread,
                                              oldGroupModel: TSGroupModel,
                                              newGroupModel: TSGroupModel,
                                              changeActionsProtoData: Data? = nil) -> Promise<Void> {

        return databaseStorage.read(.promise) { transaction in
            // GroupsV2 TODO: This behavior will change for v2 groups.
            let expiresInSeconds = thread.disappearingMessagesDuration(with: transaction)
            let message = TSOutgoingMessage(in: thread,
                                            groupMetaMessage: .update,
                                            expiresInSeconds: expiresInSeconds)
            return message
        }.then(on: .global()) { (message: TSOutgoingMessage) throws -> Promise<Void> in
            if let avatarData = newGroupModel.groupAvatarData,
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
            return firstly {
                self.messageSender.sendMessage(.promise, message.asPreparer)
            }.done(on: .global()) { _ in
                Logger.debug("Successfully sent group update")
            }.recover(on: .global()) { error in
                owsFailDebug("Failed to send group update with error: \(error)")
                throw error
            }
        }
    }

    private static func sendDurableNewGroupMessage(forThread thread: TSGroupThread) -> Promise<Void> {
        assert(thread.groupModel.groupAvatarData == nil)

        return databaseStorage.write(.promise) { transaction in
            let message = TSOutgoingMessage.init(in: thread, groupMetaMessage: .new, expiresInSeconds: 0)
            self.messageSenderJobQueue.add(message: message.asPreparer,
                                           transaction: transaction)
        }
    }

    // MARK: -

    private static func insertGroupThreadInDatabaseAndCreateInfoMessage(groupModel: TSGroupModel,
                                                                        groupUpdateSourceAddress: SignalServiceAddress?,
                                                                        transaction: SDSAnyWriteTransaction) -> TSGroupThread {
        let groupThread = TSGroupThread(groupModelPrivate: groupModel)
        groupThread.anyInsert(transaction: transaction)
        insertGroupUpdateInfoMessage(groupThread: groupThread,
                                     oldGroupModel: nil,
                                     newGroupModel: groupModel,
                                     groupUpdateSourceAddress: groupUpdateSourceAddress,
                                     transaction: transaction)
        return groupThread
    }

    public static func updateExistingGroupThreadInDatabaseAndCreateInfoMessage(groupThread: TSGroupThread,
                                                                               newGroupModel: TSGroupModel,
                                                                               groupUpdateSourceAddress: SignalServiceAddress?,
                                                                               transaction: SDSAnyWriteTransaction) -> TSGroupThread {

        let oldGroupModel = groupThread.groupModel
        groupThread.update(with: newGroupModel, transaction: transaction)

        guard !oldGroupModel.isEqual(to: newGroupModel) else {
            // Skip redundant update.
            return groupThread
        }

        insertGroupUpdateInfoMessage(groupThread: groupThread,
                                     oldGroupModel: oldGroupModel,
                                     newGroupModel: newGroupModel,
                                     groupUpdateSourceAddress: groupUpdateSourceAddress,
                                     transaction: transaction)

        return groupThread
    }

    public static func tryToUpdateExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: TSGroupModel,
                                                                                    groupUpdateSourceAddress: SignalServiceAddress?,
                                                                                    transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {
        let groupId = newGroupModel.groupId
        let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction)
        guard let groupThread = thread else {
            throw OWSAssertionError("Missing groupThread.")
        }
        return self.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(groupThread: groupThread,
                                                                            newGroupModel: newGroupModel,
                                                                            groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                            transaction: transaction)
    }

    private static func insertGroupUpdateInfoMessage(groupThread: TSGroupThread,
                                                     oldGroupModel: TSGroupModel?,
                                                     newGroupModel: TSGroupModel,
                                                     groupUpdateSourceAddress: SignalServiceAddress?,
                                                     transaction: SDSAnyWriteTransaction) {

        var userInfo: [InfoMessageUserInfoKey: Any] = [
            .newGroupModel: newGroupModel
        ]
        if let oldGroupModel = oldGroupModel {
            userInfo[.oldGroupModel] = oldGroupModel
        }
        if let groupUpdateSourceAddress = groupUpdateSourceAddress {
            userInfo[.groupUpdateSourceAddress] = groupUpdateSourceAddress
        }
        let infoMessage = TSInfoMessage(thread: groupThread,
                                        messageType: .typeGroupUpdate,
                                        infoMessageUserInfo: userInfo)
        infoMessage.anyInsert(transaction: transaction)
    }
}
