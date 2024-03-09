//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalMessaging
import SignalServiceKit

/// A type that allows calls to be started with a given recipient after various
/// checks are performed. See ``startCall(from:)`` for details of those checks.
struct CallStarter {
    private enum Recipient {
        case contact(thread: TSContactThread, withVideo: Bool)
        case group(thread: TSGroupThread)

        var thread: TSThread {
            switch self {
            case let .contact(thread, _):
                return thread
            case let .group(thread):
                return thread
            }
        }
    }

    enum StartCallResult {
        /// A new call was started, or an ongoing call was returned to.
        case callStarted
        /// A call was not started for a reason other than the recipient being blocked.
        case callNotStarted
        /// A sheet was presented, prompting to unblock the recipient.
        case promptedToUnblock

        var callDidStartOrResume: Bool {
            switch self {
            case .callStarted:
                return true
            case .promptedToUnblock, .callNotStarted:
                return false
            }
        }
    }

    struct Context {
        var blockingManager: BlockingManager
        var databaseStorage: SDSDatabaseStorage
        var callService: CallService
    }

    private var recipient: Recipient
    private var context: Context

    init(contactThread: TSContactThread, withVideo: Bool, context: Context) {
        self.recipient = .contact(thread: contactThread, withVideo: withVideo)
        self.context = context
    }

    init(groupThread: TSGroupThread, context: Context) {
        self.recipient = .group(thread: groupThread)
        self.context = context
    }

    /// Attempts to start a call, if the conditions to start a call are met. If
    /// a call with `recipient` is already ongoing, it returns to that call.
    ///
    /// The checks and actions performed before starting a call:
    /// - Show unblock sheet if attempting to call a thread you have blocked
    /// - If a call with the recipient is ongoing, open that
    /// - Don't allow calls to Note to Self
    /// - Don't allow calls to announcement-only group chats
    /// - Only allow calls to V2 groups where you are a full member
    ///
    /// - Parameter viewController: A presenting view controller.
    /// If the conversation is blocked or the user cannot call the recipient,
    /// this is used to present an unblock sheet or error message.
    /// - Returns: A result of the attempt to start a call.
    /// See ``StartCallResult``.
    @discardableResult
    func startCall(from viewController: UIViewController) -> StartCallResult {
        let threadIsBlocked = context.databaseStorage.read { tx in
            context.blockingManager.isThreadBlocked(
                recipient.thread,
                transaction: tx
            )
        }

        if threadIsBlocked {
            BlockListUIUtils.showUnblockThreadActionSheet(recipient.thread, from: viewController, completion: nil)
            return .promptedToUnblock
        }

        switch recipient {
        case let .contact(thread, withVideo):
            if thread.uniqueId == context.callService.currentCall?.thread.uniqueId {
                WindowManager.shared.returnToCallView()
                return .callStarted
            }

            guard !thread.isNoteToSelf else {
                owsFailDebug("Shouldn't be able to start call with Note to Self")
                return .callNotStarted
            }
            self.whitelistThread(thread)
            context.callService.initiateCall(thread: thread, isVideo: withVideo)
        case let .group(thread):
            guard !thread.isBlockedByAnnouncementOnly else {
                Self.showBlockedByAnnouncementOnlySheet(from: viewController)
                return .callNotStarted
            }
            guard
                thread.groupMembership.isLocalUserFullMember,
                thread.isGroupV2Thread
            else {
                return .callNotStarted
            }
            self.whitelistThread(thread)
            GroupCallViewController.presentLobby(thread: thread)
        }
        return .callStarted
    }

    private func whitelistThread(_ thread: TSThread) {
        ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(thread)
    }

    static func showBlockedByAnnouncementOnlySheet(from viewController: UIViewController) {
        OWSActionSheets.showActionSheet(
            title: OWSLocalizedString(
                "GROUP_CALL_BLOCKED_BY_ANNOUNCEMENT_ONLY_TITLE",
                comment: "Title for error alert indicating that only group administrators can start calls in announcement-only groups."
            ),
            message: OWSLocalizedString(
                "GROUP_CALL_BLOCKED_BY_ANNOUNCEMENT_ONLY_MESSAGE",
                comment: "Message for error alert indicating that only group administrators can start calls in announcement-only groups."
            ),
            fromViewController: viewController
        )
    }
}
