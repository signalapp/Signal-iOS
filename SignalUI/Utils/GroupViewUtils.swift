//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalServiceKit
import UIKit

public class GroupViewUtils {

    public static func formatGroupMembersLabel(memberCount: Int) -> String {
        let format = OWSLocalizedString(
            "GROUP_MEMBER_COUNT_LABEL_%d",
            tableName: "PluralAware",
            comment: "The 'group member count' indicator when there are no members in the group.",
        )
        return String.localizedStringWithFormat(format, memberCount)
    }

    @MainActor
    public static func updateGroupWithActivityIndicator(
        fromViewController: UIViewController,
        updateBlock: @escaping () async throws -> Void,
        completion: (() -> Void)?,
    ) {
        // GroupsV2 TODO: Should we allow cancel here?
        ModalActivityIndicatorViewController.present(
            fromViewController: fromViewController,
            canCancel: false,
            asyncBlock: { modalActivityIndicator in
                do {
                    try await GroupManager.waitForMessageFetchingAndProcessingWithTimeout()
                    try await updateBlock()
                    modalActivityIndicator.dismiss {
                        completion?()
                    }
                } catch {
                    owsFailDebugUnlessNetworkFailure(error)

                    modalActivityIndicator.dismiss {
                        GroupViewUtils.showUpdateErrorUI(error: error)
                    }
                }
            },
        )
    }

    public class func showUpdateErrorUI(error: Error) {
        AssertIsOnMainThread()

        if error.isNetworkFailureOrTimeout {
            OWSActionSheets.showActionSheet(
                title: OWSLocalizedString(
                    "ERROR_NETWORK_FAILURE",
                    comment: "Error indicating network connectivity problems.",
                ),
                message: OWSLocalizedString(
                    "UPDATE_GROUP_FAILED_DUE_TO_NETWORK",
                    comment: "Error indicating that a group could not be updated due to network connectivity problems.",
                ),
            )
        } else {
            OWSActionSheets.showActionSheet(title: OWSLocalizedString(
                "UPDATE_GROUP_FAILED",
                comment: "Error indicating that a group could not be updated.",
            ))
        }
    }

    public static func showInvalidGroupMemberAlert(fromViewController: UIViewController) {
        let actionSheet = ActionSheetController(
            title: CommonStrings.errorAlertTitle,
            message: OWSLocalizedString(
                "EDIT_GROUP_ERROR_CANNOT_ADD_MEMBER",
                comment: "Error message indicating the a user can't be added to a group.",
            ),
        )

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.learnMore,
            style: .default,
        ) { _ in
            self.showCantAddMemberView(fromViewController: fromViewController)
        })
        actionSheet.addAction(OWSActionSheets.okayAction)
        fromViewController.presentActionSheet(actionSheet)
    }

    private static func showCantAddMemberView(fromViewController: UIViewController) {
        let vc = SFSafariViewController(url: URL.Support.groups)
        fromViewController.present(vc, animated: true, completion: nil)
    }
}
