//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

public struct CVSelectionItem {
    public let interactionId: String
}

// MARK: -

public struct CVSelectionType: OptionSet {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static var none: CVSelectionType { CVSelectionType(rawValue: 0) }
    public static let primaryContent = CVSelectionType(rawValue: 1 << 0)
    public static let secondaryContent = CVSelectionType(rawValue: 1 << 1)
    public static var allContent: CVSelectionType { primaryContent.union(secondaryContent) }
}

// MARK: -

// In multi-select mode, represents which interactions are currently selected.
// In forwarding mode, represents which interactions (or portions thereof) are currently selected.
public class CVSelectionState {
    // A map of interaction uniqueId-CVSelectionType.
    //
    // CVSelectionType values should never be .none.
    private var stateMap = [String: CVSelectionType]()

    fileprivate func add(_ interactionId: String, selectionType: CVSelectionType) {
        AssertIsOnMainThread()
        owsAssertDebug(!isSelected(interactionId, selectionType: selectionType))

        let oldSelectionType: CVSelectionType = stateMap[interactionId] ?? .none
        let newSelectionType: CVSelectionType = oldSelectionType.union(selectionType)
        if newSelectionType.isEmpty {
            owsFailDebug("Adding should never remove.")
            stateMap.removeValue(forKey: interactionId)
        } else {
            stateMap[interactionId] = newSelectionType
        }
    }

    fileprivate func remove(_ interactionId: String, selectionType: CVSelectionType) {
        AssertIsOnMainThread()
        owsAssertDebug(isSelected(interactionId, selectionType: selectionType))

        let oldSelectionType: CVSelectionType = stateMap[interactionId] ?? .none
        let newSelectionType: CVSelectionType = oldSelectionType.subtracting(selectionType)
        if newSelectionType.isEmpty {
            stateMap.removeValue(forKey: interactionId)
        } else {
            stateMap[interactionId] = newSelectionType
        }
    }

    fileprivate func isSelected(_ interactionId: String, selectionType: CVSelectionType) -> Bool {
        AssertIsOnMainThread()

        let oldSelectionType: CVSelectionType = stateMap[interactionId] ?? .none
        return oldSelectionType.contains(selectionType)
    }

    func reset() {
        AssertIsOnMainThread()

        stateMap.removeAll()
    }

    fileprivate func selectedInteractionIds(withSelectionType filterSelectionType: CVSelectionType) -> Set<String> {
        AssertIsOnMainThread()

        return Set(stateMap.compactMap { (interactionId: String, interactionSelectionType: CVSelectionType) -> String? in
            if interactionSelectionType.intersection(interactionSelectionType).isEmpty {
                return nil
            } else {
                return interactionId
            }
        })
    }

    fileprivate var multiSelectSelection: Set<String> {
        AssertIsOnMainThread()

        return Set(stateMap.keys)
    }
}

// MARK: -

extension ConversationViewController {

    public func cvc_isMessageSelected(_ interaction: TSInteraction) -> Bool {
        isMessageSelected(interaction)
    }

    public func cvc_didSelectViewItem(_ itemViewModel: CVItemViewModelImpl) {
        didSelectMessage(itemViewModel)
    }

    public func cvc_didDeselectViewItem(_ itemViewModel: CVItemViewModelImpl) {
        didDeselectMessage(itemViewModel)
    }

//    public func addToSelection(_ interactionId: String) {
//        cellSelection.add(interactionId)
//        // TODO: Update cells/selection view?
//    }
//
//    public func removeFromSelection(_ interactionId: String) {
//        cellSelection.remove(interactionId)
//        // TODO: Update cells/selection view?
//    }
//
//    public func isMessageSelected(_ interaction: TSInteraction) -> Bool {
//        cellSelection.isSelected(interaction.uniqueId)
//    }
//    fileprivate var selectedInteractionIds: Set<String> { cellSelection.selectedInteractionIds }
//
//    func clearSelection() {
//        cellSelection.reset()
//        clearCollectionViewSelection()
//    }
//
//    func clearCollectionViewSelection() {
//        guard let selectedIndices = collectionView.indexPathsForSelectedItems else {
//            owsFailDebug("selectedIndices was unexpectedly nil")
//            return
//        }
//
//        for index in selectedIndices {
//            collectionView.deselectItem(at: index, animated: false)
//            guard let cell = collectionView.cellForItem(at: index) else {
//                continue
//            }
//            cell.isSelected = false
//        }
//    }

    public func buildSelectionToolbar() -> MessageActionsToolbar {
        let deleteSelectedMessages = MessageAction(
            .delete,
            accessibilityLabel: NSLocalizedString("MESSAGE_ACTION_DELETE_SELECTED_MESSAGES",
                                                  comment: "accessibility label"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action",
                                                                    name: "delete_selected_messages"), contextMenuTitle: "Delete Selected", contextMenuAttributes: [],
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

                DispatchQueue.main.async {
                    self.clearSelection()
                    modalActivityIndicator.dismiss {
                        self.uiMode = .normal
                        DispatchQueue.global().async {
                            self.deleteSelectedItems(selectedInteractionIds: selectedInteractionIds)
                        }
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

    public func updateSelectionButtons() {
        guard let selectionToolbar = self.selectionToolbar else {
            owsFailDebug("Missing selectionToolbar.")
            return
        }
        guard let deleteButton = selectionToolbar.buttonItem(for: .delete) else {
            owsFailDebug("deleteButton was unexpectedly nil")
            return
        }
        deleteButton.isEnabled = selectedInteractionIds.count > 0
    }

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
    }

    public func didSelectMessage(_ message: CVItemViewModel) {
        AssertIsOnMainThread()
        owsAssertDebug(isShowingSelectionUI)

        let interactionId = message.interaction.uniqueId
//        guard let indexPath = indexPath(forInteractionUniqueId: interactionId) else {
//            owsFailDebug("indexPath was unexpectedly nil")
//            return
//        }
//
//        collectionView.selectItem(at: indexPath,
//                                  animated: false,
//                                  // TODO: Is there a better way to indicate .none?
//                                  scrollPosition: UICollectionView.ScrollPosition(rawValue: 0))
        addToSelection(interactionId)

        updateSelectionButtons()
    }

    public func didDeselectMessage(_ message: CVItemViewModel) {
        AssertIsOnMainThread()
        owsAssertDebug(isShowingSelectionUI)

        let interactionId = message.interaction.uniqueId
//        guard let indexPath = indexPath(forInteractionUniqueId: interactionId) else {
//            owsFailDebug("indexPath was unexpectedly nil")
//            return
//        }
//
//        collectionView.deselectItem(at: indexPath, animated: false)
        removeFromSelection(interactionId)

        updateSelectionButtons()
    }
}

// MARK: - Selection

extension ConversationViewController {

    var cancelSelectionBarButtonItem: UIBarButtonItem {
        UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(didTapCancelSelection))
    }

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
