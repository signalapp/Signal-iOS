//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

extension ConversationViewController {
    @objc
    func viewItem(forIndex index: NSInteger) -> ConversationViewItem? {
        guard index >= 0, index < viewItems.count else {
            owsFailDebug("Invalid view item index: \(index)")
            return nil
        }
        return viewItems[index]
    }

    @objc
    var viewItems: [ConversationViewItem] { conversationViewModel.viewState.viewItems }

    @objc
    func ensureIndexPath(of interaction: TSMessage) -> IndexPath? {
        return databaseStorage.uiRead { transaction in
            self.conversationViewModel.ensureLoadWindowContainsInteractionId(interaction.uniqueId,
                                                                             transaction: transaction)
        }
    }

    @objc
    func clearThreadUnreadFlagIfNecessary() {
        if thread.isMarkedUnread {
            self.databaseStorage.write { transaction in
                self.thread.clearMarkedAsUnread(updateStorageService: true, transaction: transaction)
            }
        }
    }
}

// MARK: - ForwardMessageDelegate

extension ConversationViewController: ForwardMessageDelegate {
    public func forwardMessageFlowDidComplete(viewItem: ConversationViewItem, threads: [TSThread]) {
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

// MARK: - MessageActionsDelegate

extension ConversationViewController: MessageActionsDelegate {
    func messageActionsShowDetailsForItem(_ conversationViewItem: ConversationViewItem) {
        showDetailView(for: conversationViewItem)
    }

    func messageActionsReplyToItem(_ conversationViewItem: ConversationViewItem) {
        populateReply(for: conversationViewItem)
    }

    func messageActionsForwardItem(_ conversationViewItem: ConversationViewItem) {
        ForwardMessageNavigationController.present(for: conversationViewItem, from: self, delegate: self)
    }

    func messageActionsStartedSelect(initialItem conversationViewItem: ConversationViewItem) {
        uiMode = .selection

        guard let indexPath = self.conversationViewModel.indexPath(for: conversationViewItem) else {
            owsFailDebug("indexPath was unexpectedly nil")
            return
        }

        guard let cell = self.collectionView.cellForItem(at: indexPath) else {
            owsFailDebug("indexPath was unexpectedly nil")
            return
        }

        guard let conversationCell = cell as? ConversationViewCell else {
            owsFailDebug("unexpected cell type: \(cell)")
            return
        }
        self.conversationCell(conversationCell, didSelect: conversationViewItem)
    }

    func messageActionsDeleteItem(_ conversationViewItem: ConversationViewItem) {
        // Only show the new menu at all if the feature is on.
        guard RemoteConfig.deleteForEveryone else { return conversationViewItem.deleteAction() }

        let actionSheetController = ActionSheetController(message: NSLocalizedString(
            "MESSAGE_ACTION_DELETE_FOR_TITLE",
            comment: "The title for the action sheet asking who the user wants to delete the message for."
        ))

        let deleteForMeAction = ActionSheetAction(
            title: NSLocalizedString(
                "MESSAGE_ACTION_DELETE_FOR_YOU",
                comment: "The title for the action that deletes a message for the local user only."
            ),
            style: .destructive
        ) { _ in
            conversationViewItem.deleteAction()
        }
        actionSheetController.addAction(deleteForMeAction)

        if canBeRemotelyDeleted(conversationViewItem: conversationViewItem),
            let message = conversationViewItem.interaction as? TSMessage {

            let deleteForEveryoneAction = ActionSheetAction(
                title: NSLocalizedString(
                    "MESSAGE_ACTION_DELETE_FOR_EVERYONE",
                    comment: "The title for the action that deletes a message for all users in the conversation."
                ),
                style: .destructive
            ) { [weak self] _ in
                self?.showDeleteForEveryoneConfirmationIfNecessary {
                    guard let self = self else { return }

                    let deleteMessage = TSOutgoingDeleteMessage(thread: self.thread, message: message)

                    self.databaseStorage.write { transaction in
                        message.updateWithRemotelyDeletedAndRemoveRenderableContent(with: transaction)
                        SSKEnvironment.shared.messageSenderJobQueue.add(message: deleteMessage.asPreparer, transaction: transaction)
                    }
                }
            }
            actionSheetController.addAction(deleteForEveryoneAction)
        }

        actionSheetController.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheetController)
    }

    // A message can be remoetely deleted iff:
    //  * the feature flag is enabled
    //  * you sent this message
    //  * you haven't already remotely deleted this message
    //  * it has been less than 3 hours since you sent the message
    func canBeRemotelyDeleted(conversationViewItem: ConversationViewItem) -> Bool {
        guard RemoteConfig.deleteForEveryone else { return false }
        guard let outgoingMessage = conversationViewItem.interaction as? TSOutgoingMessage else { return false }
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

    func clearSelection() {
        selectedItems = [:]
        clearCollectionViewSelection()
        updateSelectionHighlight()
    }

    func clearCollectionViewSelection() {
        guard let selectedIndices = collectionView.indexPathsForSelectedItems else {
            owsFailDebug("selectedIndices was unexpectedly nil")
            return
        }

        for index in selectedIndices {
            collectionView.deselectItem(at: index, animated: false)
            guard let cell = collectionView.cellForItem(at: index) else {
                continue
            }
            cell.isSelected = false
        }
    }

    @objc
    public func buildSelectionToolbar() -> MessageActionsToolbar {
        let deleteSelectedMessages = MessageAction(
            .delete,
            accessibilityLabel: NSLocalizedString("MESSAGE_ACTION_DELETE_SELECTED_MESSAGES",
                                                  comment: "accessibility label"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action",
                                                                    name: "delete_selected_messages"),
            block: { [weak self] _ in self?.didTapDeleteSelectedItems() }
        )

        let toolbar = MessageActionsToolbar(actions: [deleteSelectedMessages])
        toolbar.actionDelegate = self
        return toolbar
    }

    func didTapDeleteSelectedItems() {
        let message: String
        if selectedItems.count > 1 {
            let messageFormat = NSLocalizedString("DELETE_SELECTED_MESSAGES_IN_CONVERSATION_ALERT_FORMAT",
                                                  comment: "action sheet body. Embeds {{number of selected messages}} which will be deleted.")
            message = String(format: messageFormat, selectedItems.count)
        } else {
            message = NSLocalizedString("DELETE_SELECTED_SINGLE_MESSAGES_IN_CONVERSATION_ALERT_FORMAT",
                                        comment: "action sheet body")
        }
        let alert = ActionSheetController(title: nil, message: message)
        alert.addAction(OWSActionSheets.cancelAction)

        let delete = ActionSheetAction(title: CommonStrings.deleteButton, style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { [weak self] modalActivityIndicator in
                guard let self = self else { return }

                self.databaseStorage.write { transaction in
                    for (_, item) in self.selectedItems {
                        item.interaction.anyRemove(transaction: transaction)
                    }
                }
                DispatchQueue.main.async {
                    self.clearSelection()
                    modalActivityIndicator.dismiss {
                        self.uiMode = .normal
                    }
                }
            }
        }
        alert.addAction(delete)
        present(alert, animated: true)
    }

    @objc
    public func updateSelectionButtons() {
        guard let deleteButton = selectionToolbar.buttonItem(for: .delete) else {
            owsFailDebug("deleteButton was unexpectedly nil")
            return
        }
        deleteButton.isEnabled = selectedItems.count > 0
    }

    @objc
    public func maintainSelectionAfterMappingChange() {
        clearCollectionViewSelection()
        for (_, viewItem) in selectedItems {
            guard let indexPath = conversationViewModel.indexPath(for: viewItem) else {
                // cell for item was unloaded
                continue
            }

            collectionView.selectItem(at: indexPath,
                                      animated: false,
                                      scrollPosition: [])
        }
    }

    @objc
    public func updateSelectionHighlight() {
        guard let indexPaths = collectionView.indexPathsForSelectedItems else {
            owsFailDebug("indexPaths was unexpectedly nil")
            return
        }

        let groups: [[IndexPath]] = Self.consecutivelyGrouped(indexPaths: indexPaths)

        let frames = groups.compactMap {
            self.boundingFrame(indexPaths: $0)
        }.map {
            self.selectionHighlightView.convert($0, from: self.collectionView)
        }
        collectionView.sendSubviewToBack(selectionHighlightView)
        selectionHighlightView.setHighlightedFrames(frames)
    }

    func boundingFrame(indexPaths: [IndexPath]) -> CGRect? {
        guard let first = indexPaths.first else {
            return nil
        }

        guard let firstFrame = self.layout.layoutAttributesForItem(at: first)?.frame else {
            owsFailDebug("firstFrame was unexpectedly nil")
            return nil
        }

        let topMargin: CGFloat
        if first.row - 1 >= 0, let firstItem = viewItem(forIndex: first.row), let previousItem = viewItem(forIndex: first.row - 1) {
            let spacing = firstItem.vSpacing(withPreviousLayoutItem: previousItem)
            topMargin = spacing / 2
        } else if first.row - 1 < 0 {
            topMargin = ConversationStyle.defaultMessageSpacing / 2
        } else {
            topMargin = 0
        }

        guard let last = indexPaths.last else {
            owsFailDebug("last was unexpectedly nil")
            return nil
        }

        guard let lastFrame = self.layout.layoutAttributesForItem(at: last)?.frame else {
            owsFailDebug("lastFrame was unexpectedly nil")
            return nil
        }

        let bottomMargin: CGFloat
        if last.row + 1 < viewItems.count, let lastItem = viewItem(forIndex: last.row), let afterLastItem = viewItem(forIndex: last.row + 1) {
            let spacing = afterLastItem.vSpacing(withPreviousLayoutItem: lastItem)
            bottomMargin = spacing / 2
        } else if last.row + 1 >= viewItems.count {
            bottomMargin = ConversationStyle.defaultMessageSpacing / 2
        } else {
            bottomMargin = 0
        }

        let height = lastFrame.bottomLeft.y - firstFrame.topLeft.y + topMargin + bottomMargin
        return CGRect(x: firstFrame.topLeft.x,
                      y: firstFrame.topLeft.y - topMargin,
                      width: firstFrame.width,
                      height: height)
    }

    class func consecutivelyGrouped(indexPaths: [IndexPath]) -> [[IndexPath]] {
        let sorted = indexPaths.sorted { lhs, rhs in
            if lhs.section == rhs.section {
                return lhs.row < rhs.row
            } else {
                return lhs.section < rhs.section
            }
        }

        var consecutiveIndexPaths: [[IndexPath]] = []
        var previousIndexPath: IndexPath?
        for indexPath in sorted {
            defer {
                previousIndexPath = indexPath
            }

            guard let previousIndexPath = previousIndexPath else {
                consecutiveIndexPaths.append([indexPath])
                continue
            }

            guard previousIndexPath.section == indexPath.section else {
                consecutiveIndexPaths.append([indexPath])
                continue
            }

            guard previousIndexPath.row + 1 == indexPath.row else {
                consecutiveIndexPaths.append([indexPath])
                continue
            }

            let lastIndex = consecutiveIndexPaths.endIndex - 1
            consecutiveIndexPaths[lastIndex].append(indexPath)
        }

        return consecutiveIndexPaths
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
            hideSelectionViewsForVisibleCells()
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
            showSelectionViewsForVisibleCells()
        }

        updateBarButtonItems()
        reloadBottomBar()
    }
}

// MARK: - Selection

extension ConversationViewController {

