//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

public extension ConversationViewController {

    var isCurrentCallForThread: Bool {
        switch AppEnvironment.shared.callService.callServiceState.currentCall?.mode {
        case nil:
            return false
        case .individual(let call):
            return call.thread.uniqueId == thread.uniqueId
        case .groupThread(let call):
            return call.groupId.serialize().asData == (thread as? TSGroupThread)?.groupId
        case .callLink:
            return false
        }
    }

    var isCallingSupported: Bool {
        canCall
    }

    var canCall: Bool {
        ConversationViewController.canCall(threadViewModel: threadViewModel)
    }

    private var callStarterContext: CallStarter.Context {
        .init(
            blockingManager: SSKEnvironment.shared.blockingManagerRef,
            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
            callService: AppEnvironment.shared.callService
        )
    }

    @objc
    func showGroupLobbyOrActiveCall() {
        guard let groupId = try? (thread as? TSGroupThread)?.groupIdentifier else {
            owsFailDebug("Tried to present group call for non-group thread.")
            return
        }

        let startCallResult = CallStarter(
            groupId: groupId,
            context: self.callStarterContext
        ).startCall(from: self)

        if startCallResult.callDidStartOrResume {
            removeGroupCallTooltip()
        }
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

        let startCallResult = CallStarter(
            contactThread: contactThread,
            withVideo: withVideo,
            context: self.callStarterContext
        ).startCall(from: self)

        switch startCallResult {
        case .callStarted:
            NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
        case .callNotStarted:
            break
        case .promptedToUnblock:
            self.userHasScrolled = false
        }

    }

    func refreshCallState() {
        if let groupId = try? (thread as? TSGroupThread)?.groupIdentifier {
            Task {
                await SSKEnvironment.shared.groupCallManagerRef.peekGroupCallAndUpdateThread(
                    forGroupId: groupId,
                    peekTrigger: .localEvent()
                )
            }
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
            SSKEnvironment.shared.preferencesRef.incrementGroupCallTooltipShownCount()
            viewState.didAlreadyShowGroupCallTooltipEnoughTimes = SSKEnvironment.shared.databaseStorageRef.read { tx in
                SSKEnvironment.shared.preferencesRef.wasGroupCallTooltipShown(withTransaction: tx)
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
