//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

extension ConversationViewController {

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

    public var renderItems: [CVRenderItem] {
        AssertIsOnMainThread()

        return loadCoordinator.renderItems
    }

    public var allIndexPaths: [IndexPath] {
        AssertIsOnMainThread()

        return loadCoordinator.allIndexPaths
    }

    func ensureIndexPath(of interaction: TSMessage) -> IndexPath? {
        // CVC TODO: This is incomplete.
        self.indexPath(forInteractionUniqueId: interaction.uniqueId)
    }

    func clearThreadUnreadFlagIfNecessary() {
        if threadViewModel.isMarkedUnread {
            self.databaseStorage.write { transaction in
                self.threadViewModel.associatedData.updateWith(
                    isMarkedUnread: false,
                    updateStorageService: true,
                    transaction: transaction
                )
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

    // When performing an interactive dismiss, safe area updates rapidly in quick succession,
    // which causes this method to go haywire, recomputing insets a few times and incorrectly determining
    // that it needs to scroll as a result. To avoid this, apply a debounce to rapid updates.
    public func updateContentInsetsDebounced() {
        updateContentInsetsEvent.requestNotify()
    }

    @objc(updateContentInsets)
    internal func updateContentInsets() {
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
        newInsets.bottom = (keyboardOverlap +
                                bottomBar.height -
                                view.safeAreaInsets.bottom)
        newInsets.top = (bannerView?.height ?? 0)

        let wasScrolledToBottom = self.isScrolledToBottom

        // Changing the contentInset can change the contentOffset, so make sure we
        // stash the current value before making any changes.
        let oldYOffset = collectionView.contentOffset.y

        let didChangeInsets = oldInsets != newInsets

        UIView.performWithoutAnimation {
            if didChangeInsets {
                let contentOffset = self.collectionView.contentOffset
                self.collectionView.contentInset = newInsets
                self.collectionView.setContentOffset(contentOffset, animated: false)
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
        } else if isPresentingContextMenu {
            // Do nothing
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
                let minYOffset = -view.safeAreaInsets.top
                let newYOffset = (oldYOffset + insetChange).clamp(minYOffset, safeContentHeight)
                let newOffset = CGPoint(x: 0, y: newYOffset)

                // This offset change will be animated by UIKit's UIView animation block
                // which updateContentInsets() is called within
                collectionView.setContentOffset(newOffset, animated: false)
            }
        }
    }

    public func showUnknownThreadWarningAlert() {
        // TODO: Finalize this copy.
        let message = (thread.isGroupThread
                        ? NSLocalizedString("ALERT_UNKNOWN_THREAD_WARNING_GROUP_MESSAGE",
                                            comment: "Message for UI warning about an unknown group thread.")
                        : NSLocalizedString("ALERT_UNKNOWN_THREAD_WARNING_CONTACT_MESSAGE",
                                            comment: "Message for UI  warning about an unknown contact thread."))
        let actionSheet = ActionSheetController(message: message)
        actionSheet.addAction(ActionSheetAction(
            title: NSLocalizedString("ALERT_UNKNOWN_THREAD_WARNING_LEARN_MORE",
                                     comment: "Label for button to learn more about message requests."),
            style: .default,
            handler: { _ in
                // TODO: Finalize this behavior.
                let url = URL(string: "https://support.signal.org/hc/articles/360007459591")!
                UIApplication.shared.open(url, options: [:])

            }
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    public func showDeliveryIssueWarningAlert(from senderAddress: SignalServiceAddress, isKnownThread: Bool) {
        let senderName = databaseStorage.read { transaction in
            Self.contactsManager.displayName(for: senderAddress, transaction: transaction)
        }
        let alertTitle = NSLocalizedString("ALERT_DELIVERY_ISSUE_TITLE", comment: "Title for delivery issue sheet")
        let alertMessageFormat: String
        if isKnownThread {
            alertMessageFormat = NSLocalizedString("ALERT_DELIVERY_ISSUE_MESSAGE_FORMAT", comment: "Format string for delivery issue sheet message. Embeds {{ sender name }}.")
        } else {
            alertMessageFormat = NSLocalizedString("ALERT_DELIVERY_ISSUE_UNKNOWN_THREAD_MESSAGE_FORMAT", comment: "Format string for delivery issue sheet message where the original thread is unknown. Embeds {{ sender name }}.")
        }

        let alertMessage = String(format: alertMessageFormat, senderName)

        let headerImageView = UIImageView(image: .init(named: "delivery-issue"))
        headerImageView.autoSetDimension(.height, toSize: 110)
        headerImageView.autoSetDimension(.width, toSize: 200)

        let headerView = UIView()
        headerView.addSubview(headerImageView)
        headerImageView.autoPinEdge(toSuperviewEdge: .top, withInset: 22)
        headerImageView.autoPinEdge(toSuperviewEdge: .bottom)
        headerImageView.autoHCenterInSuperview()

        let actionSheet = ActionSheetController(
            title: alertTitle,
            message: alertMessage)
        actionSheet.customHeader = headerView
        actionSheet.addAction(OWSActionSheets.okayAction)
        actionSheet.addAction(
            ActionSheetAction(
                title: CommonStrings.learnMore,
                accessibilityIdentifier: "learn_more",
                style: .default
            ) { _ in
                UIApplication.shared.open(URL(string: "https://support.signal.org/hc/articles/4404859745690")!)
            }
        )
        presentActionSheet(actionSheet)
    }
}

// MARK: - ForwardMessageDelegate

extension ConversationViewController: ForwardMessageDelegate {
    public func forwardMessageFlowDidComplete(items: [ForwardMessageItem],
                                              recipientThreads: [TSThread]) {
        AssertIsOnMainThread()

        self.uiMode = .normal

        self.dismiss(animated: true) {
            ForwardMessageViewController.finalizeForward(items: items,
                                                         recipientThreads: recipientThreads,
                                                         fromViewController: self)
        }
    }

    public func forwardMessageFlowDidCancel() {
        self.dismiss(animated: true)
    }
}

// MARK: - MessageActionsToolbarDelegate

extension ConversationViewController: MessageActionsToolbarDelegate {
    public func messageActionsToolbar(_ messageActionsToolbar: MessageActionsToolbar, executedAction: MessageAction) {
        executedAction.block(messageActionsToolbar)
    }

    public var messageActionsToolbarSelectedInteractionCount: Int {
        self.selectionState.interactionCount
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
    func uiModeDidChange(oldValue: ConversationUIMode) {
        if oldValue == .search {
            if #available(iOS 13.0, *) {
                navigationItem.searchController = nil
                // HACK: For some reason at this point the OWSNavbar retains the extra space it
                // used to house the search bar. This only seems to occur when dismissing
                // the search UI when scrolled to the very top of the conversation.
                navigationController?.navigationBar.sizeToFit()
            }
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

extension ConversationViewController: MediaPresentationContextProvider {
    func mediaPresentationContext(item: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        guard case let .gallery(galleryItem) = item else {
            owsFailDebug("Unexpected media type")
            return nil
        }

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
        return MediaPresentationContext(mediaView: mediaView,
                                        presentationFrame: presentationFrame,
                                        cornerRadius: CVComponentMessage.bubbleSharpCornerRadius * 2)
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

public extension ConversationViewController {
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

    public func expandTruncatedTextOrPresentLongTextView(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        guard let displayableBodyText = itemViewModel.displayableBodyText else {
            owsFailDebug("Missing displayableBodyText.")
            return
        }
        if displayableBodyText.canRenderTruncatedTextInline {
            self.setTextExpanded(interactionId: itemViewModel.interaction.uniqueId)
            self.loadCoordinator.enqueueReload(updatedInteractionIds: [itemViewModel.interaction.uniqueId],
                                               deletedInteractionIds: [])
        } else {
            let viewController = LongTextViewController(itemViewModel: itemViewModel)
            viewController.delegate = self
            navigationController?.pushViewController(viewController, animated: true)
        }
    }
}

// MARK: -

extension ConversationViewController: SendPaymentViewDelegate {
    public func didSendPayment() {
        let paymentSettingsView = PaymentsSettingsViewController(mode: .standalone)
        let navigationController = OWSNavigationController(rootViewController: paymentSettingsView)
        presentFormSheet(navigationController, animated: true)
    }
}