    @objc
    var cancelSelectionBarButtonItem: UIBarButtonItem {
        UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(didTapCancelSelection))
    }

    @objc
    var deleteAllBarButtonItem: UIBarButtonItem {
        let title = NSLocalizedString("CONVERSATION_VIEW_DELETE_ALL_MESSAGES", comment: "button text to delete all items in the current conversation")
        return UIBarButtonItem(title: title, style: .plain, target: self, action: #selector(didTapDeleteAll))
    }

    @objc
    func didTapCancelSelection() {
        clearSelection()
        uiMode = .normal
    }

    @objc
    func didTapDeleteAll() {
        let alert = ActionSheetController(title: nil, message: NSLocalizedString("DELETE_ALL_MESSAGES_IN_CONVERSATION_ALERT_BODY", comment: "action sheet body"))
        alert.addAction(OWSActionSheets.cancelAction)
        let deleteTitle = NSLocalizedString("DELETE_ALL_MESSAGES_IN_CONVERSATION_BUTTON", comment: "button text")
        let delete = ActionSheetAction(title: deleteTitle, style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { [weak self] modalActivityIndicator in
                guard let self = self else { return }
                self.databaseStorage.write {
                    self.thread.removeAllThreadInteractions(transaction: $0)
                }
                DispatchQueue.main.async {
                    self.clearSelection()
                    modalActivityIndicator.dismiss {
                        self.uiMode = .normal
                    }
                }
            }
        }
        alert.addAction(delete)
        present(alert, animated: true)
    }

    func hideSelectionViewsForVisibleCells() {
        let cells = collectionView.visibleCells.compactMap { $0 as? SelectableConversationCell }
        cells.forEach { $0.selectionView.alpha = 1 }
        UIView.animate(withDuration: 0.15) {
            for cell in cells {
                cell.selectionView.alpha = 0
                cell.selectionView.isHidden = true
            }
        }
    }

    func showSelectionViewsForVisibleCells() {
        let cells = collectionView.visibleCells.compactMap { $0 as? SelectableConversationCell }
        cells.forEach { $0.selectionView.alpha = 0 }
        UIView.animate(withDuration: 0.15) {
            for cell in cells {
                cell.selectionView.isHidden = false
                cell.selectionView.alpha = 1
            }
        }
    }
}

extension ConversationViewController: MessageActionsViewControllerDelegate {
    func messageActionsViewControllerRequestedKeyboardDismissal(_ messageActionsViewController: MessageActionsViewController, focusedView: ConversationViewCell) {
        dismissKeyBoard()

        // After dismissing the keyboard, it's important we update the message actions
        // state. We keep track of the content offset at the time of presenting a message
        // action to ensure that new messages / typing indicators don't cause the
        // focused message to move. That offset is now different since the focused message
        // may be repositioning.
        updateMessageActionsState(for: focusedView)
    }

