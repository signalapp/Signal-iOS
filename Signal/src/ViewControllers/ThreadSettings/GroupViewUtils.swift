//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import UIKit

class GroupViewUtils {

    public static func formatGroupMembersLabel(memberCount: Int) -> String {
        guard memberCount > 0 else {
            return NSLocalizedString("GROUP_MEMBER_COUNT_LABEL_0",
                                     comment: "The 'group member count' indicator when there are no members in the group.")
        }
        guard memberCount != 1 else {
            return NSLocalizedString("GROUP_MEMBER_COUNT_LABEL_1",
                                     comment: "The 'group member count' indicator when there is 1 member in the group.")
        }
        let format = NSLocalizedString("GROUP_MEMBER_COUNT_LABEL_FORMAT",
                                       comment: "Format for the 'group member count' indicator. Embeds {the number of group members}.")
        return String(format: format, OWSFormat.formatInt(memberCount))
    }

    public static func updateGroupWithActivityIndicator(fromViewController: UIViewController,
                                                        updatePromiseBlock: @escaping () -> Promise<Void>,
                                                        completion: @escaping () -> Void) {
        // GroupsV2 TODO: Should we allow cancel here?
        ModalActivityIndicatorViewController.present(fromViewController: fromViewController,
                                                     canCancel: false) { modalActivityIndicator in
                                                        firstly {
                                                            updatePromiseBlock()
                                                        }.done { _ in
                                                            modalActivityIndicator.dismiss {
                                                                completion()
                                                            }
                                                        }.catch { error in
                                                            switch error {
                                                            case GroupsV2Error.redundantChange:
                                                                // Treat GroupsV2Error.redundantChange as a success.
                                                                modalActivityIndicator.dismiss {
                                                                    completion()
                                                                }
                                                            default:
                                                                owsFailDebug("Could not update group: \(error)")

                                                                modalActivityIndicator.dismiss {
                                                                    GroupViewUtils.showUpdateErrorUI(error: error)
                                                                }
                                                            }
                                                        }
        }
    }

    public class func showUpdateErrorUI(error: Error) {
        AssertIsOnMainThread()

        let showUpdateNetworkErrorUI = {
            OWSActionSheets.showActionSheet(title: NSLocalizedString("ERROR_NETWORK_FAILURE",
                                                                     comment: "Error indicating network connectivity problems."),
                                            message: NSLocalizedString("UPDATE_GROUP_FAILED_DUE_TO_NETWORK",
                                                                     comment: "Error indicating that a group could not be updated due to network connectivity problems."))
        }

        if error.isNetworkFailureOrTimeout {
            return showUpdateNetworkErrorUI()
        }

        OWSActionSheets.showActionSheet(title: NSLocalizedString("UPDATE_GROUP_FAILED",
                                                                 comment: "Error indicating that a group could not be updated."))
    }
}
