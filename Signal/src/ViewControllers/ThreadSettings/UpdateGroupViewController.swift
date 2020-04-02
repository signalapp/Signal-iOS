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
            return try databaseStorage.read { transaction in
                let newGroupMembership: GroupMembership
                switch oldGroupModel.groupsVersion {
                case .V1:
                    newGroupMembership = GroupMembership(v1Members: v1Members)
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
                    newGroupMembership = groupMembershipBuilder.build()
                }

                var builder = oldGroupModel.asBuilder
                builder.name = newTitle
                builder.avatarData = newAvatarData
                builder.groupMembership = newGroupMembership
                return try builder.build(transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error)")
            return oldGroupModel
        }
    }

    func updateGroupThread(oldGroupModel: TSGroupModel,
                           newGroupModel: TSGroupModel,
                           delegate: OWSConversationSettingsViewDelegate) {

        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: self,
                                                        updatePromiseBlock: {
                                                            self.updateGroupThreadPromise(oldGroupModel: oldGroupModel,
                                                                newGroupModel: newGroupModel)
        },
                                                        completion: {
                                                            delegate.conversationSettingsDidUpdate()
            delegate.popAllConversationSettingsViews()
        })
    }
}

// MARK: -

extension UpdateGroupViewController {
    fileprivate func updateGroupThreadPromise(oldGroupModel: TSGroupModel,
                                              newGroupModel: TSGroupModel) -> Promise<Void> {

        guard let localAddress = tsAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Missing localAddress."))
        }

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: oldGroupModel,
                                                         description: self.logTag)
        }.then(on: .global()) { _ in
            // dmConfiguration: nil means don't change disappearing messages configuration.
            GroupManager.localUpdateExistingGroup(groupModel: newGroupModel,
                                                  dmConfiguration: nil,
                                                  groupUpdateSourceAddress: localAddress)
        }.asVoid()
    }
}
