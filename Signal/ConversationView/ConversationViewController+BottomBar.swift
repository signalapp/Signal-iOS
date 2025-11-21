//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

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

protocol ConversationBottomBar: UIView {
    /// Return `true` to have view controller put this bar above keyboard (using `keyboardLayoutGuide`).
    /// Return `false` to have view controller constrain bottom edge of the bar to the bottom edge of the screen.
    var shouldAttachToKeyboardLayoutGuide: Bool { get }
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
                let messageRequestType = SSKEnvironment.shared.databaseStorageRef.read { tx in
                    return MessageRequestView.messageRequestType(forThread: self.threadViewModel.threadRecord, transaction: tx)
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
            loadInputToolbarIfNeeded()
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

        bottomBarContainer.removeAllSubviews()

        if let bottomView {
            bottomView.translatesAutoresizingMaskIntoConstraints = false
            bottomBarContainer.addSubview(bottomView)
            NSLayoutConstraint.activate([
                bottomView.topAnchor.constraint(equalTo: bottomBarContainer.topAnchor),
                bottomView.leadingAnchor.constraint(equalTo: bottomBarContainer.leadingAnchor),
                bottomView.trailingAnchor.constraint(equalTo: bottomBarContainer.trailingAnchor),
            ])

            if let conversationBottomBar = bottomView as? ConversationBottomBar,
               conversationBottomBar.shouldAttachToKeyboardLayoutGuide
            {
                NSLayoutConstraint.activate([
                    bottomView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
                ])
            } else {
                NSLayoutConstraint.activate([
                    bottomView.bottomAnchor.constraint(equalTo: bottomBarContainer.bottomAnchor),
                ])
            }
        }

        updateContentInsets()
    }

    func loadInputToolbarIfNeeded() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else { return }

        guard inputToolbar == nil else { return }

        var messageDraft: MessageBody?
        var replyDraft: ThreadReplyInfo?
        var voiceMemoDraft: VoiceMessageInterruptedDraft?
        var editTarget: TSOutgoingMessage?
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            messageDraft = thread.currentDraft(transaction: transaction)
            voiceMemoDraft = VoiceMessageInterruptedDraft.currentDraft(for: thread, transaction: transaction)
            if messageDraft != nil || voiceMemoDraft != nil {
                replyDraft = DependenciesBridge.shared.threadReplyInfoStore.fetch(for: thread.uniqueId, tx: transaction)
            }
            editTarget = thread.editTarget(transaction: transaction)
        }

        let inputToolbar = buildInputToolbar(
            messageDraft: messageDraft,
            draftReply: replyDraft,
            voiceMemoDraft: voiceMemoDraft,
            editTarget: editTarget
        )

        // Obscures content underneath bottom bar to improve legibility.
        if #available(iOS 26, *) {
            let interaction = UIScrollEdgeElementContainerInteraction()
            interaction.scrollView = collectionView
            interaction.edge = .bottom
            inputToolbar.setScrollEdgeElementContainerInteraction(interaction)
        }

        self.inputToolbar = inputToolbar
    }

    func reloadDraft() {
        AssertIsOnMainThread()

        guard let messageDraft = (SSKEnvironment.shared.databaseStorageRef.read { transaction in
            self.thread.currentDraft(transaction: transaction)
        }) else {
            return
        }
        guard let inputToolbar = self.inputToolbar else {
            return
        }
        inputToolbar.setMessageBody(messageDraft, animated: false)
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

    func popKeyBoard() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }
        guard let inputToolbar = inputToolbar else {
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
        return groupThread.groupModel.groupMembership.isLocalUserRequestingMember
    }

    var userLeftGroup: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return false
        }
        return !groupThread.groupModel.groupMembership.isLocalUserFullMember
    }

    private var hasBlockingLegacyGroup: Bool {
        thread.isGroupV1Thread
    }

    private var isBlockedFromSendingByAnnouncementOnlyGroup: Bool {
        thread.isBlockedByAnnouncementOnly
    }
}
