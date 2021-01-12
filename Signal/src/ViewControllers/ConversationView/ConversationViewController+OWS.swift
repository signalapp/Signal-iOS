//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

extension ConversationViewController {

    @objc
    public func renderItem(forIndex index: NSInteger) -> CVRenderItem? {
        guard index >= 0, index < renderItems.count else {
            owsFailDebug("Invalid view item index: \(index)")
            return nil
        }
        return renderItems[index]
    }

    var renderState: CVRenderState {
        AssertIsOnMainThread()

        return loadCoordinator.renderState
    }

    @objc
    public var renderItems: [CVRenderItem] {
        AssertIsOnMainThread()

        return loadCoordinator.renderItems
    }

    @objc
    public var allIndexPaths: [IndexPath] {
        AssertIsOnMainThread()

        return loadCoordinator.allIndexPaths
    }

    @objc
    func ensureIndexPath(of interaction: TSMessage) -> IndexPath? {
        // CVC TODO: This is incomplete.
        self.indexPath(forInteractionUniqueId: interaction.uniqueId)
    }

    @objc
    func clearThreadUnreadFlagIfNecessary() {
        if thread.isMarkedUnread {
            self.databaseStorage.write { transaction in
                self.thread.clearMarkedAsUnread(updateStorageService: true, transaction: transaction)
            }
        }
    }

    @objc(canCallThreadViewModel:)
    public static func canCall(threadViewModel: ThreadViewModel) -> Bool {
        let thread = threadViewModel.threadRecord
        guard thread.isLocalUserFullMemberOfThread else {
            return false
        }
        guard !threadViewModel.hasPendingMessageRequest else {
            return false
        }
        guard let contactThread = thread as? TSContactThread else {
            return RemoteConfig.groupCalling && thread.isGroupV2Thread
        }
        guard !contactThread.isNoteToSelf else {
            return false
        }
        return true
    }

    // MARK: -

    @objc(updateContentInsetsAnimated:)
    public func updateContentInsets(animated: Bool) {
        AssertIsOnMainThread()

        guard !isMeasuringKeyboardHeight else {
            return
        }

        // Don't update the content insets if an interactive pop is in progress
        guard let navigationController = self.navigationController else {
            return
        }
        if let interactivePopGestureRecognizer = navigationController.interactivePopGestureRecognizer {
            switch interactivePopGestureRecognizer.state {
            case .possible, .failed:
                break
            default:
                return
            }
        }

        view.layoutIfNeeded()

        let oldInsets = collectionView.contentInset
        var newInsets = oldInsets

        let keyboardOverlap = inputAccessoryPlaceholder.keyboardOverlap
        newInsets.bottom = (messageActionsExtraContentInsetPadding +
                                keyboardOverlap +
                                bottomBar.height -
                                view.safeAreaInsets.bottom)
        newInsets.top = messageActionsExtraContentInsetPadding + (bannerView?.height ?? 0)

        let wasScrolledToBottom = self.isScrolledToBottom

        // Changing the contentInset can change the contentOffset, so make sure we
        // stash the current value before making any changes.
        let oldYOffset = collectionView.contentOffset.y

        let didChangeInsets = oldInsets != newInsets

        UIView.performWithoutAnimation {
            if didChangeInsets {
                self.collectionView.contentInset = newInsets
            }
            self.collectionView.scrollIndicatorInsets = newInsets
        }

        // Adjust content offset to prevent the presented keyboard from obscuring content.
        if !didChangeInsets {
            // Do nothing.
            //
            // If content inset didn't change, no need to update content offset.
        } else if !hasAppearedAndHasAppliedFirstLoad {
            // Do nothing.
        } else if wasScrolledToBottom {
            // If we were scrolled to the bottom, don't do any fancy math. Just stay at the bottom.
            scrollToBottomOfLoadWindow(animated: false)
        } else if isViewCompletelyAppeared {
            // If we were scrolled away from the bottom, shift the content in lockstep with the
            // keyboard, up to the limits of the content bounds.
            let insetChange = newInsets.bottom - oldInsets.bottom

            // Only update the content offset if the inset has changed.
            if insetChange != 0 {
                // The content offset can go negative, up to the size of the top layout guide.
                // This accounts for the extended layout under the navigation bar.
                owsAssertDebug(topLayoutGuide.length == view.safeAreaInsets.top)
                let minYOffset = -view.safeAreaInsets.top
                let newYOffset = (oldYOffset + insetChange).clamp(minYOffset, safeContentHeight)
                let newOffset = CGPoint(x: 0, y: newYOffset)

                UIView.performWithoutAnimation {
                    collectionView.setContentOffset(newOffset, animated: false)
                }
            }
        }
    }
}

