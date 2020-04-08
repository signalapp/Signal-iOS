//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMetadataKit
import ZKGroup

// GroupsV2 TODO: Convert this extension into tests.
@objc
public class GroupsV2Test: NSObject {

    // MARK: - Dependencies

    private class var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private class var groupsV2: GroupsV2Swift {
        return SSKEnvironment.shared.groupsV2 as! GroupsV2Swift
    }

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    @objc
    public static func testGroupsV2Functionality() {
        guard !FeatureFlags.isUsingProductionService,
            FeatureFlags.groupsV2CreateGroups,
            FeatureFlags.versionedProfiledFetches,
            FeatureFlags.versionedProfiledUpdate else {
                owsFailDebug("Incorrect feature flags.")
                return
        }
        let members = [SignalServiceAddress]()
        let title0 = "hello"
        let title1 = "goodbye"
        let avatar1Image = UIImage(color: .red, size: CGSize(square: 1))
        guard let avatar1Data = avatar1Image.pngData() else {
            owsFailDebug("Invalid avatar1Data.")
            return
        }
        guard let localUuid = tsAccountManager.localUuid else {
            owsFailDebug("Missing localUuid.")
            return
        }
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return
        }
        let stagingNumbers = [
            "+16785621057",
            "+13252214009"
        ]
        let stagingAccounts = stagingNumbers.map { SignalServiceAddress(phoneNumber: $0) }
        guard stagingAccounts.contains(localAddress) else {
            owsFailDebug("Missing localAddress.")
            return
        }
        let otherAddresses = Set(stagingAccounts).subtracting([localAddress])
        let localAddressSet = Set([SignalServiceAddress(uuid: localUuid)])
        Logger.verbose("otherAddresses: \(otherAddresses)")
        firstly {
            GroupManager.localCreateNewGroup(members: members,
                                             name: title0,
                                             shouldSendMessage: true)
        }.then(on: .global()) { (groupThread: TSGroupThread) -> Promise<GroupV2Snapshot> in
            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                throw OWSAssertionError("Invalid group model.")
            }
            return self.groupsV2.fetchCurrentGroupV2Snapshot(groupModel: groupModel)
        }.map(on: .global()) { (groupV2Snapshot: GroupV2Snapshot) throws -> Data in
            let groupModel = try self.databaseStorage.read { transaction in
                return try TSGroupModelBuilder(groupV2Snapshot: groupV2Snapshot).build(transaction: transaction) as! TSGroupModelV2
            }
            let groupId = groupModel.groupId
            guard groupModel.revision == 0 else {
                throw OWSAssertionError("Unexpected groupV2Revision: \(groupModel.revision).")
            }

            guard groupV2Snapshot.revision == 0 else {
                throw OWSAssertionError("Unexpected group version: \(groupV2Snapshot.revision).")
            }
            guard groupV2Snapshot.title == title0 else {
                throw OWSAssertionError("Unexpected group title: \(groupV2Snapshot.title).")
            }
            guard groupV2Snapshot.avatarData == nil else {
                throw OWSAssertionError("Unexpected group avatarData: \(groupV2Snapshot.avatarData?.hexadecimalString).")
            }
            guard groupModel.groupName == title0 else {
                throw OWSAssertionError("Unexpected group title: \(groupModel.groupName).")
            }
            guard groupModel.groupAvatarData == nil else {
                throw OWSAssertionError("Unexpected group avatarData: \(groupModel.groupAvatarData?.hexadecimalString).")
            }

            let groupMembership = groupModel.groupMembership

            // GroupsV2 TODO: Test around administrators and pending members.
            let expectedMembers = localAddressSet
            guard groupMembership.nonPendingMembers == expectedMembers else {
                throw OWSAssertionError("Unexpected members: \(groupMembership.nonPendingMembers).")
            }
            let expectedAdministrators = expectedMembers
            guard groupMembership.nonPendingAdministrators == expectedAdministrators else {
                throw OWSAssertionError("Unexpected administrators: \(groupMembership.nonPendingAdministrators).")
            }
            guard groupV2Snapshot.accessControlForMembers == .member else {
                throw OWSAssertionError("Unexpected accessControlForMembers: \(groupV2Snapshot.accessControlForMembers).")
            }
            guard groupV2Snapshot.accessControlForAttributes == .member else {
                throw OWSAssertionError("Unexpected accessControlForAttributes: \(groupV2Snapshot.accessControlForAttributes).")
            }
            return groupId
        }.then(on: .global()) { (groupId: Data) throws -> Promise<TSGroupThread> in
            let (groupThread, dmConfiguration) = try self.fetchGroupThread(groupId: groupId)
            let oldGroupModel = groupThread.groupModel as! TSGroupModelV2
            guard oldGroupModel.groupMembership.nonPendingAdministrators == localAddressSet else {
                throw OWSAssertionError("Unexpected groupMembership.")
            }
            guard oldGroupModel.groupMembership.nonAdminMembers.isEmpty else {
                throw OWSAssertionError("Unexpected groupMembership.")
            }
            guard oldGroupModel.revision == 0 else {
                throw OWSAssertionError("Unexpected groupV2Revision: \(oldGroupModel.revision).")
            }
            guard oldGroupModel.groupName == title0 else {
                throw OWSAssertionError("Unexpected group title: \(oldGroupModel.groupName).")
            }
            guard oldGroupModel.groupAvatarData == nil else {
                throw OWSAssertionError("Unexpected group avatarData: \(oldGroupModel.groupAvatarData?.hexadecimalString).")
            }

            var groupMembershipBuilder = oldGroupModel.groupMembership.asBuilder
            for address in otherAddresses {
                groupMembershipBuilder.remove(address)
                groupMembershipBuilder.addNonPendingMember(address, role: .normal)
            }
            let groupMembership = groupMembershipBuilder.build()

            var groupModelBuilder = oldGroupModel.asBuilder
            groupModelBuilder.name = title1
            groupModelBuilder.avatarData = avatar1Data
            groupModelBuilder.avatarUrlPath = nil
            groupModelBuilder.groupMembership = groupMembership
            let newGroupModel = try self.databaseStorage.read { transaction in
                try groupModelBuilder.build(transaction: transaction)
            }

            // GroupsV2 TODO: Add and remove members, change avatar, etc.

            return GroupManager.localUpdateExistingGroup(groupModel: newGroupModel,
                                                         dmConfiguration: dmConfiguration,
                                                         groupUpdateSourceAddress: localAddress)
        }.then(on: .global()) { (groupThread) -> Promise<GroupV2Snapshot> in
            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                throw OWSAssertionError("Invalid group model.")
            }
            return groupsV2.fetchCurrentGroupV2Snapshot(groupModel: groupModel)
        }.map(on: .global()) { (groupV2Snapshot: GroupV2Snapshot) throws -> Data in
            let groupModel = try self.databaseStorage.read { transaction in
                return try TSGroupModelBuilder(groupV2Snapshot: groupV2Snapshot).build(transaction: transaction) as! TSGroupModelV2
            }
            let groupId = groupModel.groupId
            guard groupModel.revision == 1 else {
                throw OWSAssertionError("Unexpected groupV2Revision: \(groupModel.revision).")
            }

            guard groupV2Snapshot.revision == 1 else {
                throw OWSAssertionError("Unexpected group version: \(groupV2Snapshot.revision).")
            }
            guard groupV2Snapshot.title == title1 else {
                throw OWSAssertionError("Unexpected group title: \(groupV2Snapshot.title).")
            }
            guard groupV2Snapshot.avatarData == avatar1Data else {
                throw OWSAssertionError("Unexpected group avatarData: \(groupV2Snapshot.avatarData?.hexadecimalString).")
            }
            guard groupModel.groupName == title1 else {
                throw OWSAssertionError("Unexpected group title: \(groupModel.groupName).")
            }
            guard groupModel.groupAvatarData == avatar1Data else {
                throw OWSAssertionError("Unexpected group avatarData: \(groupModel.groupAvatarData?.hexadecimalString).")
            }

            let groupMembership = groupModel.groupMembership

            // GroupsV2 TODO: Test around administrators and pending members.

            let expectedMembers = Set(stagingAccounts)
            guard groupMembership.nonPendingMembers == expectedMembers else {
                throw OWSAssertionError("Unexpected members: \(groupMembership.nonPendingMembers).")
            }
            let expectedAdministrators = localAddressSet
            guard groupMembership.nonPendingAdministrators == expectedAdministrators else {
                throw OWSAssertionError("Unexpected administrators: \(groupMembership.nonPendingAdministrators).")
            }
            guard groupV2Snapshot.accessControlForMembers == .member else {
                throw OWSAssertionError("Unexpected accessControlForMembers: \(groupV2Snapshot.accessControlForMembers).")
            }
            guard groupV2Snapshot.accessControlForAttributes == .member else {
                throw OWSAssertionError("Unexpected accessControlForAttributes: \(groupV2Snapshot.accessControlForAttributes).")
            }
            return groupId
        }.then(on: .global()) { (groupId: Data) throws -> Promise<TSGroupThread> in
            let (groupThread, dmConfiguration) = try self.fetchGroupThread(groupId: groupId)
            guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
                throw OWSAssertionError("Invalid group model.")
            }
            guard oldGroupModel.groupMembership.nonPendingAdministrators == localAddressSet else {
                throw OWSAssertionError("Unexpected groupMembership.")
            }
            guard oldGroupModel.groupMembership.nonAdminMembers == otherAddresses else {
                throw OWSAssertionError("Unexpected groupMembership.")
            }
            guard oldGroupModel.revision == 1 else {
                throw OWSAssertionError("Unexpected groupV2Revision: \(oldGroupModel.revision).")
            }
            guard oldGroupModel.groupName == title1 else {
                throw OWSAssertionError("Unexpected group title: \(oldGroupModel.groupName).")
            }
            guard oldGroupModel.groupAvatarData == avatar1Data else {
                throw OWSAssertionError("Unexpected group avatarData: \(oldGroupModel.groupAvatarData?.hexadecimalString).")
            }

            var groupMembershipBuilder = oldGroupModel.groupMembership.asBuilder
            for address in otherAddresses {
                groupMembershipBuilder.remove(address)
            }
            let groupMembership = groupMembershipBuilder.build()

            var groupModelBuilder = oldGroupModel.asBuilder
            groupModelBuilder.avatarData = nil
            groupModelBuilder.avatarUrlPath = nil
            groupModelBuilder.groupMembership = groupMembership
            let newGroupModel = try self.databaseStorage.read { transaction in
                try groupModelBuilder.build(transaction: transaction)
            }

            // GroupsV2 TODO: Add and remove members, change avatar, etc.

            return GroupManager.localUpdateExistingGroup(groupModel: newGroupModel,
                                                         dmConfiguration: dmConfiguration,
                                                         groupUpdateSourceAddress: localAddress)
        }.then(on: .global()) { (groupThread: TSGroupThread) -> Promise<GroupV2Snapshot> in
            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                throw OWSAssertionError("Invalid group model.")
            }
            return self.groupsV2.fetchCurrentGroupV2Snapshot(groupModel: groupModel)
        }.map(on: .global()) { (groupV2Snapshot: GroupV2Snapshot) throws -> Data in
            let groupModel = try self.databaseStorage.read { transaction in
                return try TSGroupModelBuilder(groupV2Snapshot: groupV2Snapshot).build(transaction: transaction) as! TSGroupModelV2
            }
            let groupId: Data = groupModel.groupId
            guard groupModel.revision == 2 else {
                throw OWSAssertionError("Unexpected groupV2Revision: \(groupModel.revision).")
            }

            guard groupV2Snapshot.revision == 2 else {
                throw OWSAssertionError("Unexpected group version: \(groupV2Snapshot.revision).")
            }
            guard groupV2Snapshot.title == title1 else {
                throw OWSAssertionError("Unexpected group title: \(groupV2Snapshot.title).")
            }
            guard groupV2Snapshot.avatarData == nil else {
                throw OWSAssertionError("Unexpected group avatarData: \(groupV2Snapshot.avatarData?.hexadecimalString).")
            }
            guard groupModel.groupName == title1 else {
                throw OWSAssertionError("Unexpected group title: \(groupModel.groupName).")
            }
            guard groupModel.groupAvatarData == nil else {
                throw OWSAssertionError("Unexpected group avatarData: \(groupModel.groupAvatarData?.hexadecimalString).")
            }

            let groupMembership = groupModel.groupMembership

            // GroupsV2 TODO: Test around administrators and pending members.

            let expectedMembers = localAddressSet
            guard groupMembership.nonPendingMembers == expectedMembers else {
                throw OWSAssertionError("Unexpected members: \(groupMembership.nonPendingMembers).")
            }
            let expectedAdministrators = localAddressSet
            guard groupMembership.nonPendingAdministrators == expectedAdministrators else {
                throw OWSAssertionError("Unexpected administrators: \(groupMembership.nonPendingAdministrators).")
            }
            guard groupV2Snapshot.accessControlForMembers == .member else {
                throw OWSAssertionError("Unexpected accessControlForMembers: \(groupV2Snapshot.accessControlForMembers).")
            }
            guard groupV2Snapshot.accessControlForAttributes == .member else {
                throw OWSAssertionError("Unexpected accessControlForAttributes: \(groupV2Snapshot.accessControlForAttributes).")
            }
            return groupId
        }.map(on: .global()) { (groupId: Data) throws -> Data in
            let (groupThread, dmConfiguration) = try self.fetchGroupThread(groupId: groupId)
            let groupModel = groupThread.groupModel as! TSGroupModelV2
            guard groupModel.groupMembership.nonPendingAdministrators == localAddressSet else {
                throw OWSAssertionError("Unexpected groupMembership.")
            }
            guard groupModel.groupMembership.nonAdminMembers.isEmpty else {
                throw OWSAssertionError("Unexpected groupMembership.")
            }
            guard groupModel.revision == 2 else {
                throw OWSAssertionError("Unexpected groupV2Revision: \(groupModel.revision).")
            }
            guard groupModel.groupName == title1 else {
                throw OWSAssertionError("Unexpected group title: \(groupModel.groupName).")
            }
            guard groupModel.groupAvatarData == nil else {
                throw OWSAssertionError("Unexpected group avatarData: \(groupModel.groupAvatarData?.hexadecimalString).")
            }
            return groupId
        }.done { (_: Data) -> Void in
            Logger.info("---- Success.")
        }.catch { error in
            owsFailDebug("---- Error: \(error)")
        }.retainUntilComplete()
    }

    private static func fetchGroupThread(groupId: Data) throws -> (TSGroupThread, OWSDisappearingMessagesConfiguration) {
        return try databaseStorage.read { (transaction) throws -> (TSGroupThread, OWSDisappearingMessagesConfiguration) in
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("Missing groupThread.")
            }
            let dmConfiguration = groupThread.disappearingMessagesConfiguration(with: transaction)
            return (groupThread, dmConfiguration)
        }
    }
}
