//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

final public class BlockListUIUtils {

    public typealias Completion = (Bool) -> Void

    private init() {}

    // MARK: Block

    public static func showBlockThreadActionSheet(
        _ thread: TSThread,
        from viewController: UIViewController,
        completion: Completion?
    ) {
        if let contactThread = thread as? TSContactThread {
            showBlockAddressActionSheet(contactThread.contactAddress, from: viewController, completion: completion)
            return
        }
        if let groupThread = thread as? TSGroupThread {
            showBlockGroupActionSheet(groupThread, from: viewController, completion: completion)
            return
        }
        owsFailDebug("Unexpected thread type: \(thread.self)")
    }

    public static func showBlockAddressActionSheet(
        _ address: SignalServiceAddress,
        from viewController: UIViewController,
        completion: Completion?
    ) {
        let displayName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue() }
        showBlockAddressesActionSheet(address, displayName: displayName, from: viewController, completion: completion)
    }

    private static func showBlockAddressesActionSheet(
        _ address: SignalServiceAddress,
        displayName: String,
        from viewController: UIViewController,
        completion: Completion?
    ) {
        owsAssertDebug(address.isValid)
        owsAssertDebug(!displayName.isEmpty)

        if address.isLocalAddress {
            showOkActionSheet(
                title: OWSLocalizedString(
                    "BLOCK_LIST_VIEW_CANT_BLOCK_SELF_ALERT_TITLE",
                    comment: "The title of the 'You can't block yourself' alert."
                ),
                message: OWSLocalizedString(
                    "BLOCK_LIST_VIEW_CANT_BLOCK_SELF_ALERT_MESSAGE",
                    comment: "The message of the 'You can't block yourself' alert."
                ),
                from: viewController,
                completion: { _ in
                    completion?(false)
                }
            )
            return
        }

        let actionSheetTitle = String(
            format: OWSLocalizedString(
                "BLOCK_LIST_BLOCK_USER_TITLE_FORMAT",
                comment: "A format for the 'block user' action sheet title. Embeds {{the blocked user's name or phone number}}."
            ),
            displayName.formattedForActionSheetTitle()
        )
        let actionSheet = ActionSheetController(
            title: actionSheetTitle,
            message: OWSLocalizedString(
                "BLOCK_USER_BEHAVIOR_EXPLANATION",
                comment: "An explanation of the consequences of blocking another user."
            )
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("BLOCK_LIST_BLOCK_BUTTON", comment: "Button label for the 'block' button"),
            style: .destructive,
            handler: { _ in
                blockAddress(address, displayName: displayName, from: viewController) { _ in
                    completion?(true)
                }
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
            handler: { _ in
                completion?(false)
            }
        ))
        viewController.presentActionSheet(actionSheet)
    }

    private static func showBlockGroupActionSheet(
        _ groupThread: TSGroupThread,
        from viewController: UIViewController,
        completion: Completion?
    ) {
        let actionSheetTitle = String(
            format: OWSLocalizedString(
                "BLOCK_LIST_BLOCK_GROUP_TITLE_FORMAT",
                comment: "A format for the 'block group' action sheet title. Embeds the {{group name}}."
            ),
            groupThread.groupNameOrDefault.formattedForActionSheetTitle()
        )
        let actionSheet = ActionSheetController(
            title: actionSheetTitle,
            message: OWSLocalizedString(
                "BLOCK_GROUP_BEHAVIOR_EXPLANATION",
                comment: "An explanation of the consequences of blocking a group."
            )
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("BLOCK_LIST_BLOCK_BUTTON", comment: "Button label for the 'block' button"),
            style: .destructive,
            handler: { _ in
                blockGroup(groupThread, from: viewController) { _ in
                    completion?(true)
                }
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
            handler: { _ in
                completion?(false)
            }
        ))
        viewController.presentActionSheet(actionSheet)
    }

    private static func blockAddress(
        _ address: SignalServiceAddress,
        displayName: String,
        from viewController: UIViewController,
        completion: ((ActionSheetAction) -> Void)?
    ) {
        owsAssertDebug(!displayName.isEmpty)
        owsAssertDebug(address.isValid)

        SSKEnvironment.shared.databaseStorageRef.write { tx in
            SSKEnvironment.shared.blockingManagerRef.addBlockedAddress(address, blockMode: .localShouldLeaveGroups, transaction: tx)
        }

        showOkActionSheet(
            title: OWSLocalizedString(
                "BLOCK_LIST_VIEW_BLOCKED_ALERT_TITLE",
                comment: "The title of the 'user blocked' alert."
            ),
            message: String(
                format: OWSLocalizedString(
                    "BLOCK_LIST_VIEW_BLOCKED_ALERT_MESSAGE_FORMAT",
                    comment: "The message format of the 'conversation blocked' alert. Embeds the {{conversation title}}."
                ),
                displayName.formattedForActionSheetMessage()
            ),
            from: viewController,
            completion: completion
        )
    }

    @MainActor
    private static func blockGroup(
        _ groupThread: TSGroupThread,
        from viewController: UIViewController,
        completion: ((ActionSheetAction) -> Void)?
    ) {
        guard groupThread.isLocalUserMemberOfAnyKind else {
            blockGroupStep2(groupThread, from: viewController, completion: completion)
            return
        }

        GroupManager.leaveGroupOrDeclineInviteAsyncWithUI(
            groupThread: groupThread,
            fromViewController: viewController,
            success: {
                blockGroupStep2(groupThread, from: viewController, completion: completion)
            }
        )
    }

    private static func blockGroupStep2(
        _ groupThread: TSGroupThread,
        from viewController: UIViewController,
        completion: ((ActionSheetAction) -> Void)?
    ) {
        // block the group regardless of the ability to deliver the
        // "leave group" message.
        SSKEnvironment.shared.databaseStorageRef.write(block: { tx in
            SSKEnvironment.shared.blockingManagerRef.addBlockedGroupId(
                groupThread.groupId,
                blockMode: .localShouldLeaveGroups,
                transaction: tx
            )
        })

        let actionSheetTitle = OWSLocalizedString(
            "BLOCK_LIST_VIEW_BLOCKED_GROUP_ALERT_TITLE",
            comment: "The title of the 'group blocked' alert."
        )
        let actionSheetMessageFormat = OWSLocalizedString(
            "BLOCK_LIST_VIEW_BLOCKED_ALERT_MESSAGE_FORMAT",
            comment: "The message format of the 'conversation blocked' alert. Embeds the {{conversation title}}."
        )
        let actionSheetMessage = String(format: actionSheetMessageFormat, groupThread.groupNameOrDefault.formattedForActionSheetMessage())

        showOkActionSheet(title: actionSheetTitle, message: actionSheetMessage, from: viewController, completion: completion)
    }

    // MARK: Unblock

    public static func showUnblockThreadActionSheet(
        _ thread: TSThread,
        from viewController: UIViewController,
        completion: Completion?
    ) {
        if let contactThread = thread as? TSContactThread {
            showUnblockAddressActionSheet(contactThread.contactAddress, from: viewController, completion: completion)
            return
        }
        if let groupThread = thread as? TSGroupThread {
            showUnblockGroupActionSheet(
                groupId: groupThread.groupModel.groupId,
                groupNameOrDefault: groupThread.groupModel.groupNameOrDefault,
                from: viewController,
                completion: completion
            )
            return
        }
        owsFailDebug("unexpected thread type: \(thread.self)")
    }

    public static func showUnblockAddressActionSheet(
        _ address: SignalServiceAddress,
        from viewController: UIViewController,
        completion: Completion?
    ) {
        let displayName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue() }
        owsAssertDebug(!displayName.isEmpty)

        let actionSheetTitle = String(
            format: OWSLocalizedString(
                "BLOCK_LIST_UNBLOCK_TITLE_FORMAT",
                comment: "A format for the 'unblock conversation' action sheet title. Embeds the {{conversation title}}."
            ),
            displayName.formattedForActionSheetTitle()
        )
        let actionSheet = ActionSheetController(title: actionSheetTitle)
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("BLOCK_LIST_UNBLOCK_BUTTON", comment: "Button label for the 'unblock' button"),
            style: .destructive,
            handler: { _ in
                unblockAddress(address, displayName: displayName, from: viewController) { _ in
                    completion?(false)
                }
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
            handler: { _ in
                completion?(true)
            }
        ))
        viewController.presentActionSheet(actionSheet)
    }

    public static func showUnblockGroupActionSheet(
        groupId: Data,
        groupNameOrDefault: String,
        from viewController: UIViewController,
        completion: Completion?
    ) {
        let actionSheetTitle = OWSLocalizedString(
            "BLOCK_LIST_UNBLOCK_GROUP_TITLE",
            comment: "Action sheet title when confirming you want to unblock a group."
        )
        let actionSheetMessage = OWSLocalizedString(
            "BLOCK_LIST_UNBLOCK_GROUP_BODY",
            comment: "Action sheet body when confirming you want to unblock a group"
        )
        let actionSheet = ActionSheetController(title: actionSheetTitle, message: actionSheetMessage)
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("BLOCK_LIST_UNBLOCK_BUTTON", comment: "Button label for the 'unblock' button"),
            style: .destructive,
            handler: { _ in
                unblockGroup(groupId: groupId, groupNameOrDefault: groupNameOrDefault, from: viewController) { _ in
                    completion?(false)
                }
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
            handler: { _ in
                completion?(true)
            }
        ))
        viewController.presentActionSheet(actionSheet)
    }

    private static func unblockAddress(
        _ address: SignalServiceAddress,
        displayName: String,
        from viewController: UIViewController,
        completion: ((ActionSheetAction) -> Void)?
    ) {
        owsAssertDebug(address.isValid)
        owsAssertDebug(!displayName.isEmpty)

        SSKEnvironment.shared.databaseStorageRef.write { tx in
            SSKEnvironment.shared.blockingManagerRef.removeBlockedAddress(address, wasLocallyInitiated: true, transaction: tx)
        }

        let actionSheetTitleFormat = OWSLocalizedString(
            "BLOCK_LIST_VIEW_UNBLOCKED_ALERT_TITLE_FORMAT",
            comment: "Alert title after unblocking a group or 1:1 chat. Embeds the {{conversation title}}."
        )
        let actionSheetTitle = String(format: actionSheetTitleFormat, displayName.formattedForActionSheetTitle())
        showOkActionSheet(title: actionSheetTitle, message: nil, from: viewController, completion: completion)
    }

    private static func unblockGroup(
        groupId: Data,
        groupNameOrDefault: String,
        from viewController: UIViewController,
        completion: ((ActionSheetAction) -> Void)?
    ) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            SSKEnvironment.shared.blockingManagerRef.removeBlockedGroup(groupId: groupId, wasLocallyInitiated: true, transaction: tx)
        }

        let actionSheetTitleFormat = OWSLocalizedString(
            "BLOCK_LIST_VIEW_UNBLOCKED_ALERT_TITLE_FORMAT",
            comment: "Alert title after unblocking a group or 1:1 chat. Embeds the {{conversation title}}."
        )
        let actionSheetTitle = String(format: actionSheetTitleFormat, groupNameOrDefault.formattedForActionSheetMessage())
        let actionSheetMessage = OWSLocalizedString(
            "BLOCK_LIST_VIEW_UNBLOCKED_GROUP_ALERT_BODY",
            comment: "Alert body after unblocking a group."
        )
        showOkActionSheet(title: actionSheetTitle, message: actionSheetMessage, from: viewController, completion: completion)
    }

    // MARK: UI Utils

    private static func showOkActionSheet(
        title: String,
        message: String?,
        from viewController: UIViewController,
        completion: ((ActionSheetAction) -> Void)?
    ) {
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.okButton,
            style: .default,
            handler: completion
        ))
        viewController.presentActionSheet(actionSheet)
    }
}
