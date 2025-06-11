//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
public import SignalServiceKit

public extension GroupManager {

    @MainActor
    static func leaveGroupOrDeclineInviteAsyncWithUI(
        groupThread: TSGroupThread,
        fromViewController: UIViewController,
        replacementAdminAci: Aci? = nil,
        success: (() -> Void)?
    ) {

        guard groupThread.isLocalUserMemberOfAnyKind else {
            owsFailDebug("unexpectedly trying to leave group for which we're not a member.")
            return
        }

        ModalActivityIndicatorViewController.present(
            fromViewController: fromViewController,
            canCancel: false,
            asyncBlock: { modal in
                do {
                    try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                        self.localLeaveGroupOrDeclineInvite(
                            groupThread: groupThread,
                            replacementAdminAci: replacementAdminAci,
                            waitForMessageProcessing: true,
                            tx: transaction
                        )
                    }.awaitable()
                    modal.dismiss { success?() }
                } catch {
                    owsFailDebug("Leave group failed: \(error)")
                    modal.dismiss {
                        OWSActionSheets.showActionSheet(
                            title: OWSLocalizedString(
                                "LEAVE_GROUP_FAILED",
                                comment: "Error indicating that a group could not be left."
                            )
                        )
                    }
                }
            }
        )
    }

    @MainActor
    static func acceptGroupInviteWithModal(
        _ groupThread: TSGroupThread,
        fromViewController: UIViewController
    ) async throws {
        do {
            try await ModalActivityIndicatorViewController.presentAndPropagateResult(
                from: fromViewController
            ) {
                guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid group model")
                }

                try await self.localAcceptInviteToGroupV2(
                    groupModel: groupModelV2,
                    waitForMessageProcessing: true
                )
            }
        } catch {
            OWSActionSheets.showActionSheet(title: OWSLocalizedString(
                "GROUPS_INVITE_ACCEPT_INVITE_FAILED",
                comment: "Error indicating that an error occurred while accepting an invite."
            ))
        }
    }
}