// MARK: - ForwardMessageDelegate

extension ConversationViewController: ForwardMessageDelegate {
    public func forwardMessageFlowDidComplete(itemViewModel: CVItemViewModelImpl, threads: [TSThread]) {
        self.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }

            guard let thread = threads.first,
                  thread.uniqueId != self.thread.uniqueId else {
                return
            }

            SignalApp.shared().presentConversation(for: thread, animated: true)
        }
    }

    public func forwardMessageFlowDidCancel() {
        self.dismiss(animated: true)
    }
}

// MARK: -

extension ConversationViewController {

    // A message can be remotely deleted iff:
    //  * the feature flag is enabled
    //  * you sent this message
    //  * you haven't already remotely deleted this message
    //  * it has been less than 3 hours since you sent the message
    func canBeRemotelyDeleted(item: CVItemViewModel) -> Bool {
        guard let outgoingMessage = item.interaction as? TSOutgoingMessage else { return false }
        guard !outgoingMessage.wasRemotelyDeleted else { return false }
        guard Date.ows_millisecondTimestamp() - outgoingMessage.timestamp <= (kHourInMs * 3) else { return false }

        return true
    }

    func showDeleteForEveryoneConfirmationIfNecessary(completion: @escaping () -> Void) {
        guard !Environment.shared.preferences.wasDeleteForEveryoneConfirmationShown() else { return completion() }

        OWSActionSheets.showConfirmationAlert(
            title: NSLocalizedString(
                "MESSAGE_ACTION_DELETE_FOR_EVERYONE_CONFIRMATION",
                comment: "A one-time confirmation that you want to delete for everyone"
            ),
            proceedTitle: NSLocalizedString(
                "MESSAGE_ACTION_DELETE_FOR_EVERYONE",
                comment: "The title for the action that deletes a message for all users in the conversation."
            ),
            proceedStyle: .destructive) { _ in
            Environment.shared.preferences.setWasDeleteForEveryoneConfirmationShown()
            completion()
        }
    }
}

// MARK: - MessageActionsToolbarDelegate

extension ConversationViewController: MessageActionsToolbarDelegate {
    public func messageActionsToolbar(_ messageActionsToolbar: MessageActionsToolbar, executedAction: MessageAction) {
        executedAction.block(messageActionsToolbar)
    }
}

// MARK: -

extension ConversationViewController: GroupViewHelperDelegate {
    func groupViewHelperDidUpdateGroup() {
        // Do nothing.
    }

    var currentGroupModel: TSGroupModel? {
        guard let groupThread = self.thread as? TSGroupThread else {
            return nil
        }
        return groupThread.groupModel
    }

    var fromViewController: UIViewController? {
        return self
    }
}

// MARK: - UIMode

extension ConversationViewController {
    @objc
    func uiModeDidChange(oldValue: ConversationUIMode) {
        switch oldValue {
        case .normal:
            // no-op
            break
        case .search:
            if #available(iOS 13.0, *) {
                navigationItem.searchController = nil
                // HACK: For some reason at this point the OWSNavbar retains the extra space it
                // used to house the search bar. This only seems to occur when dismissing
                // the search UI when scrolled to the very top of the conversation.
                navigationController?.navigationBar.sizeToFit()
            }
        case .selection:
            break
        }

