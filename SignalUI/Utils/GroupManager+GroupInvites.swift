//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
public import SignalServiceKit

public extension GroupManager {

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
            canCancel: false
        ) { modalView in
            firstly(on: DispatchQueue.global()) {
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    self.localLeaveGroupOrDeclineInvite(
                        groupThread: groupThread,
                        replacementAdminAci: replacementAdminAci,
                        waitForMessageProcessing: true,
                        tx: transaction
                    ).asVoid()
                }
            }.done(on: DispatchQueue.main) { _ in
                modalView.dismiss {
                    success?()
                }
            }.catch { error in
                owsFailDebug("Leave group failed: \(error)")
                modalView.dismiss {
                    OWSActionSheets.showActionSheet(
                        title: OWSLocalizedString(
                            "LEAVE_GROUP_FAILED",
                            comment: "Error indicating that a group could not be left."
                        )
                    )
                }
            }
        }
    }

    @MainActor
    static func acceptGroupInviteWithModal(
        _ groupThread: TSGroupThread,
        fromViewController: UIViewController
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            ModalActivityIndicatorViewController.present(
                fromViewController: fromViewController,
                canCancel: false,
                asyncBlock: { modalActivityIndicator in
                    do {
                        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
                            throw OWSAssertionError("Invalid group model")
                        }

                        try await self.localAcceptInviteToGroupV2(
                            groupModel: groupModelV2,
                            waitForMessageProcessing: true
                        )

                        modalActivityIndicator.dismiss {
                            continuation.resume()
                        }
                    } catch {
                        modalActivityIndicator.dismiss {
                            let title = OWSLocalizedString(
                                "GROUPS_INVITE_ACCEPT_INVITE_FAILED",
                                comment: "Error indicating that an error occurred while accepting an invite."
                            )

                            OWSActionSheets.showActionSheet(title: title)

                            continuation.resume(throwing: error)
                        }
                    }
                }
            )
        }
    }
}
