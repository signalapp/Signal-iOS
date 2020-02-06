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

    private class var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
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
        guard let groupsV2Swift = self.groupsV2 as? GroupsV2Swift else {
            owsFailDebug("Missing groupsV2Swift.")
            return
        }
        GroupManager.createNewGroup(members: members,
                                    name: title0,
                                    shouldSendMessage: true)
            .then(on: .global()) { (groupThread: TSGroupThread) -> Promise<(Data, GroupV2Snapshot)> in
                let groupModel = groupThread.groupModel
                guard groupModel.groupsVersion == .V2 else {
                    throw OWSAssertionError("Not a V2 group.")
                }
                return groupsV2Swift.fetchCurrentGroupV2Snapshot(groupModel: groupModel)
                    .map(on: .global()) { (groupV2Snapshot: GroupV2Snapshot) -> (Data, GroupV2Snapshot) in
                        return (groupThread.groupModel.groupId, groupV2Snapshot)
                }
        }.map(on: .global()) { (groupId: Data, groupV2Snapshot: GroupV2Snapshot) throws -> Data in

            let groupModel = try self.databaseStorage.read { transaction in
                return try GroupManager.buildGroupModel(groupV2Snapshot: groupV2Snapshot, transaction: transaction)
            }
            guard groupModel.groupV2Revision == 0 else {
                throw OWSAssertionError("Unexpected groupV2Revision: \(groupModel.groupV2Revision).")
            }

            guard groupV2Snapshot.revision == 0 else {
                throw OWSAssertionError("Unexpected group version: \(groupV2Snapshot.revision).")
            }
            guard groupV2Snapshot.title == title0 else {
                throw OWSAssertionError("Unexpected group title: \(groupV2Snapshot.title).")
            }

            let groupMembership = groupModel.groupMembership

            // GroupsV2 TODO: Test around administrators and pending members.
            let expectedMembers = localAddressSet
            guard groupMembership.allMembers == expectedMembers else {
                throw OWSAssertionError("Unexpected members: \(groupMembership.allMembers).")
            }
            let expectedAdministrators = expectedMembers
            guard groupMembership.administrators == expectedAdministrators else {
                throw OWSAssertionError("Unexpected administrators: \(groupMembership.administrators).")
            }
            guard groupV2Snapshot.accessControlForMembers == .member else {
                throw OWSAssertionError("Unexpected accessControlForMembers: \(groupV2Snapshot.accessControlForMembers).")
            }
            guard groupV2Snapshot.accessControlForAttributes == .member else {
                throw OWSAssertionError("Unexpected accessControlForAttributes: \(groupV2Snapshot.accessControlForAttributes).")
            }
            return groupId
        }.then(on: .global()) { (groupId: Data) throws -> Promise<(Data, GroupV2Snapshot)> in
            let (groupThread, dmConfiguration) = try self.fetchGroupThread(groupId: groupId)
            let groupModel = groupThread.groupModel
            guard groupModel.groupMembership.administrators == localAddressSet else {
                throw OWSAssertionError("Unexpected groupMembership.")
            }
            guard groupModel.groupMembership.nonAdminMembers.isEmpty else {
                throw OWSAssertionError("Unexpected groupMembership.")
            }
            guard groupModel.groupV2Revision == 0 else {
                throw OWSAssertionError("Unexpected groupV2Revision: \(groupModel.groupV2Revision).")
            }

            var groupMembershipBuilder = groupModel.groupMembership.asBuilder
            for address in otherAddresses {
                groupMembershipBuilder.replace(address, isAdministrator: false, isPending: false)
            }
            let groupMembership = groupMembershipBuilder.build()

            let groupAccess = groupModel.groupAccess!
            // GroupsV2 TODO: Add and remove members, change avatar, etc.

            return GroupManager.updateExistingGroup(groupId: groupId,
                                                    name: title1,
                                                    avatarData: nil,
                                                    groupMembership: groupMembership,
                                                    groupAccess: groupAccess,
                                                    groupsVersion: groupModel.groupsVersion,
                                                    dmConfiguration: dmConfiguration,
                                                    groupUpdateSourceAddress: localAddress)
                .then(on: .global()) { (groupThread) -> Promise<GroupV2Snapshot> in
                    // GroupsV2 TODO: This should reflect the new group.
                    return groupsV2Swift.fetchCurrentGroupV2Snapshot(groupModel: groupThread.groupModel)
            }.map(on: .global()) { (groupV2Snapshot: GroupV2Snapshot) -> (Data, GroupV2Snapshot) in
                return (groupId, groupV2Snapshot)
            }
        }.map(on: .global()) { (groupId: Data, groupV2Snapshot: GroupV2Snapshot) throws -> Data in

            let groupModel = try self.databaseStorage.read { transaction in
                return try GroupManager.buildGroupModel(groupV2Snapshot: groupV2Snapshot, transaction: transaction)
            }
            guard groupModel.groupV2Revision == 1 else {
                throw OWSAssertionError("Unexpected groupV2Revision: \(groupModel.groupV2Revision).")
            }

            guard groupV2Snapshot.revision == 1 else {
                throw OWSAssertionError("Unexpected group version: \(groupV2Snapshot.revision).")
            }
            guard groupV2Snapshot.title == title1 else {
                throw OWSAssertionError("Unexpected group title: \(groupV2Snapshot.title).")
            }

            let groupMembership = groupModel.groupMembership

            // GroupsV2 TODO: Test around administrators and pending members.

            let expectedMembers = Set(stagingAccounts)
            guard groupMembership.allMembers == expectedMembers else {
                throw OWSAssertionError("Unexpected members: \(groupMembership.allMembers).")
            }
            let expectedAdministrators = localAddressSet
            guard groupMembership.administrators == expectedAdministrators else {
                throw OWSAssertionError("Unexpected administrators: \(groupMembership.administrators).")
            }
            guard groupV2Snapshot.accessControlForMembers == .member else {
                throw OWSAssertionError("Unexpected accessControlForMembers: \(groupV2Snapshot.accessControlForMembers).")
            }
            guard groupV2Snapshot.accessControlForAttributes == .member else {
                throw OWSAssertionError("Unexpected accessControlForAttributes: \(groupV2Snapshot.accessControlForAttributes).")
            }
            return groupId
        }.then(on: .global()) { (groupId: Data) throws -> Promise<(Data, GroupV2Snapshot)> in
            let (groupThread, dmConfiguration) = try self.fetchGroupThread(groupId: groupId)
            let groupModel = groupThread.groupModel
            guard groupModel.groupMembership.administrators == localAddressSet else {
                throw OWSAssertionError("Unexpected groupMembership.")
            }
            guard groupModel.groupMembership.nonAdminMembers == otherAddresses else {
                throw OWSAssertionError("Unexpected groupMembership.")
            }
            guard groupModel.groupV2Revision == 1 else {
                throw OWSAssertionError("Unexpected groupV2Revision: \(groupModel.groupV2Revision).")
            }

            var groupMembershipBuilder = groupModel.groupMembership.asBuilder
            for address in otherAddresses {
                groupMembershipBuilder.remove(address)
            }
            let groupMembership = groupMembershipBuilder.build()

            let groupAccess = groupModel.groupAccess!
            // GroupsV2 TODO: Add and remove members, change avatar, etc.

            return GroupManager.updateExistingGroup(groupId: groupId,
                                                    name: title1,
                                                    avatarData: nil,
                                                    groupMembership: groupMembership,
                                                    groupAccess: groupAccess,
                                                    groupsVersion: groupModel.groupsVersion,
                                                    dmConfiguration: dmConfiguration,
                                                    groupUpdateSourceAddress: localAddress)
                .then(on: .global()) { (_) -> Promise<GroupV2Snapshot> in
                    // GroupsV2 TODO: This should reflect the new group.
                    return groupsV2Swift.fetchCurrentGroupV2Snapshot(groupModel: groupModel)
            }.map(on: .global()) { (groupV2Snapshot: GroupV2Snapshot) -> (Data, GroupV2Snapshot) in
                return (groupId, groupV2Snapshot)
            }
        }.map(on: .global()) { (groupId: Data, groupV2Snapshot: GroupV2Snapshot) throws -> Data in

            let groupModel = try self.databaseStorage.read { transaction in
                return try GroupManager.buildGroupModel(groupV2Snapshot: groupV2Snapshot, transaction: transaction)
            }
            guard groupModel.groupV2Revision == 2 else {
                throw OWSAssertionError("Unexpected groupV2Revision: \(groupModel.groupV2Revision).")
            }

            guard groupV2Snapshot.revision == 2 else {
                throw OWSAssertionError("Unexpected group version: \(groupV2Snapshot.revision).")
            }
            guard groupV2Snapshot.title == title1 else {
                throw OWSAssertionError("Unexpected group title: \(groupV2Snapshot.title).")
            }

            let groupMembership = groupModel.groupMembership

            // GroupsV2 TODO: Test around administrators and pending members.

            let expectedMembers = localAddressSet
            guard groupMembership.allMembers == expectedMembers else {
                throw OWSAssertionError("Unexpected members: \(groupMembership.allMembers).")
            }
            let expectedAdministrators = localAddressSet
            guard groupMembership.administrators == expectedAdministrators else {
                throw OWSAssertionError("Unexpected administrators: \(groupMembership.administrators).")
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
            let groupModel = groupThread.groupModel
            guard groupModel.groupMembership.administrators == localAddressSet else {
                throw OWSAssertionError("Unexpected groupMembership.")
            }
            guard groupModel.groupMembership.nonAdminMembers.isEmpty else {
                throw OWSAssertionError("Unexpected groupMembership.")
            }
            guard groupModel.groupV2Revision == 2 else {
                throw OWSAssertionError("Unexpected groupV2Revision: \(groupModel.groupV2Revision).")
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
