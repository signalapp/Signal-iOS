//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

public extension ConversationViewController {

    var isCurrentCallForThread: Bool {
        thread.uniqueId == callService.currentCall?.thread.uniqueId
    }

    var isCallingSupported: Bool {
        canCall
    }

    var canCall: Bool {
        ConversationViewController.canCall(threadViewModel: threadViewModel)
    }

    @objc
    func showGroupLobbyOrActiveCall() {
        if isCurrentCallForThread {
            WindowManager.shared.returnToCallView()
            return
        }

        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Tried to present group call for non-group thread.")
            return
        }

        guard canCall else {
            owsFailDebug("Tried to initiate a call but thread is not callable.")
            return
        }

        if thread.isBlockedByAnnouncementOnly {
            OWSActionSheets.showActionSheet(
                title: OWSLocalizedString("GROUP_CALL_BLOCKED_BY_ANNOUNCEMENT_ONLY_TITLE",
                                           comment: "Title for error alert indicating that only group administrators can start calls in announcement-only groups."),
                message: OWSLocalizedString("GROUP_CALL_BLOCKED_BY_ANNOUNCEMENT_ONLY_MESSAGE",
                                         comment: "Message for error alert indicating that only group administrators can start calls in announcement-only groups.")
            )
            return
        }

        removeGroupCallTooltip()

        // We initiated a call, so if there was a pending message request we should accept it.
        ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(thread: thread)

        GroupCallViewController.presentLobby(thread: groupThread)
    }

    @objc
    func startIndividualAudioCall() {
        startIndividualCall(withVideo: false)
    }

    @objc
    func startIndividualVideoCall() {
        startIndividualCall(withVideo: true)
    }

    func startIndividualCall(withVideo: Bool) {
        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Invalid thread.")
            return
        }

        guard canCall else {
            Logger.warn("Tried to initiate a call but thread is not callable.")
            return
        }

        if isBlockedConversation() {
            showUnblockConversationUI { [weak self] isBlocked in
                guard let self = self else { return }
                if !isBlocked {
                    self.startIndividualCall(withVideo: withVideo)
                }
            }
            return
        }

        let didShowSNAlert = self.showSafetyNumberConfirmationIfNecessary(confirmationText: CallStrings.confirmAndCallButtonTitle,
                                                                          completion: { [weak self] didConfirmIdentity in
                                                                            if didConfirmIdentity {
                                                                                self?.startIndividualCall(withVideo: withVideo)
                                                                            }
                                                                          })
        if didShowSNAlert {
            return
        }

        // We initiated a call, so if there was a pending message request we should accept it.
        ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(thread: thread)

        callService.initiateCall(thread: contactThread, isVideo: withVideo)
        NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
    }

    func refreshCallState() {
        if let groupThread = thread as? TSGroupThread {
            callService.peekCallAndUpdateThread(groupThread)
        }
    }

    // MARK: - Group Call Tooltip

    func showGroupCallTooltipIfNecessary() {
        removeGroupCallTooltip()

        guard canCall, isGroupConversation else {
            return
        }
        if viewState.didAlreadyShowGroupCallTooltipEnoughTimes {
            return
        }

        // We only want to increment once per CVC lifecycle, since
        // we may tear down and rebuild the tooltip multiple times
        // as the navbar items change.
        if !hasIncrementedGroupCallTooltipShownCount {
            preferences.incrementGroupCallTooltipShownCount()
            viewState.didAlreadyShowGroupCallTooltipEnoughTimes = databaseStorage.read { tx in
                preferences.wasGroupCallTooltipShown(with: tx)
            }
            hasIncrementedGroupCallTooltipShownCount = true
        }

        if conversationViewModel.groupCallInProgress {
            return
        }

        let tailReferenceView = UIView()
        tailReferenceView.isUserInteractionEnabled = false
        view.addSubview(tailReferenceView)
        self.groupCallTooltipTailReferenceView = tailReferenceView

        let tooltip = GroupCallTooltip.present(fromView: self.view,
                                               widthReferenceView: self.view,
                                               tailReferenceView: tailReferenceView) { [weak self] in
            self?.showGroupLobbyOrActiveCall()
        }
        self.groupCallTooltip = tooltip

        // This delay is unfortunate, but the bar button item is not always
        // ready to use as a position reference right away after it is set
        // on the navigation item. So we wait a short amount of time for it
        // to hopefully be ready since there's unfortunately not a simple
        // way to monitor when the navigation bar layout has finished (without
        // subclassing navigation bar). Since the stakes are low here (the
        // tooltip just won't be visible), it's not worth doing that for.

        tooltip.isHidden = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.positionGroupCallTooltip()
        }
    }

    func positionGroupCallTooltip() {
        guard let groupCallTooltipTailReferenceView = self.groupCallTooltipTailReferenceView,
              let groupCallBarButtonItem = self.groupCallBarButtonItem else {
            return
        }
        guard let barButtonView = groupCallBarButtonItem.value(forKey: "view") as? UIView else {
            return
        }
        groupCallTooltipTailReferenceView.frame = view.convert(barButtonView.frame,
                                                               from: barButtonView.superview)
        groupCallTooltip?.isHidden = false
    }

    private func removeGroupCallTooltip() {
        groupCallTooltip?.removeFromSuperview()
        self.groupCallTooltip = nil
        groupCallTooltipTailReferenceView?.removeFromSuperview()
        self.groupCallTooltipTailReferenceView = nil
    }

    private var groupCallTooltip: GroupCallTooltip? {
        get { viewState.groupCallTooltip }
        set { viewState.groupCallTooltip = newValue }
    }

    private var groupCallTooltipTailReferenceView: UIView? {
        get { viewState.groupCallTooltipTailReferenceView }
        set { viewState.groupCallTooltipTailReferenceView = newValue }
    }

    private var hasIncrementedGroupCallTooltipShownCount: Bool {
        get { viewState.hasIncrementedGroupCallTooltipShownCount }
        set { viewState.hasIncrementedGroupCallTooltipShownCount = newValue }
    }
}