        switch uiMode {
        case .normal:
            if navigationItem.titleView != headerView {
                navigationItem.titleView = headerView
            }
        case .search:
            if #available(iOS 13.0, *) {
                navigationItem.searchController = searchController.uiSearchController
            } else {
                // Note: setting a searchBar as the titleView causes UIKit to render the navBar
                // *slightly* taller (44pt -> 56pt)
                navigationItem.titleView = searchController.uiSearchController.searchBar
            }
        case .selection:
            navigationItem.titleView = nil
        }

        updateBarButtonItems()
        ensureBottomViewType()
    }
}

// MARK: -

extension ConversationViewController: MessageActionsViewControllerDelegate {
    public func messageActionsViewControllerRequestedKeyboardDismissal(_ messageActionsViewController: MessageActionsViewController,
                                                                       focusedView: UIView) {
        dismissKeyBoard()

        // After dismissing the keyboard, it's important we update the message actions
        // state. We keep track of the content offset at the time of presenting a message
        // action to ensure that new messages / typing indicators don't cause the
        // focused message to move. That offset is now different since the focused message
        // may be repositioning.
        updateMessageActionsState(forCell: focusedView)
    }

    public func messageActionsViewControllerRequestedDismissal(_ messageActionsViewController: MessageActionsViewController,
                                                               withAction action: MessageAction?) {

        let sender: UIView? = {
            let interaction = messageActionsViewController.focusedInteraction
            guard let indexPath = indexPath(forInteractionUniqueId: interaction.uniqueId) else {
                return nil
            }

            guard self.collectionView.indexPathsForVisibleItems.contains(indexPath),
                  let cell = self.collectionView.cellForItem(at: indexPath) as? CVCell else {
                return nil
            }

            // TODO: Should we use a more specific cell view?
            return cell
        }()

        dismissMessageActions(animated: true) {
            action?.block(sender)
        }
    }

    public func messageActionsViewControllerRequestedDismissal(_ messageActionsViewController: MessageActionsViewController,
                                                               withReaction reaction: String,
                                                               isRemoving: Bool) {
        dismissMessageActions(animated: true) {
            guard let message = messageActionsViewController.focusedInteraction as? TSMessage else {
                owsFailDebug("Not sending reaction for unexpected interaction type")
                return
            }

            self.databaseStorage.asyncWrite { transaction in
                ReactionManager.localUserReactedWithDurableSend(to: message,
                                                                emoji: reaction,
                                                                isRemoving: isRemoving,
                                                                transaction: transaction)
            }
        }
    }

    public func messageActionsViewController(_ messageActionsViewController: MessageActionsViewController,
                                             shouldShowReactionPickerForInteraction: TSInteraction) -> Bool {
        guard !threadViewModel.hasPendingMessageRequest else { return false }
        guard threadViewModel.isLocalUserFullMemberOfThread else { return false }

        switch messageActionsViewController.focusedInteraction {
        case let outgoingMessage as TSOutgoingMessage:
            if outgoingMessage.wasRemotelyDeleted { return false }

            switch outgoingMessage.messageState {
            case .failed, .sending:
                return false
            default:
                return true
            }
        case let incomingMessage as TSIncomingMessage:
            if incomingMessage.wasRemotelyDeleted { return false }

            return true
        default:
            return false
        }
    }

    public func messageActionsViewControllerLongPressGestureRecognizer(_ messageActionsViewController: MessageActionsViewController) -> UILongPressGestureRecognizer {
        return collectionViewLongPressGestureRecognizer
    }
}

