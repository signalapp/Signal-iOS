//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public extension UpdateGroupViewController {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    func canAddOrInviteMember(oldGroupModel: TSGroupModel,
                              address: SignalServiceAddress) -> Bool {
        guard oldGroupModel.groupsVersion == .V2 else {
            return true
        }
        return databaseStorage.read { transaction in
            return GroupManager.doesUserSupportGroupsV2(address: address, transaction: transaction)
        }
    }

    func buildNewGroupModel(oldGroupModel: TSGroupModel,
                            newTitle: String?,
                            newAvatarData: Data?,
                            v1Members: Set<SignalServiceAddress>) -> TSGroupModel {
        do {
            let groupId = oldGroupModel.groupId
            return try databaseStorage.read { transaction in
                let groupMembership: GroupMembership
                switch oldGroupModel.groupsVersion {
                case .V1:
                    groupMembership = GroupMembership(v1Members: v1Members)
                case .V2:
                    // GroupsV2 TODO: This is a temporary implementation until we
                    // rewrite groups v2 to be aware of roles, access, kicking
                    // members, etc.  For now, new users will _not_ be added as
                    // administrators.
                    let oldGroupMembership = oldGroupModel.groupMembership
                    var groupMembershipBuilder = oldGroupMembership.asBuilder
                    for address in v1Members {
                        guard GroupManager.doesUserSupportGroupsV2(address: address, transaction: transaction) else {
                            Logger.warn("Invalid address: \(address)")
                            continue
                        }
                        if !oldGroupMembership.allUsers.contains(address) {
                            groupMembershipBuilder.addNonPendingMember(address, role: .normal)
                        }
                    }
                    // GroupsV2 TODO: Remove members, change roles, etc. when
                    // UI supports pending members, kicking members, etc..
                    groupMembership = groupMembershipBuilder.build()
                }
                let groupsVersion = oldGroupModel.groupsVersion
                return try GroupManager.buildGroupModel(groupId: groupId,
                                                        name: newTitle,
                                                        avatarData: newAvatarData,
                                                        groupMembership: groupMembership,
                                                        groupAccess: oldGroupModel.groupAccess,
                                                        groupsVersion: groupsVersion,
                                                        groupV2Revision: oldGroupModel.groupV2Revision,
                                                        groupSecretParamsData: oldGroupModel.groupSecretParamsData,
                                                        newGroupSeed: nil,
                                                        transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error)")
            return oldGroupModel
        }
    }

    func updateGroupThread(oldGroupModel: TSGroupModel,
                           newGroupModel: TSGroupModel,
                           success: @escaping (TSGroupThread) -> Void,
                           failure: @escaping (Error) -> Void) {

        guard let localAddress = tsAccountManager.localAddress else {
            return failure(OWSAssertionError("Missing localAddress."))
        }

        // dmConfiguration: nil means don't change disappearing messages configuration.
        firstly {
            GroupManager.localUpdateExistingGroup(groupId: newGroupModel.groupId,
                                                  name: newGroupModel.groupName,
                                                  avatarData: newGroupModel.groupAvatarData,
                                                  groupMembership: newGroupModel.groupMembership,
                                                  groupAccess: newGroupModel.groupAccess,
                                                  groupsVersion: newGroupModel.groupsVersion,
                                                  dmConfiguration: nil,
                                                  groupUpdateSourceAddress: localAddress)
        }.done(on: .global()) { groupThread in
            success(groupThread)
        }.catch(on: .global()) { (error) in
            switch error {
            case GroupsV2Error.redundantChange:
                // GroupsV2 TODO: Treat this as a success.

                owsFailDebug("Could not update group: \(error)")

                failure(error)
            default:
                owsFailDebug("Could not update group: \(error)")

                failure(error)
            }
        }.retainUntilComplete()
    }
}
