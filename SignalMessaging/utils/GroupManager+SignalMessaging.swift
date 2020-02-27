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

    static func leaveGroupThreadAsyncWithUI(groupThread: TSGroupThread,
                                            fromViewController: UIViewController,
                                            success: (() -> Void)?) {

        guard groupThread.isLocalUserInGroup() else {
            owsFailDebug("unexpectedly trying to leave group for which we're not a member.")
            return
        }

        databaseStorage.write { transaction in
            sendGroupQuitMessage(inThread: groupThread, transaction: transaction)
        }

        ModalActivityIndicatorViewController.present(fromViewController: fromViewController, canCancel: false) { modalView in
            firstly {
                self.leaveGroupOrDeclineInvite(groupThread: groupThread).asVoid()
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
}
