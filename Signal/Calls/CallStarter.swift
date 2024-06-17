//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
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
        let callTarget: CallTarget
        let callThread: TSThread
        let isVideoCall: Bool
        switch recipient {
        case .contact(let thread, let withVideo):
            callTarget = .individual(thread)
            callThread = thread
            isVideoCall = withVideo
        case .group(let thread):
            callTarget = .groupThread(thread)
            callThread = thread
            isVideoCall = true
        }

        let threadIsBlocked = context.databaseStorage.read { tx in
            return context.blockingManager.isThreadBlocked(callThread, transaction: tx)
        }
        if threadIsBlocked {
            BlockListUIUtils.showUnblockThreadActionSheet(callThread, from: viewController, completion: nil)
            return .promptedToUnblock
        }

        if let currentCall = context.callService.callServiceState.currentCall, currentCall.mode.matches(callTarget) {
            WindowManager.shared.returnToCallView()
            return .callStarted
        }

        switch callTarget {
        case .individual(let thread):
            guard thread.canCall else {
                owsFailDebug("Shouldn't be able to startCall if canCall is false")
                return .callNotStarted
            }
        case .groupThread(let thread):
            guard !thread.isBlockedByAnnouncementOnly else {
                Self.showBlockedByAnnouncementOnlySheet(from: viewController)
                return .callNotStarted
            }
            guard thread.canCall else {
                return .callNotStarted
            }
        case .callLink:
            owsFail("Not supported.")
        }
        self.whitelistThread(callThread)
        context.callService.initiateCall(to: callTarget, isVideo: isVideoCall)
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

    @MainActor
    static func prepareToStartCall(shouldAskForCameraPermission: Bool) async -> UIViewController? {
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            Logger.warn("Can't start a call unless you're registered")
            OWSActionSheets.showActionSheet(title: OWSLocalizedString(
                "YOU_MUST_COMPLETE_ONBOARDING_BEFORE_PROCEEDING",
                comment: "alert body shown when trying to use features in the app before completing registration-related setup."
            ))
            return nil
        }

        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFail("Can't start a call if there's no view controller")
        }

        guard await frontmostViewController.askForMicrophonePermissions() else {
            Logger.warn("aborting due to missing microphone permissions.")
            frontmostViewController.ows_showNoMicrophonePermissionActionSheet()
            return nil
        }

        if shouldAskForCameraPermission {
            guard await frontmostViewController.askForCameraPermissions() else {
                Logger.warn("aborting due to missing camera permissions.")
                return nil
            }
        }

        return frontmostViewController
    }
}
