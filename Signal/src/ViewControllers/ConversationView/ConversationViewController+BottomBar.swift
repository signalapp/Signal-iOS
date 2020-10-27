//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension ConversationViewController {

    @objc
    func updateInputToolbar() {
        AssertIsOnMainThread()

        let existingDraft = inputToolbar.messageBody()

        let inputToolbar = buildInputToolbar(conversationStyle: conversationStyle)
        inputToolbar.setMessageBody(existingDraft, animated: false)
        self.inputToolbar = inputToolbar

        // reloadBottomBar is expensive and we need to avoid it while
        // initially configuring the view. viewWillAppear() will call
        // reloadBottomBar(). After viewWillAppear(), we need to call
        // reloadBottomBar() to reflect changes in the theme.
        if hasViewWillAppearOccurred {
            reloadBottomBar()
        }
    }

    @objc
    func reloadBottomBar() {
        AssertIsOnMainThread()

        let bottomView: UIView

        if let requestView = self.requestView {
            bottomView = requestView
        } else {
            switch uiMode {
            case .search:
                bottomView = searchController.resultsBar
            case .selection:
                bottomView = selectionToolbar
            case .normal:
                bottomView = inputToolbar
            }
        }

        if bottomView.superview == bottomBar && viewHasEverAppeared {
            // Do nothing, the view has not changed.
            return
        }

        for subView in bottomBar.subviews {
            subView.removeFromSuperview()
        }

        bottomBar.addSubview(bottomView)

        // The message requests view expects to extend into the safe area
        if let requestView = self.requestView {
            bottomView.autoPinEdgesToSuperviewEdges()
        } else {
            bottomView.autoPinEdgesToSuperviewMargins()
        }

        updateInputAccessoryPlaceholderHeight()
        updateContentInsets(animated: viewHasEverAppeared)
    }

    @objc
    func updateBottomBarPosition() {
        AssertIsOnMainThread()

        if let interactivePopGestureRecognizer = navigationController?.interactivePopGestureRecognizer {
            // Don't update the bottom bar position if an interactive pop is in progress
            switch interactivePopGestureRecognizer.state {
            case .possible, .failed:
                break
            default:
                return
            }
        }

        bottomBarBottomConstraint?.constant = -inputAccessoryPlaceholder.keyboardOverlap

        // We always want to apply the new bottom bar position immediately,
        // as this only happens during animations (interactive or otherwise)
        bottomBar.superview?.layoutIfNeeded()
    }

    @objc
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

    @objc
    func showMessageRequestDialogIfRequiredAsync() {
        AssertIsOnMainThread()

        DispatchQueue.main.async { [weak self] in
            self?.showMessageRequestDialogIfRequired()
        }
    }

    @objc
    func showMessageRequestDialogIfRequired() {
        AssertIsOnMainThread()

        if threadViewModel.hasPendingMessageRequest || isLocalUserRequestingMember {
            requestView?.removeFromSuperview()
            if self.isLocalUserRequestingMember {
                let memberRequestView = MemberRequestView(threadViewModel: threadViewModel,
                                                          fromViewController: self)
                memberRequestView.delegate = self
                requestView = memberRequestView
            } else {
                let messageRequestView = MessageRequestView(threadViewModel: threadViewModel)
                messageRequestView.delegate = self
                requestView = messageRequestView
            }
            reloadBottomBar()
        } else {
            if requestView != nil {
                dismissMessageRequestView()
            } else {
                reloadBottomBar()
                updateInputVisibility()
            }
        }
    }

    @objc
    func updateInputVisibility() {
        AssertIsOnMainThread()

        if viewState.isInPreviewPlatter {
            inputToolbar.isHidden = true
            dismissKeyBoard()
            return
        }

        if self.userLeftGroup {
            // user has requested they leave the group. further sends disallowed
            inputToolbar.isHidden = true
            dismissKeyBoard()
        } else {
            inputToolbar.isHidden = false
        }
    }

    @objc
    func updateInputToolbarLayout() {
        AssertIsOnMainThread()

        inputToolbar.updateLayout(withSafeAreaInsets: view.safeAreaInsets)
    }

    @objc
    func popKeyBoard() {
        AssertIsOnMainThread()

        inputToolbar.beginEditingMessage()
    }

    @objc
    func dismissKeyBoard() {
        AssertIsOnMainThread()

        inputToolbar.endEditingMessage()
        inputToolbar.clearDesiredKeyboard()
    }

    @objc
    func dismissMessageRequestView() {
        AssertIsOnMainThread()

        guard let requestView = self.requestView else {
            return
        }

        // Slide the request view off the bottom of the screen.
        let bottomInset: CGFloat = view.safeAreaInsets.bottom

        let dismissingView = requestView
        self.requestView = nil

        reloadBottomBar()
        updateInputVisibility()

        // Add the view on top of the new bottom bar (if there is one),
        // and then slide it off screen to reveal the new input view.
        view.addSubview(dismissingView)
        dismissingView.autoPinWidthToSuperview()
        dismissingView.autoPinEdge(toSuperviewEdge: .bottom)

        var endFrame = dismissingView.bounds
        endFrame.origin.y -= endFrame.size.height + bottomInset

        UIView.animate(withDuration: 0.2, delay: 0, options: []) {
            dismissingView.bounds = endFrame
        } completion: { (_) in
            dismissingView.removeFromSuperview()
        }
    }

    @objc
    var isLocalUserRequestingMember: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return false
        }
        return groupThread.isLocalUserRequestingMember
    }

    @objc
    var userLeftGroup: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return false
        }
        return !groupThread.isLocalUserFullMember
    }
}
