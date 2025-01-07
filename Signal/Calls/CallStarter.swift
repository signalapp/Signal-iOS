//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalUI
import SignalServiceKit
import SignalRingRTC

/// A type that allows calls to be started with a given recipient after various
/// checks are performed. See ``startCall(from:)`` for details of those checks.
struct CallStarter {
    private enum Recipient {
        case contactThread(TSContactThread, withVideo: Bool)
        case groupThread(GroupIdentifier)
        case callLink(CallLinkRootKey)
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
        self.recipient = .contactThread(contactThread, withVideo: withVideo)
        self.context = context
    }

    init(groupId: GroupIdentifier, context: Context) {
        self.recipient = .groupThread(groupId)
        self.context = context
    }

    init(callLink: CallLinkRootKey, context: Context) {
        self.recipient = .callLink(callLink)
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
        let callThread: TSThread?
        let isVideoCall: Bool
        switch recipient {
        case .contactThread(let thread, let withVideo):
            callTarget = .individual(thread)
            callThread = thread
            isVideoCall = withVideo
        case .groupThread(let groupId):
            callTarget = .groupThread(groupId)
            callThread = context.databaseStorage.read { tx in TSGroupThread.fetch(forGroupId: groupId, tx: tx)! }
            isVideoCall = true
        case .callLink(let rootKey):
            callTarget = .callLink(CallLink(rootKey: rootKey))
            callThread = nil
            isVideoCall = true
        }

        if let callThread {
            let threadIsBlocked = context.databaseStorage.read { tx in
                return context.blockingManager.isThreadBlocked(callThread, transaction: tx)
            }
            if threadIsBlocked {
                BlockListUIUtils.showUnblockThreadActionSheet(callThread, from: viewController, completion: nil)
                return .promptedToUnblock
            }
        }

        if let currentCall = context.callService.callServiceState.currentCall, currentCall.mode.matches(callTarget) {
            AppEnvironment.shared.windowManagerRef.returnToCallView()
            return .callStarted
        }

        if let thread = callThread as? TSGroupThread, thread.isBlockedByAnnouncementOnly {
            Self.showBlockedByAnnouncementOnlySheet(from: viewController)
            return .callNotStarted
        }

        if let thread = callThread {
            let canCall = {
                switch thread {
                case let thread as TSContactThread: return thread.canCall
                case let thread as TSGroupThread: return thread.canCall
                default: return false
                }
            }()
            guard canCall else {
                owsFailDebug("Shouldn't be able to startCall if canCall is false")
                return .callNotStarted
            }
            self.whitelistThread(thread)
        }

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
    static func prepareToStartCall(from viewController: UIViewController, shouldAskForCameraPermission: Bool) async -> Bool {
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            Logger.warn("Can't start a call unless you're registered")
            OWSActionSheets.showActionSheet(title: OWSLocalizedString(
                "YOU_MUST_COMPLETE_ONBOARDING_BEFORE_PROCEEDING",
                comment: "alert body shown when trying to use features in the app before completing registration-related setup."
            ))
            return false
        }

        guard await viewController.askForMicrophonePermissions() else {
            Logger.warn("aborting due to missing microphone permissions.")
            viewController.ows_showNoMicrophonePermissionActionSheet()
            return false
        }

        if shouldAskForCameraPermission {
            guard await viewController.askForCameraPermissions() else {
                Logger.warn("aborting due to missing camera permissions.")
                return false
            }
        }

        return true
    }
}