    func messageActionsViewControllerRequestedDismissal(_ messageActionsViewController: MessageActionsViewController, withAction action: MessageAction?) {

        let sender: UIView? = {
            let interaction = messageActionsViewController.focusedInteraction
            guard let index = conversationViewModel.viewState.interactionIndexMap[interaction.uniqueId] else {
                return nil
            }

            let indexPath = IndexPath(item: index.intValue, section: 0)

            guard self.collectionView.indexPathsForVisibleItems.contains(indexPath),
                let cell = self.collectionView.cellForItem(at: indexPath) else {
                    return nil
            }

            switch cell {
            case let messageCell as OWSMessageCell:
                return messageCell.messageView
            default:
                return cell
            }
        }()

        dismissMessageActions(animated: true) {
            action?.block(sender)
        }
    }

    func messageActionsViewControllerRequestedDismissal(_ messageActionsViewController: MessageActionsViewController, withReaction reaction: String, isRemoving: Bool) {
        dismissMessageActions(animated: true) {
            guard let message = messageActionsViewController.focusedInteraction as? TSMessage else {
                owsFailDebug("Not sending reaction for unexpected interaction type")
                return
            }

            self.databaseStorage.asyncWrite { transaction in
                ReactionManager.localUserReacted(to: message,
                                                 emoji: reaction,
                                                 isRemoving: isRemoving,
                                                 transaction: transaction)
            }
        }
    }

