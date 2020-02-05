//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public extension ThreadUtil {

    static func leaveGroupOrDeclineInviteAsync(_ groupThread: TSGroupThread,
                                               fromViewController: UIViewController,
                                               success: @escaping () -> Void) {
        ModalActivityIndicatorViewController.present(fromViewController: fromViewController,
                                                     canCancel: false) { modalActivityIndicator in
                                                        firstly { () -> Promise<TSGroupThread> in
                                                            GroupManager.leaveGroupOrDeclineInvite(groupThread: groupThread)
                                                        }.done { _ in
                                                            modalActivityIndicator.dismiss {
                                                                success()
                                                            }
                                                        }.catch { error in
                                                            owsFailDebug("Error: \(error)")

                                                            modalActivityIndicator.dismiss {
                                                                let title = NSLocalizedString("GROUPS_LEAVE_GROUP_FAILED",
                                                                                              comment: "Error indicating that a group could not be left.")
                                                                OWSActionSheets.showActionSheet(title: title)
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
                                                            GroupManager.acceptInviteToGroupV2(groupThread: groupThread)
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
