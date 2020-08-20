//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public extension GroupManager {

    // MARK: - Dependencies

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    static func leaveGroupOrDeclineInviteAsyncWithUI(groupThread: TSGroupThread,
                                                     fromViewController: UIViewController,
                                                     replacementAdminUuid: UUID? = nil,
                                                     success: (() -> Void)?) {

        guard groupThread.isLocalUserMemberOfAnyKind else {
            owsFailDebug("unexpectedly trying to leave group for which we're not a member.")
            return
        }

        ModalActivityIndicatorViewController.present(fromViewController: fromViewController, canCancel: false) { modalView in
            firstly {
                self.leaveGroupOrDeclineInvitePromise(groupThread: groupThread,
                                                      replacementAdminUuid: replacementAdminUuid).asVoid()
            }.done { _ in
                modalView.dismiss {
                    success?()
                }
            }.catch { error in
                owsFailDebug("Leave group failed: \(error)")
                modalView.dismiss {
                    OWSActionSheets.showActionSheet(title: NSLocalizedString("LEAVE_GROUP_FAILED",
                                                                             comment: "Error indicating that a group could not be left."))
                }
            }
        }
    }

    static func acceptGroupInviteAsync(_ groupThread: TSGroupThread,
                                       fromViewController: UIViewController,
                                       success: @escaping () -> Void) {
        ModalActivityIndicatorViewController.present(fromViewController: fromViewController,
                                                     canCancel: false) { modalActivityIndicator in
                                                        firstly { () -> Promise<TSGroupThread> in
                                                            self.acceptGroupInvitePromise(groupThread: groupThread)
                                                        }.done { _ in
                                                            modalActivityIndicator.dismiss {
                                                                success()
                                                            }
                                                        }.catch { error in
                                                            owsFailDebug("Error: \(error)")

                                                            modalActivityIndicator.dismiss {
                                                                let title = NSLocalizedString("GROUPS_INVITE_ACCEPT_INVITE_FAILED",
                                                                                              comment: "Error indicating that an error occurred while accepting an invite.")
                                                                OWSActionSheets.showActionSheet(title: title)
                                                            }
                                                        }
        }
    }
}

// MARK: -

extension GroupManager {
    static func leaveGroupOrDeclineInvitePromise(groupThread: TSGroupThread,
                                                 replacementAdminUuid: UUID? = nil) -> Promise<TSGroupThread> {
        return firstly {
            return GroupManager.messageProcessingPromise(for: groupThread,
                                                         description: "Leave or decline invite")
        }.then(on: .global()) {
            GroupManager.localLeaveGroupOrDeclineInvite(groupThread: groupThread,
                                                        replacementAdminUuid: replacementAdminUuid)
        }
    }

    static func acceptGroupInvitePromise(groupThread: TSGroupThread) -> Promise<TSGroupThread> {
        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: groupThread,
                                                         description: "Accept invite")
        }.then(on: .global()) { _ -> Promise<TSGroupThread> in
            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                throw OWSAssertionError("Invalid group model.")
            }
            return GroupManager.localAcceptInviteToGroupV2(groupModel: groupModel)
        }
    }
}