    func messageActionsViewController(_ messageActionsViewController: MessageActionsViewController,
                                      shouldShowReactionPickerForInteraction: TSInteraction) -> Bool {
        guard !self.threadViewModel.hasPendingMessageRequest else { return false }

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
            // to media not withing the collectionView's visible bounds.
            return nil
        }

        guard let messageCell = collectionView.visibleCells[safe: visibleIndex] as? OWSMessageCell else {
            owsFailDebug("messageCell was unexpectedly nil")
            return nil
        }

        guard let mediaView = messageCell.messageBubbleView.albumItemView(forAttachment: galleryItem.attachmentStream) else {
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
        guard let messageBubbleView = toContext.messageBubbleView else { return }

        // To avoid flicker when transition view is animated over the message bubble,
        // we initially hide the overlaying elements and fade them in.
        messageBubbleView.footerView.alpha = 0
        messageBubbleView.bodyMediaGradientView?.alpha = 0.0
    }

    func mediaDidDismiss(toContext: MediaPresentationContext) {
        guard let messageBubbleView = toContext.messageBubbleView else { return }

        // To avoid flicker when transition view is animated over the message bubble,
        // we initially hide the overlaying elements and fade them in.
        let duration: TimeInterval = kIsDebuggingMediaPresentationAnimations ? 1.5 : 0.2
        UIView.animate(
            withDuration: duration,
            animations: {
                messageBubbleView.footerView.alpha = 1.0
                messageBubbleView.bodyMediaGradientView?.alpha = 1.0
        })
    }
}

private extension MediaPresentationContext {
    var messageBubbleView: OWSMessageBubbleView? {
        guard let messageBubbleView = mediaView.firstAncestor(ofType: OWSMessageBubbleView.self) else {
            owsFailDebug("unexpected mediaView: \(mediaView)")
            return nil
        }

        return messageBubbleView
    }
}

extension OWSMessageBubbleView {
    func albumItemView(forAttachment attachment: TSAttachmentStream) -> UIView? {
        guard let mediaAlbumCellView = bodyMediaView as? MediaAlbumCellView else {
            owsFailDebug("mediaAlbumCellView was unexpectedly nil")
            return nil
        }

        guard let albumItemView = (mediaAlbumCellView.itemViews.first { $0.attachment == attachment }) else {
            assert(mediaAlbumCellView.moreItemsView != nil)
            return mediaAlbumCellView.moreItemsView
        }

        return albumItemView
    }
}

@objc
public class SelectionHighlightView: UIView {
    func setHighlightedFrames(_ frames: [CGRect]) {
        subviews.forEach { $0.removeFromSuperview() }

        for frame in frames {
            let highlight = UIView(frame: frame)
            highlight.backgroundColor = Theme.selectedConversationCellColor
            addSubview(highlight)
        }
    }
}
