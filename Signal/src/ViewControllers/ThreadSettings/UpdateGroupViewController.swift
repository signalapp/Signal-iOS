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

        // GroupsV2 TODO: Should we allow cancel here?
        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false) { modalActivityIndicator in
                                                        firstly {
                                                            self.updateGroupThreadPromise(oldGroupModel: oldGroupModel,
                                                                                          newGroupModel: newGroupModel)
                                                        }.done { groupThread in
                                                            modalActivityIndicator.dismiss {
                                                                delegate.conversationSettingsDidUpdate(groupThread)
                                                                delegate.popAllConversationSettingsViews()
                                                            }
                                                        }.catch { error in
                                                            if case GroupsV2Error.redundantChange = error {
                                                                if let groupThread = (self.databaseStorage.read { transaction in
                                                                    TSGroupThread.fetch(groupId: newGroupModel.groupId, transaction: transaction)
                                                                    }) {
                                                                    // Treat GroupsV2Error.redundantChange as a success.
                                                                    modalActivityIndicator.dismiss {
                                                                        delegate.conversationSettingsDidUpdate(groupThread)
                                                                        delegate.popAllConversationSettingsViews()
                                                                    }
                                                                    return
                                                                }
                                                            }

                                                            owsFailDebug("Could not update group: \(error)")

                                                            modalActivityIndicator.dismiss {
                                                                UpdateGroupViewController.showUpdateErrorUI(error: error)
                                                            }
                                                        }.retainUntilComplete()
        }
    }

    class func showUpdateErrorUI(error: Error) {
        AssertIsOnMainThread()

        let showUpdateNetworkErrorUI = {
            OWSActionSheets.showActionSheet(title: NSLocalizedString("UPDATE_GROUP_FAILED_DUE_TO_NETWORK",
                                                                     comment: "Error indicating that a group could not be updated due to network connectivity problems."))
        }

        if error.isNetworkFailureOrTimeout {
            return showUpdateNetworkErrorUI()
        }

        OWSActionSheets.showActionSheet(title: NSLocalizedString("UPDATE_GROUP_FAILED",
                                                                 comment: "Error indicating that a group could not be updated."))
    }
}

// MARK: -

extension UpdateGroupViewController {
    private func updateGroupThreadPromise(oldGroupModel: TSGroupModel,
                                          newGroupModel: TSGroupModel) -> Promise<TSGroupThread> {

        guard let localAddress = tsAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Missing localAddress."))
        }

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: oldGroupModel)
        }.then(on: .global()) { _ in
            // dmConfiguration: nil means don't change disappearing messages configuration.
            GroupManager.localUpdateExistingGroup(groupModel: newGroupModel,
                                                  dmConfiguration: nil,
                                                  groupUpdateSourceAddress: localAddress)
        }
    }
}
