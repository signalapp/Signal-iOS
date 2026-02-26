//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

@MainActor
class LeaveGroupCoordinator: ReplaceAdminViewControllerDelegate {
    private let groupThread: TSGroupThread
    private let groupModel: TSGroupModelV2
    private let localAci: Aci
    private let onSuccess: () -> Void

    init(
        groupThread: TSGroupThread,
        groupModel: TSGroupModelV2,
        localAci: Aci,
        onSuccess: @escaping () -> Void,
    ) {
        self.groupThread = groupThread
        self.groupModel = groupModel
        self.localAci = localAci
        self.onSuccess = onSuccess
    }

    func startLeaveGroupFlow(rootViewController: UIViewController) {
        // Retain self for the lifetime of rootViewController.
        ObjectRetainer.retainObject(self, forLifetimeOf: rootViewController)

        if
            GroupManager.canLocalUserLeaveGroupWithoutChoosingNewAdmin(
                localAci: localAci,
                groupMembership: groupModel.groupMembership,
            )
        {
            showLeaveGroupConfirmAlert(
                fromViewController: rootViewController,
                replacementAdminAci: nil,
            )
        } else {
            showReplaceAdminAlert(fromViewController: rootViewController)
        }
    }

    // MARK: -

    private func showLeaveGroupConfirmAlert(
        fromViewController: UIViewController,
        replacementAdminAci: Aci?,
    ) {
        let alert = ActionSheetController(
            title: OWSLocalizedString(
                "CONFIRM_LEAVE_GROUP_TITLE",
                comment: "Alert title",
            ),
            message: OWSLocalizedString(
                "CONFIRM_LEAVE_GROUP_DESCRIPTION",
                comment: "Alert body",
            ),
        )

        alert.addAction(ActionSheetAction(
            title: CommonStrings.leaveButton,
            style: .destructive,
            handler: { [weak self, weak fromViewController] _ in
                guard let self, let fromViewController else { return }

                leaveGroup(
                    fromViewController: fromViewController,
                    replacementAdminAci: replacementAdminAci,
                )
            },
        ))

        alert.addAction(OWSActionSheets.cancelAction)
        fromViewController.presentActionSheet(alert)
    }

    private func showReplaceAdminAlert(fromViewController: UIViewController) {
        let replacementAdminCandidates = groupModel.groupMembership.fullMembers
            .filter { $0.aci != localAci }

        guard !replacementAdminCandidates.isEmpty else {
            OWSActionSheets.showErrorAlert(
                message: OWSLocalizedString(
                    "GROUPS_CANT_REPLACE_ADMIN_ALERT_MESSAGE",
                    comment: "Message for the 'can't replace group admin' alert.",
                ),
                fromViewController: fromViewController,
            )
            return
        }

        let alert = ActionSheetController(
            title: OWSLocalizedString(
                "GROUPS_REPLACE_ADMIN_ALERT_TITLE",
                comment: "Title for the 'replace group admin' alert.",
            ),
            message: OWSLocalizedString(
                "GROUPS_REPLACE_ADMIN_ALERT_MESSAGE",
                comment: "Message for the 'replace group admin' alert.",
            ),
        )

        alert.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "GROUPS_REPLACE_ADMIN_BUTTON",
                comment: "Label for the 'replace group admin' button.",
            ),
            style: .default,
            handler: { [weak self, weak fromViewController] _ in
                guard let self, let fromViewController else { return }

                showReplaceAdminView(
                    fromViewController: fromViewController,
                    candidates: replacementAdminCandidates,
                )
            },
        ))

        alert.addAction(OWSActionSheets.cancelAction)
        fromViewController.presentActionSheet(alert)
    }

    private func showReplaceAdminView(
        fromViewController: UIViewController,
        candidates: Set<SignalServiceAddress>,
    ) {
        owsAssertDebug(!candidates.isEmpty)

        let replaceAdminViewController = ReplaceAdminViewController(
            candidates: candidates,
            replaceAdminViewControllerDelegate: self,
        )

        fromViewController.present(
            OWSNavigationController(rootViewController: replaceAdminViewController),
            animated: true,
        )
    }

    private func leaveGroup(
        fromViewController: UIViewController,
        replacementAdminAci: Aci?,
    ) {
        GroupManager.leaveGroupOrDeclineInviteAsyncWithUI(
            groupThread: groupThread,
            fromViewController: fromViewController,
            replacementAdminAci: replacementAdminAci,
        ) { [onSuccess] in
            if let replaceAdminViewController = fromViewController as? ReplaceAdminViewController {
                replaceAdminViewController.dismiss(animated: true) {
                    onSuccess()
                }
            } else {
                onSuccess()
            }
        }
    }

    // MARK: - ReplaceAdminViewControllerDelegate

    func replaceAdminView(
        _ replaceAdminViewController: ReplaceAdminViewController,
        didSelectNewAdminAci replacementAdminAci: Aci,
    ) {
        showLeaveGroupConfirmAlert(
            fromViewController: replaceAdminViewController,
            replacementAdminAci: replacementAdminAci,
        )
    }
}