extension ConversationViewController: MediaPresentationContextProvider {
    func mediaPresentationContext(galleryItem: MediaGalleryItem, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        guard let indexPath = ensureIndexPath(of: galleryItem.message) else {
            owsFailDebug("indexPath was unexpectedly nil")
            return nil
        }

        // `indexPath(of:)` can change the load window which requires re-laying out our view
        // in order to correctly determine:
        //  - `indexPathsForVisibleItems`
        //  - the correct presentation frame
        collectionView.layoutIfNeeded()

        guard let visibleIndex = collectionView.indexPathsForVisibleItems.firstIndex(of: indexPath) else {
            // This could happen if, after presenting media, you navigated within the gallery
            // to media not within the collectionView's visible bounds.
            return nil
        }

        guard let messageCell = collectionView.visibleCells[safe: visibleIndex] as? CVCell else {
            owsFailDebug("messageCell was unexpectedly nil")
            return nil
        }

        guard let mediaView = messageCell.albumItemView(forAttachment: galleryItem.attachmentStream) else {
            owsFailDebug("itemView was unexpectedly nil")
            return nil
        }

        guard let mediaSuperview = mediaView.superview else {
            owsFailDebug("mediaSuperview was unexpectedly nil")
            return nil
        }

        let presentationFrame = coordinateSpace.convert(mediaView.frame, from: mediaSuperview)

        // TODO exactly match corner radius for collapsed cells - maybe requires passing a masking view?
        return MediaPresentationContext(mediaView: mediaView, presentationFrame: presentationFrame, cornerRadius: kOWSMessageCellCornerRadius_Small * 2)
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return nil
    }

    func mediaWillDismiss(toContext: MediaPresentationContext) {
        // To avoid flicker when transition view is animated over the message bubble,
        // we initially hide the overlaying elements and fade them in.
        let mediaOverlayViews = toContext.mediaOverlayViews
        for mediaOverlayView in mediaOverlayViews {
            mediaOverlayView.alpha = 0
        }
    }

    func mediaDidDismiss(toContext: MediaPresentationContext) {
        // To avoid flicker when transition view is animated over the message bubble,
        // we initially hide the overlaying elements and fade them in.
        let mediaOverlayViews = toContext.mediaOverlayViews
        let duration: TimeInterval = kIsDebuggingMediaPresentationAnimations ? 1.5 : 0.2
        UIView.animate(
            withDuration: duration,
            animations: {
                for mediaOverlayView in mediaOverlayViews {
                    mediaOverlayView.alpha = 1
                }
            })
    }
}

// MARK: -

@objc
public extension ConversationViewController {
    func showManualMigrationAlert(groupThread: TSGroupThread,
                                  migrationInfo: GroupsV2MigrationInfo) {
        let mode = GroupMigrationActionSheet.Mode.upgradeGroup(migrationInfo: migrationInfo)
        let view = GroupMigrationActionSheet(groupThread: groupThread, mode: mode)
        view.present(fromViewController: self)
    }

    func showGroupLinkPromotionActionSheet() {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        guard groupThread.isGroupV2Thread else {
            return
        }
        let view = GroupLinkPromotionActionSheet(groupThread: groupThread,
                                                 conversationViewController: self)
        view.present(fromViewController: self)
    }
}

// MARK: -

extension ConversationViewController: MessageDetailViewDelegate {

    func detailViewMessageWasDeleted(_ messageDetailViewController: MessageDetailViewController) {
        Logger.info("")

        navigationController?.popToViewController(self, animated: true)
    }
}
// MARK: -

extension ConversationViewController: LongTextViewDelegate {

    public func longTextViewMessageWasDeleted(_ longTextViewController: LongTextViewController) {
        Logger.info("")

        navigationController?.popToViewController(self, animated: true)
    }

    @objc
    public func expandTruncatedTextOrPresentLongTextView(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        guard let displayableBodyText = itemViewModel.displayableBodyText else {
            owsFailDebug("Missing displayableBodyText.")
            return
        }
        if displayableBodyText.canRenderTruncatedTextInline {
            self.setTextExpanded(interactionId: itemViewModel.interaction.uniqueId)

            // TODO: Verify scroll state continuity.
            // Alternately we could use load coordinator and specify a scroll action.
            databaseStorage.write { transaction in
                self.databaseStorage.touch(interaction: itemViewModel.interaction,
                                           shouldReindex: false,
                                           transaction: transaction)
            }
        } else {
            let viewController = LongTextViewController(itemViewModel: itemViewModel)
            viewController.delegate = self
            navigationController?.pushViewController(viewController, animated: true)
        }
    }
}
