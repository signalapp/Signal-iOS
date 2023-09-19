//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

enum CVCBottomViewType: Equatable {
    // For perf reasons, we don't use a bottom view until
    // the view is about to appear for the first time.
    case none
    case inputToolbar
    case memberRequestView
    case messageRequestView(messageRequestType: MessageRequestType)
    case search
    case selection
    case blockingLegacyGroup
    case announcementOnlyGroup
}

// MARK: -

public extension ConversationViewController {

    internal var bottomViewType: CVCBottomViewType {
        get { viewState.bottomViewType }
        set {
            // For perf reasons, we avoid adding any "bottom view"
            // to the view hierarchy until its necessary, e.g. when
            // the view is about to appear.
            owsAssertDebug(hasViewWillAppearEverBegun)

            if viewState.bottomViewType != newValue {
                if viewState.bottomViewType == .inputToolbar {
                    // Dismiss the keyboard if we're swapping out the input toolbar
                    dismissKeyBoard()
                }
                viewState.bottomViewType = newValue
                updateBottomBar()
            }
        }
    }

    func ensureBottomViewType() {
        AssertIsOnMainThread()

        guard viewState.selectionAnimationState == .idle else {
            return
        }

        bottomViewType = { () -> CVCBottomViewType in
            // The ordering of this method determines
            // precedence of the bottom views.

            if !hasViewWillAppearEverBegun {
                return .none
            } else if threadViewModel.hasPendingMessageRequest {
                let messageRequestType = Self.databaseStorage.read { transaction in
                    MessageRequestView.messageRequestType(forThread: self.threadViewModel.threadRecord,
                                                          transaction: transaction)
                }
                return .messageRequestView(messageRequestType: messageRequestType)
            } else if isLocalUserRequestingMember {
                return .memberRequestView
            } else if hasBlockingLegacyGroup {
                return .blockingLegacyGroup
            } else if isBlockedFromSendingByAnnouncementOnlyGroup {
                return .announcementOnlyGroup
            } else {
                switch uiMode {
                case .search:
                    return .search
                case .selection:
                    return .selection
                case .normal:
                    if viewState.isInPreviewPlatter || userLeftGroup {
                        return .none
                    } else {
                        return .inputToolbar
                    }
                }
            }
        }()
    }

