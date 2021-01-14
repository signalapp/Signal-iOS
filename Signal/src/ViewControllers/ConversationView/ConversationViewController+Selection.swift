//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

// Represents which interactions are currently selected during multi-select.
public class CVCellSelection {
    private var _selectedInteractionIds = Set<String>()

    fileprivate func add(_ interactionId: String) {
        AssertIsOnMainThread()
        owsAssertDebug(!isSelected(interactionId))

        _selectedInteractionIds.insert(interactionId)
    }

    fileprivate func remove(_ interactionId: String) {
        AssertIsOnMainThread()
        owsAssertDebug(isSelected(interactionId))

        _selectedInteractionIds.remove(interactionId)
    }

    fileprivate func isSelected(_ interactionId: String) -> Bool {
        AssertIsOnMainThread()

        return _selectedInteractionIds.contains(interactionId)
    }

    func reset() {
        AssertIsOnMainThread()

        _selectedInteractionIds.removeAll()
    }

    fileprivate var selectedInteractionIds: Set<String> {
        AssertIsOnMainThread()

        return _selectedInteractionIds
    }
}

// MARK: -

extension ConversationViewController {

    @objc
    public func addToSelection(_ interactionId: String) {
        cellSelection.add(interactionId)
        // TODO: Update cells/selection view?
    }

    @objc
    public func removeFromSelection(_ interactionId: String) {
        cellSelection.remove(interactionId)
        // TODO: Update cells/selection view?
    }

    @objc
    public func isMessageSelected(_ interaction: TSInteraction) -> Bool {
        cellSelection.isSelected(interaction.uniqueId)
    }
    fileprivate var selectedInteractionIds: Set<String> { cellSelection.selectedInteractionIds }

    func clearSelection() {
        cellSelection.reset()
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
        let selectedInteractionIds = self.selectedInteractionIds

        let message: String
        if selectedInteractionIds.count > 1 {
            let messageFormat = NSLocalizedString("DELETE_SELECTED_MESSAGES_IN_CONVERSATION_ALERT_FORMAT",
                                                  comment: "action sheet body. Embeds {{number of selected messages}} which will be deleted.")
            message = String(format: messageFormat, selectedInteractionIds.count)
        } else {
            message = NSLocalizedString("DELETE_SELECTED_SINGLE_MESSAGES_IN_CONVERSATION_ALERT_FORMAT",
                                        comment: "action sheet body")
        }
        let alert = ActionSheetController(title: nil, message: message)
        alert.addAction(OWSActionSheets.cancelAction)

        let delete = ActionSheetAction(title: CommonStrings.deleteForMeButton, style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { [weak self] modalActivityIndicator in
                guard let self = self else { return }

                self.deleteSelectedItems(selectedInteractionIds: selectedInteractionIds)

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

    private func deleteSelectedItems(selectedInteractionIds: Set<String>) {
        databaseStorage.write { transaction in
            for interactionId in selectedInteractionIds {
                guard let interaction = TSInteraction.anyFetch(uniqueId: interactionId,
                                                               transaction: transaction) else {
                    owsFailDebug("Missing interaction.")
                    continue
                }
                interaction.anyRemove(transaction: transaction)
            }
        }
    }

    @objc
    public func updateSelectionButtons() {
        guard let deleteButton = selectionToolbar.buttonItem(for: .delete) else {
            owsFailDebug("deleteButton was unexpectedly nil")
            return
        }
        deleteButton.isEnabled = selectedInteractionIds.count > 0
    }

    @objc
    public func ensureSelectionViewState() {
        guard isShowingSelectionUI else {
            return
        }
        clearCollectionViewSelection()

        let selectedInteractionIds = self.selectedInteractionIds
        let selectedIndexPaths = selectedInteractionIds.compactMap { interactionId in
            indexPath(forInteractionUniqueId: interactionId)
        }
        let indexPaths = collectionView.indexPathsForVisibleItems
        for indexPath in indexPaths {
            let isSelected = selectedIndexPaths.contains(indexPath)
            if isSelected {
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            } else {
                collectionView.deselectItem(at: indexPath, animated: false)
            }
        }
        updateSelectionHighlight()
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

        guard let firstFrame = layout.layoutAttributesForItem(at: first)?.frame else {
            owsFailDebug("firstFrame was unexpectedly nil")
            return nil
        }

        let topMargin: CGFloat
        if first.row - 1 >= 0,
           let firstItem = renderItem(forIndex: first.row),
           let previousItem = renderItem(forIndex: first.row - 1) {
            let spacing = firstItem.vSpacing(previousLayoutItem: previousItem)
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
        if last.row + 1 < renderItems.count,
           let lastItem = renderItem(forIndex: last.row),
           let afterLastItem = renderItem(forIndex: last.row + 1) {
            let spacing = afterLastItem.vSpacing(previousLayoutItem: lastItem)
            bottomMargin = spacing / 2
        } else if last.row + 1 >= renderItems.count {
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

    @objc
    public func didSelectMessage(_ message: CVItemViewModel) {
        AssertIsOnMainThread()
        owsAssertDebug(isShowingSelectionUI)

        let interactionId = message.interaction.uniqueId
        guard let indexPath = indexPath(forInteractionUniqueId: interactionId) else {
            owsFailDebug("indexPath was unexpectedly nil")
            return
        }

        collectionView.selectItem(at: indexPath,
                                  animated: false,
                                  // TODO: Is there a better way to indicate .none?
                                  scrollPosition: UICollectionView.ScrollPosition(rawValue: 0))
        addToSelection(interactionId)

        updateSelectionButtons()
        updateSelectionHighlight()
    }

    @objc
    public func didDeselectMessage(_ message: CVItemViewModel) {
        AssertIsOnMainThread()
        owsAssertDebug(isShowingSelectionUI)

        let interactionId = message.interaction.uniqueId
        guard let indexPath = indexPath(forInteractionUniqueId: interactionId) else {
            owsFailDebug("indexPath was unexpectedly nil")
            return
        }

        collectionView.deselectItem(at: indexPath, animated: false)
        removeFromSelection(interactionId)

        updateSelectionButtons()
        updateSelectionHighlight()
    }
}

// MARK: -

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
        let thread = self.thread
        let alert = ActionSheetController(title: nil, message: NSLocalizedString("DELETE_ALL_MESSAGES_IN_CONVERSATION_ALERT_BODY", comment: "action sheet body"))
        alert.addAction(OWSActionSheets.cancelAction)
        let deleteTitle = NSLocalizedString("DELETE_ALL_MESSAGES_IN_CONVERSATION_BUTTON", comment: "button text")
        let delete = ActionSheetAction(title: deleteTitle, style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { [weak self] modalActivityIndicator in
                guard let self = self else { return }
                self.databaseStorage.write {
                    thread.removeAllThreadInteractions(transaction: $0)
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
}
