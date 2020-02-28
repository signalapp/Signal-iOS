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

    fileprivate class var messageProcessing: MessageProcessing {
        return SSKEnvironment.shared.messageProcessing
    }

    // MARK: -

    static func leaveGroupOrDeclineInviteAsyncWithUI(groupThread: TSGroupThread,
                                                     fromViewController: UIViewController,
                                                     success: (() -> Void)?) {

        guard groupThread.isLocalUserPendingOrNonPendingMember else {
            owsFailDebug("unexpectedly trying to leave group for which we're not a member.")
            return
        }

        databaseStorage.write { transaction in
            sendGroupQuitMessage(inThread: groupThread, transaction: transaction)
        }

        ModalActivityIndicatorViewController.present(fromViewController: fromViewController, canCancel: false) { modalView in
            firstly {
                self.leaveGroupOrDeclineInvitePromise(groupThread: groupThread).asVoid()
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
            }.retainUntilComplete()
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
                                                        }.retainUntilComplete()
        }
    }
}

// MARK: -

extension GroupManager {
    static func leaveGroupOrDeclineInvitePromise(groupThread: TSGroupThread) -> Promise<TSGroupThread> {
        return firstly { () -> Promise<Void> in
            guard groupThread.groupModel.groupsVersion == .V2 else {
                return Promise.value(())
            }
            // v2 group updates need to block on message processing.
            return firstly {
                self.messageProcessing.allMessageFetchingAndProcessingPromise()
            }.timeout(seconds: GroupManager.KGroupUpdateTimeoutDuration) {
                GroupsV2Error.timeout
            }
        }.then(on: .global()) {
            GroupManager.localLeaveGroupOrDeclineInvite(groupThread: groupThread)
        }
    }

    static func acceptGroupInvitePromise(groupThread: TSGroupThread) -> Promise<TSGroupThread> {
        return firstly { () -> Promise<Void> in
            guard groupThread.groupModel.groupsVersion == .V2 else {
                return Promise.value(())
            }
            // v2 group updates need to block on message processing.
            return firstly {
                self.messageProcessing.allMessageFetchingAndProcessingPromise()
            }.timeout(seconds: GroupManager.KGroupUpdateTimeoutDuration) {
                GroupsV2Error.timeout
            }
        }.then(on: .global()) { _ -> Promise<TSGroupThread> in
            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                throw OWSAssertionError("Invalid group model.")
            }
            return GroupManager.localAcceptInviteToGroupV2(groupModel: groupModel)
        }
    }
}
