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

    private class var groupsV2Swift: GroupsV2Swift {
        return self.groupsV2 as! GroupsV2Swift
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
    public static func buildGroupModel(groupV2Snapshot: GroupV2Snapshot,
                                       transaction: SDSAnyReadTransaction) throws -> TSGroupModel {
        let groupSecretParamsData = groupV2Snapshot.groupSecretParamsData
        let groupId = try groupsV2.groupId(forGroupSecretParamsData: groupSecretParamsData)
        let name: String = groupV2Snapshot.title
        let groupMembership = groupV2Snapshot.groupMembership
        let groupAccess = groupV2Snapshot.groupAccess
        // GroupsV2 TODO: Avatar.
        let avatarData: Data? = nil
        let groupsVersion = GroupsVersion.V2
        let revision = groupV2Snapshot.revision

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

        guard FeatureFlags.groupsV2CreateGroups else {
            return .V1
        }
        let canUseV2 = self.canUseV2(for: members, transaction: transaction)
        return canUseV2 ? defaultGroupsVersion : .V1
    }

    private static func canUseV2(for members: Set<SignalServiceAddress>,
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

    private static func doesUserSupportGroupsV2(address: SignalServiceAddress,
                                                transaction: SDSAnyReadTransaction) -> Bool {

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
        guard FeatureFlags.groupsV2CreateGroups else {
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
            guard FeatureFlags.groupsV2CreateGroups else {
                return Promise.value(groupMembership)
            }
            let hasLocalCredential = self.databaseStorage.read { transaction in
                return self.groupsV2.hasProfileKeyCredential(for: localAddress,
                                                             transaction: transaction)
            }
            guard !hasLocalCredential else {
                return Promise.value(groupMembership)
            }
            return firstly {
                self.groupsV2Swift.reuploadLocalProfilePromise()
            }.map(on: .global()) { (_) -> GroupMembership in
                    return groupMembership
            }
        }.then(on: .global()) { (groupMembership: GroupMembership) -> Promise<GroupMembership> in
            // Try to obtain profile key credentials for all group members
            // including ourself, unless we already have them on hand.
            guard FeatureFlags.groupsV2CreateGroups else {
                return Promise.value(groupMembership)
            }
            return firstly {
                self.groupsV2Swift.tryToEnsureProfileKeyCredentials(for: Array(groupMembership.allUsers))
            }.map(on: .global()) { (_) -> GroupMembership in
                    return groupMembership
            }
        }.then(on: .global()) { (proposedGroupMembership: GroupMembership) throws -> Promise<TSGroupModel> in
            // GroupsV2 TODO: Let users specify access levels in the "new group" view.
            let groupAccess = GroupAccess.allAccess
            let groupModel = try self.databaseStorage.read { (transaction) throws -> TSGroupModel in
                // Before we create a v2 group, we need to separate out the
                // pending and non-pending members.  If we already know we're
                // going to create a v1 group, we shouldn't separate them.
                let groupMembership = self.separatePendingMembers(in: proposedGroupMembership,
                                                                  oldGroupModel: nil,
                                                                  transaction: transaction)

                guard groupMembership.allMembers.contains(localAddress) else {
                    throw OWSAssertionError("Missing localAddress.")
                }

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

    // Separates pending and non-pending members.
    // We cannot add non-pending members unless:
    //
    // * We know their UUID.
    // * We know their profile key.
    // * We have a profile key credential for them.
    // * Their account has the "groups v2" capability
    //   (e.g. all of their clients support groups v2.
    private static func separatePendingMembers(in groupMembership: GroupMembership,
                                               oldGroupModel: TSGroupModel?,
                                               transaction: SDSAnyReadTransaction) -> GroupMembership {
        let isNewGroup: Bool
        if let oldGroupModel = oldGroupModel {
            assert(oldGroupModel.groupsVersion == .V2)
            isNewGroup = false
        } else {
            isNewGroup = true
        }

        var builder = GroupMembership.Builder()
        for address in groupMembership.allUsers {
            if isNewGroup {
                guard doesUserSupportGroupsV2(address: address, transaction: transaction) else {
                    // If any member of a new group doesn't support groups v2,
                    // we're going to create a v1 group.  In that case, we
                    // don't want to separate out pending members.
                    return groupMembership
                }
            }

            // We must call this _after_ we try to fetch profile key credentials for
            // all members.
            let isPending: Bool
            if let oldGroupModel = oldGroupModel,
                oldGroupModel.groupMembership.isNonPendingMember(address) {
                // If the member already is a full member, don't treat them
                // as pending.  Perhaps someone else added them.
                isPending = false
            } else {
                isPending = !groupsV2.hasProfileKeyCredential(for: address,
                                                              transaction: transaction)
            }
            let isAdministrator = groupMembership.isAdministrator(address)
            builder.add(address, isAdministrator: isAdministrator, isPending: isPending)
        }
        return builder.build()
    }

    private static func createNewGroupOnServiceIfNecessary(groupModel: TSGroupModel) -> Promise<TSGroupModel> {
        guard groupModel.groupsVersion == .V2 else {
            return Promise.value(groupModel)
        }
        return firstly {
            self.groupsV2Swift.createNewGroupOnService(groupModel: groupModel)
        }.map(on: .global()) { _ in
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
                                       transaction: transaction).groupThread
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
                                             transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {

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
                                           transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {

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
                                           transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {

        return try self.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: groupModel,
                                                                                     groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                     canInsert: true,
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
    public static func updateExistingGroup(groupId: Data,
                                           name: String? = nil,
                                           avatarData: Data? = nil,
                                           groupMembership: GroupMembership,
                                           groupAccess: GroupAccess,
                                           groupsVersion: GroupsVersion,
                                           dmConfiguration: OWSDisappearingMessagesConfiguration?,
                                           groupUpdateSourceAddress: SignalServiceAddress?) -> Promise<TSGroupThread> {

        switch groupsVersion {
        case .V1:
            return updateExistingGroupV1(groupId: groupId,
                                         name: name,
                                         avatarData: avatarData,
                                         groupMembership: groupMembership,
                                         groupAccess: groupAccess,
                                         dmConfiguration: dmConfiguration,
                                         groupUpdateSourceAddress: groupUpdateSourceAddress)
        case .V2:
            return updateExistingGroupV2(groupId: groupId,
                                         name: name,
                                         avatarData: avatarData,
                                         groupMembership: groupMembership,
                                         groupAccess: groupAccess,
                                         dmConfiguration: dmConfiguration,
                                         groupUpdateSourceAddress: groupUpdateSourceAddress)

        }
    }

    // If dmConfiguration is nil, don't change the disappearing messages configuration.
    private static func updateExistingGroupV1(groupId: Data,
                                              name: String? = nil,
                                              avatarData: Data? = nil,
                                              groupMembership: GroupMembership,
                                              groupAccess: GroupAccess,
                                              dmConfiguration: OWSDisappearingMessagesConfiguration?,
                                              groupUpdateSourceAddress: SignalServiceAddress?) -> Promise<TSGroupThread> {

        return self.databaseStorage.write(.promise) { (transaction) throws -> UpsertGroupResult in
            let updateInfo = try self.updateInfo(groupId: groupId,
                                                 name: name,
                                                 avatarData: avatarData,
                                                 groupMembership: groupMembership,
                                                 groupAccess: groupAccess,
                                                 newDMConfiguration: dmConfiguration,
                                                 transaction: transaction)
            let newGroupModel = updateInfo.newGroupModel
            let upsertGroupResult = try self.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                                          groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                                          canInsert: false,
                                                                                                          transaction: transaction)

            if let dmConfiguration = dmConfiguration {
                let groupThread = upsertGroupResult.groupThread
                self.updateDisappearingMessagesInDatabaseAndCreateMessages(token: dmConfiguration.asToken,
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
    private static func updateExistingGroupV2(groupId: Data,
                                              name: String? = nil,
                                              avatarData: Data? = nil,
                                              groupMembership: GroupMembership,
                                              groupAccess: GroupAccess,
                                              dmConfiguration: OWSDisappearingMessagesConfiguration?,
                                              groupUpdateSourceAddress: SignalServiceAddress?) -> Promise<TSGroupThread> {

        return DispatchQueue.global().async(.promise) { () throws -> (UpdateInfo, GroupsV2ChangeSet) in
            return try databaseStorage.read { transaction in
                let updateInfo = try self.updateInfo(groupId: groupId,
                                                     name: name,
                                                     avatarData: avatarData,
                                                     groupMembership: groupMembership,
                                                     groupAccess: groupAccess,
                                                     newDMConfiguration: dmConfiguration,
                                                     transaction: transaction)
                let changeSet = try groupsV2Swift.buildChangeSet(oldGroupModel: updateInfo.oldGroupModel,
                                                                 newGroupModel: updateInfo.newGroupModel,
                                                                 oldDMConfiguration: updateInfo.oldDMConfiguration,
                                                                 newDMConfiguration: updateInfo.newDMConfiguration,
                                                                 transaction: transaction)
                return (updateInfo, changeSet)
            }
        }.then(on: .global()) { (_: UpdateInfo, changeSet: GroupsV2ChangeSet) throws -> Promise<TSGroupThread> in
            return groupsV2Swift.updateExistingGroupOnService(changeSet: changeSet)
        }
        // GroupsV2 TODO: Handle redundant change error.
    }

    // If dmConfiguration is nil, don't change the disappearing messages configuration.
    private static func updateInfo(groupId: Data,
                                   name: String? = nil,
                                   avatarData: Data? = nil,
                                   groupMembership proposedGroupMembership: GroupMembership,
                                   groupAccess: GroupAccess,
                                   newDMConfiguration dmConfiguration: OWSDisappearingMessagesConfiguration?,
                                   transaction: SDSAnyReadTransaction) throws -> UpdateInfo {
        guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            throw OWSAssertionError("Thread does not exist.")
        }
        let oldGroupModel = thread.groupModel
        guard let localAddress = self.tsAccountManager.localAddress else {
            throw OWSAssertionError("Missing localAddress.")
        }

        let oldDMConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: thread, transaction: transaction)
        let newDMConfiguration = dmConfiguration ?? oldDMConfiguration

        let groupMembership: GroupMembership
        if oldGroupModel.groupsVersion == .V1 {
            // Always ensure we're a member of any v1 group we're updating.
            groupMembership = proposedGroupMembership.withNonAdminMember(address: localAddress)
        } else {
            for address in proposedGroupMembership.allUsers {
                guard address.uuid != nil else {
                    throw OWSAssertionError("Group v2 member missing uuid.")
                }
            }
            // Before we update a v2 group, we need to separate out the
            // pending and non-pending members.
            groupMembership = self.separatePendingMembers(in: proposedGroupMembership,
                                                          oldGroupModel: oldGroupModel,
                                                          transaction: transaction)

            guard groupMembership.allMembers.contains(localAddress) else {
                throw OWSAssertionError("Missing localAddress.")
            }

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
        return UpdateInfo(groupId: groupId,
                          oldGroupModel: oldGroupModel,
                          newGroupModel: newGroupModel,
                          oldDMConfiguration: oldDMConfiguration,
                          newDMConfiguration: newDMConfiguration)
    }

    // MARK: - Disappearing Messages

    public static func updateDisappearingMessages(thread: TSThread,
                                                  disappearingMessageToken: DisappearingMessageToken) -> Promise<Void> {

        let simpleUpdate = {
            return databaseStorage.write(.promise) { transaction in
                self.updateDisappearingMessagesInDatabaseAndCreateMessages(token: disappearingMessageToken,
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

        return groupsV2Swift.updateDisappearingMessageStateOnService(groupThread: groupThread,
            disappearingMessageToken: disappearingMessageToken).asVoid()
    }

    public static func updateDisappearingMessagesInDatabaseAndCreateMessages(token newToken: DisappearingMessageToken,
                                                                             thread: TSThread,
                                                                             transaction: SDSAnyWriteTransaction) {

        let oldConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: thread, transaction: transaction)
        let hasUnsavedChanges = oldConfiguration.asToken != newToken
        guard hasUnsavedChanges else {
            // Skip redundant updates.
            return
        }
        let newConfiguration: OWSDisappearingMessagesConfiguration
        if newToken.isEnabled {
            newConfiguration = oldConfiguration.copyAsEnabled(withDurationSeconds: newToken.durationSeconds)
        } else {
            newConfiguration = oldConfiguration.copy(withIsEnabled: false)
        }
        newConfiguration.anyUpsert(transaction: transaction)

        // GroupsV2 TODO: We could eventually merge this with insertGroupUpdateInfoMessage.
        //                If not, we should populate createdByRemoteName.
        //
        // MJK TODO - should be safe to remove this senderTimestamp
        let infoMessage = OWSDisappearingConfigurationUpdateInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(),
                                                                        thread: thread,
                                                                        configuration: newConfiguration,
                                                                        createdByRemoteName: nil,
                                                                        createdInExistingGroup: false)
        infoMessage.anyInsert(transaction: transaction)

        guard !thread.isGroupV2Thread else {
            // Don't send DM configuration messages for v2 groups.
            return
        }

        let message = OWSDisappearingMessagesConfigurationMessage(configuration: newConfiguration, thread: thread)
        messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
    }

    // MARK: - Accept Invites

    public static func acceptInviteToGroupV2(groupThread: TSGroupThread) -> Promise<TSGroupThread> {

        return groupsV2Swift.acceptInviteToGroupV2(groupThread: groupThread)
    }

    // MARK: - Leave Group / Decline Invite

    @objc
    public static func leaveGroupOrDeclineInviteObjc(groupThread: TSGroupThread) -> AnyPromise {
        return AnyPromise(leaveGroupOrDeclineInvite(groupThread: groupThread))
    }

    public static func leaveGroupOrDeclineInvite(groupThread: TSGroupThread) -> Promise<TSGroupThread> {
        switch groupThread.groupModel.groupsVersion {
        case .V1:
            return leaveGroupV1(groupId: groupThread.groupModel.groupId)
        case .V2:
            return leaveGroupV2OrDeclineInvite(groupThread: groupThread)
        }
    }

    private static func leaveGroupV1(groupId: Data) -> Promise<TSGroupThread> {
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
            if threadMessageCount > 0 {
                let infoMessage = TSInfoMessage(timestamp: message.timestamp,
                                                in: groupThread,
                                                messageType: .typeGroupQuit)
                infoMessage.anyInsert(transaction: transaction)
            }

            var groupMembershipBuilder = oldGroupModel.groupMembership.asBuilder
            groupMembershipBuilder.remove(localAddress)
            let newGroupMembership = groupMembershipBuilder.build()
            let groupAccess = try oldGroupModel.groupAccessOrDefault()
            let newGroupModel = try self.buildGroupModel(groupId: groupId,
                                                         name: oldGroupModel.groupName,
                                                         avatarData: oldGroupModel.groupAvatarData,
                                                         groupMembership: newGroupMembership,
                                                         groupAccess: groupAccess,
                                                         groupsVersion: oldGroupModel.groupsVersion,
                                                         groupV2Revision: oldGroupModel.groupV2Revision,
                                                         groupSecretParamsData: nil,
                                                         newGroupSeed: nil,
                                                         transaction: transaction)
            // GroupsV2 TODO: Do we need to set groupUpdateSourceAddress here?
            let result = try self.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(groupThread: groupThread,
                                                                                          newGroupModel: newGroupModel,
                                                                                          groupUpdateSourceAddress: nil,
                                                                                          transaction: transaction)
            return result.groupThread
        }
    }

    private static func leaveGroupV2OrDeclineInvite(groupThread: TSGroupThread) -> Promise<TSGroupThread> {
        guard let groupsV2Swift = self.groupsV2 as? GroupsV2Swift else {
            return Promise(error: OWSAssertionError("Invalid groupsV2 instance."))
        }

        return groupsV2Swift.leaveGroupV2OrDeclineInvite(groupThread: groupThread)
    }

    // MARK: - Messages

    @objc
    public static func sendGroupUpdateMessageObjc(thread: TSGroupThread) -> AnyPromise {
        return AnyPromise(self.sendGroupUpdateMessage(thread: thread))
    }

    public static func sendGroupUpdateMessage(thread: TSGroupThread,
                                              changeActionsProtoData: Data? = nil) -> Promise<Void> {

        guard !FeatureFlags.groupsV2dontSendUpdates else {
            return Promise.value(())
        }

        return databaseStorage.read(.promise) { transaction in
            let expiresInSeconds = thread.disappearingMessagesDuration(with: transaction)
            let messageBuilder = TSOutgoingMessageBuilder(thread: thread)
            messageBuilder.groupMetaMessage = .update
            messageBuilder.expiresInSeconds = expiresInSeconds
            if FeatureFlags.groupsV2embedProtosInGroupUpdates {
                messageBuilder.changeActionsProtoData = changeActionsProtoData
            }
            self.addAdditionalRecipients(to: messageBuilder,
                                         groupThread: thread,
                                         transaction: transaction)
            return messageBuilder.build()
        }.then(on: .global()) { (message: TSOutgoingMessage) throws -> Promise<Void> in
            let groupModel = thread.groupModel
            if let avatarData = groupModel.groupAvatarData,
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
        assert(thread.groupModel.groupAvatarData == nil)

        guard !FeatureFlags.groupsV2dontSendUpdates else {
            return Promise.value(())
        }

        return databaseStorage.write(.promise) { transaction in
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
        let additionalRecipients = groupThread.groupModel.allPendingMembers.filter { address in
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

    public static func insertGroupThreadInDatabaseAndCreateInfoMessage(groupModel: TSGroupModel,
                                                                       groupUpdateSourceAddress: SignalServiceAddress?,
                                                                       transaction: SDSAnyWriteTransaction) -> TSGroupThread {
        let groupThread = TSGroupThread(groupModelPrivate: groupModel)
        groupThread.anyInsert(transaction: transaction)

        insertGroupUpdateInfoMessage(groupThread: groupThread,
                                     oldGroupModel: nil,
                                     newGroupModel: groupModel,
                                     groupUpdateSourceAddress: groupUpdateSourceAddress,
                                     transaction: transaction)

        // GroupsV2 TODO: This is temporary until we build the "accept invites" UI.
        transaction.addAsyncCompletion {
            self.autoAcceptInviteToGroupV2IfNecessary(groupThread: groupThread)
        }

        return groupThread
    }

    public static func tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: TSGroupModel,
                                                                                    groupUpdateSourceAddress: SignalServiceAddress?,
                                                                                    canInsert: Bool,
                                                                                    transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {

        let groupId = newGroupModel.groupId
        guard let oldThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            guard canInsert else {
                throw OWSAssertionError("Missing groupThread.")
            }
            let thread = GroupManager.insertGroupThreadInDatabaseAndCreateInfoMessage(groupModel: newGroupModel,
                                                                                      groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                      transaction: transaction)
            return UpsertGroupResult(action: .inserted, groupThread: thread)
        }

        return try updateExistingGroupThreadInDatabaseAndCreateInfoMessage(groupThread: oldThread,
                                                                           newGroupModel: newGroupModel,
                                                                           groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                           transaction: transaction)
    }

    public static func updateExistingGroupThreadInDatabaseAndCreateInfoMessage(groupThread: TSGroupThread,
                                                                               newGroupModel: TSGroupModel,
                                                                               groupUpdateSourceAddress: SignalServiceAddress?,
                                                                               transaction: SDSAnyWriteTransaction) throws -> UpsertGroupResult {

        let oldGroupModel = groupThread.groupModel
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

        insertGroupUpdateInfoMessage(groupThread: groupThread,
                                     oldGroupModel: oldGroupModel,
                                     newGroupModel: newGroupModel,
                                     groupUpdateSourceAddress: groupUpdateSourceAddress,
                                     transaction: transaction)

        // GroupsV2 TODO: This is temporary until we build the "accept invites" UI.
        transaction.addAsyncCompletion {
            self.autoAcceptInviteToGroupV2IfNecessary(groupThread: groupThread)
        }

        return UpsertGroupResult(action: .updated, groupThread: groupThread)
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

    // GroupsV2 TODO: This is temporary until we build the "accept invites" UI.
    private static func autoAcceptInviteToGroupV2IfNecessary(groupThread: TSGroupThread) {
        guard FeatureFlags.groupsV2AutoAcceptInvites else {
            return
        }
        guard let localAddress = self.tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return
        }
        let groupMembership = groupThread.groupModel.groupMembership
        let isPendingMember = groupMembership.isPending(localAddress)
        guard isPendingMember else {
            return
        }
        firstly {
            acceptInviteToGroupV2(groupThread: groupThread)
        }.done(on: .global()) { _ in
            Logger.debug("Accept invite succeeded.")
        }.catch(on: .global()) { error in
            owsFailDebug("Accept invite failed: \(error)")
        }.retainUntilComplete()
    }

    // MARK: - Group Database

    @objc
    public static let groupsV2CapabilityStore = SDSKeyValueStore(collection: "GroupManager.groupsV2Capability")

    @objc
    public static func doesUserHaveGroupsV2Capability(address: SignalServiceAddress,
                                                     transaction: SDSAnyReadTransaction) -> Bool {
        if FeatureFlags.groupsV2IgnoreCapability {
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
}