    private func updateBottomBar() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            return
        }

        // Animate the dismissal of any existing request view.
        dismissRequestView()

        requestView?.removeFromSuperview()
        requestView = nil

        let bottomView: UIView?
        switch bottomViewType {
        case .none:
            bottomView = nil
        case .messageRequestView:
            let messageRequestView = MessageRequestView(threadViewModel: threadViewModel)
            messageRequestView.delegate = self
            requestView = messageRequestView
            bottomView = messageRequestView
        case .memberRequestView:
            let memberRequestView = MemberRequestView(threadViewModel: threadViewModel,
                                                      fromViewController: self)
            memberRequestView.delegate = self
            requestView = memberRequestView
            bottomView = memberRequestView
        case .search:
            bottomView = searchController.resultsBar
        case .selection:
            bottomView = selectionToolbar
        case .inputToolbar:
            bottomView = inputToolbar
        case .blockingLegacyGroup:
            let legacyGroupView = BlockingLegacyGroupView(fromViewController: self)
            requestView = legacyGroupView
            bottomView = legacyGroupView
        case .announcementOnlyGroup:
            let announcementOnlyView = BlockingAnnouncementOnlyView(threadViewModel: threadViewModel,
                                                                    fromViewController: self)
            requestView = announcementOnlyView
            bottomView = announcementOnlyView
        }

        bottomBar.removeAllSubviews()

        if let bottomView {
            bottomBar.addSubview(bottomView)
            bottomView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
            if bottomView is UIToolbar {
                // UIToolbar will extend its background to cover bottom safe area. 
                bottomView.autoPinEdge(toSuperviewSafeArea: .bottom)
            } else {
                bottomView.autoPinEdge(toSuperviewEdge: .bottom)
            }
        }

        updateInputAccessoryPlaceholderHeight()
        updateBottomBarPosition()
        updateContentInsets()
    }

    // This is expensive. We only need to do it if conversationStyle has changed.
    //
    // TODO: Once conversationStyle is immutable, compare the old and new
    //       conversationStyle values and exit early if it hasn't changed.
    func updateInputToolbar() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            return
        }

        var messageDraft: MessageBody?
        var replyDraft: ThreadReplyInfo?
        var voiceMemoDraft: VoiceMessageInterruptedDraft?
        var editTarget: TSOutgoingMessage?
        if let oldInputToolbar = self.inputToolbar {
            // Maintain draft continuity.
            messageDraft = oldInputToolbar.messageBodyForSending
            replyDraft = oldInputToolbar.draftReply
            editTarget = oldInputToolbar.editTarget
            voiceMemoDraft = oldInputToolbar.voiceMemoDraft
        } else {
            Self.databaseStorage.read { transaction in
                messageDraft = self.thread.currentDraft(transaction: transaction)
                voiceMemoDraft = VoiceMessageInterruptedDraft.currentDraft(for: self.thread, transaction: transaction)
                if messageDraft != nil || voiceMemoDraft != nil {
                    replyDraft = DependenciesBridge.shared.threadReplyInfoStore.fetch(for: self.thread.uniqueId, tx: transaction.asV2Read)
                }
                editTarget = self.thread.editTarget(transaction: transaction)
            }
        }

        let newInputToolbar = buildInputToolbar(
            conversationStyle: conversationStyle,
            messageDraft: messageDraft,
            draftReply: replyDraft,
            voiceMemoDraft: voiceMemoDraft,
            editTarget: editTarget
        )

        let hadFocus = self.inputToolbar?.isInputViewFirstResponder ?? false
        self.inputToolbar = newInputToolbar

        if hadFocus {
            self.inputToolbar?.beginEditingMessage()
        }
        newInputToolbar.updateFontSizes()

        updateBottomBar()
    }

    func reloadDraft() {
        AssertIsOnMainThread()

        guard let messageDraft = (Self.databaseStorage.read { transaction in
            self.thread.currentDraft(transaction: transaction)
        }) else {
            return
        }
        guard let inputToolbar = self.inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }
        inputToolbar.setMessageBody(messageDraft, animated: false)
    }

    func updateBottomBarPosition() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            return
        }

        guard !isSwitchingKeyboard else { return }

        if let interactivePopGestureRecognizer = navigationController?.interactivePopGestureRecognizer {
            // Don't update the bottom bar position if an interactive pop is in progress
            switch interactivePopGestureRecognizer.state {
            case .possible, .failed:
                break
            default:
                return
            }
        }

        guard let bottomBarBottomConstraint = bottomBarBottomConstraint,
              let bottomBarSuperview = bottomBar.superview else {
            return
        }
        let bottomBarPosition = -inputAccessoryPlaceholder.keyboardOverlap
        let didChange = bottomBarBottomConstraint.constant != bottomBarPosition
        guard didChange else {
            return
        }
        bottomBarBottomConstraint.constant = bottomBarPosition

        // We always want to apply the new bottom bar position immediately,
        // as this only happens during animations (interactive or otherwise)
        bottomBarSuperview.layoutIfNeeded()
    }

    func updateInputAccessoryPlaceholderHeight() {
        AssertIsOnMainThread()

        // If we're currently dismissing interactively, skip updating the
        // input accessory height. Changing it while dismissing can lead to
        // an infinite loop of keyboard frame changes as the listeners in
        // InputAcessoryViewPlaceholder will end up calling back here if
        // a dismissal is in progress.
        if isDismissingInteractively {
            return
        }

        // Apply any pending layout changes to ensure we're measuring the up-to-date height.
        bottomBar.superview?.layoutIfNeeded()

        inputAccessoryPlaceholder.desiredHeight = bottomBar.height
    }

    // MARK: - Message Request

    func showMessageRequestDialogIfRequiredAsync() {
        AssertIsOnMainThread()

        DispatchQueue.main.async { [weak self] in
            self?.showMessageRequestDialogIfRequired()
        }
    }

    func showMessageRequestDialogIfRequired() {
        AssertIsOnMainThread()

        ensureBottomViewType()
    }

    func updateInputToolbarLayout() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            return
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        if inputToolbar.updateLayout(withSafeAreaInsets: view.safeAreaInsets) {
            // Ensure that if the toolbar has its insets changed, we trigger a re-layout.
            // Without this, UIKit does a bad job of picking up the final safe area for
            // constraints on the toolbar on its own.
            self.view.setNeedsLayout()
            self.updateContentInsets()
        }
    }

    func popKeyBoard() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        inputToolbar.beginEditingMessage()
    }

    func dismissKeyBoard() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }

        guard viewState.selectionAnimationState == .idle else {
            return
        }

        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        inputToolbar.endEditingMessage()
        inputToolbar.clearDesiredKeyboard()
    }

    private func dismissRequestView() {
        AssertIsOnMainThread()

        guard let requestView else {
            return
        }

        self.requestView = nil

        // Slide the request view off the bottom of the screen.
        // Add the view on top of the new bottom bar (if there is one),
        // and then slide it off screen to reveal the new input view.
        view.addSubview(requestView)
        requestView.autoPinWidthToSuperview()
        requestView.autoPinEdge(toSuperviewEdge: .bottom)

        let bottomInset: CGFloat = view.safeAreaInsets.bottom
        var endFrame = requestView.bounds
        endFrame.origin.y -= endFrame.size.height + bottomInset

        UIView.animate(withDuration: 0.2, delay: 0, options: []) {
            requestView.bounds = endFrame
        } completion: { (_) in
            requestView.removeFromSuperview()
        }
    }

    private var isLocalUserRequestingMember: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return false
        }
        return groupThread.isLocalUserRequestingMember
    }

    var userLeftGroup: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return false
        }
        return !groupThread.isLocalUserFullMember
    }

    private var hasBlockingLegacyGroup: Bool {
        thread.isGroupV1Thread
    }

    private var isBlockedFromSendingByAnnouncementOnlyGroup: Bool {
        thread.isBlockedByAnnouncementOnly
    }
}
