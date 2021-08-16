//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

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

public struct CVSelectionItem {
    public let interactionId: String
    public let interactionType: OWSInteractionType
    public let selectionType: CVSelectionType
}

// MARK: -

public protocol CVSelectionStateDelegate: AnyObject {
    func selectionStateDidChange()
}

// MARK: -

// In selection mode, represents which interactions (or portions thereof) are currently selected.
@objc
public class CVSelectionState: NSObject {
    public weak var delegate: CVSelectionStateDelegate?

    // A map of interaction uniqueId-to-CVSelectionItem.
    //
    // For items in this map, selectionType should never be .none.
    private var itemMap = [String: CVSelectionItem]()

    public func add(interaction: TSInteraction, selectionType: CVSelectionType) {
        AssertIsOnMainThread()

        guard !selectionType.isEmpty else {
            owsFailDebug("Cannot add or remote empty selection type.")
            return
        }

        let interactionId = interaction.uniqueId
        owsAssertDebug(!isSelected(interactionId, selectionType: selectionType))

        if let oldItem = itemMap[interactionId] {
            let newItem = CVSelectionItem(interactionId: interactionId,
                                          interactionType: interaction.interactionType,
                                          selectionType: oldItem.selectionType.union(selectionType))
            owsAssertDebug(!newItem.selectionType.isEmpty)
            owsAssertDebug(oldItem.interactionId == newItem.interactionId)
            owsAssertDebug(oldItem.interactionType == newItem.interactionType)
            guard oldItem.selectionType != newItem.selectionType else {
                owsFailDebug("Did not change state.")
                return
            }
            itemMap[interactionId] = newItem
        } else {
            let newItem = CVSelectionItem(interactionId: interactionId,
                                          interactionType: interaction.interactionType,
                                          selectionType: selectionType)
            itemMap[interactionId] = newItem
        }
        delegate?.selectionStateDidChange()
    }

    public func add(itemViewModel: CVItemViewModel, selectionType: CVSelectionType) {
        add(interaction: itemViewModel.interaction, selectionType: selectionType)
    }

    public func remove(interaction: TSInteraction, selectionType: CVSelectionType) {
        AssertIsOnMainThread()

        guard !selectionType.isEmpty else {
            owsFailDebug("Cannot add or remote empty selection type.")
            return
        }

        let interactionId = interaction.uniqueId
        owsAssertDebug(!isSelected(interactionId, selectionType: selectionType))

        if let oldItem = itemMap[interactionId] {
            let newItem = CVSelectionItem(interactionId: interactionId,
                                          interactionType: interaction.interactionType,
                                          selectionType: oldItem.selectionType.subtracting(selectionType))
            owsAssertDebug(oldItem.interactionId == newItem.interactionId)
            owsAssertDebug(oldItem.interactionType == newItem.interactionType)
            guard oldItem.selectionType != newItem.selectionType else {
                owsFailDebug("Did not change state.")
                return
            }
            if newItem.selectionType.isEmpty {
                itemMap.removeValue(forKey: interactionId)
            } else {
                itemMap[interactionId] = newItem
            }
        } else {
            owsFailDebug("Did not change state.")
            return
        }
        delegate?.selectionStateDidChange()
    }

    public func remove(itemViewModel: CVItemViewModel, selectionType: CVSelectionType) {
        remove(interaction: itemViewModel.interaction, selectionType: selectionType)
    }

    public func isSelected(_ interactionId: String, selectionType: CVSelectionType) -> Bool {
        AssertIsOnMainThread()

        guard let oldItem = itemMap[interactionId] else {
            return false
        }
        owsAssertDebug(oldItem.selectionType != .none)
        return oldItem.selectionType.contains(selectionType)
    }

    public func hasAnySelection(_ interactionId: String) -> Bool {
        AssertIsOnMainThread()

        guard let oldItem = itemMap[interactionId] else {
            return false
        }
        owsAssertDebug(oldItem.selectionType != .none)
        return true
    }

    public func hasAnySelection(interaction: TSInteraction) -> Bool {
        hasAnySelection(interaction.uniqueId)
    }

    public func reset() {
        AssertIsOnMainThread()

        guard !itemMap.isEmpty else {
            return
        }

        itemMap.removeAll()

        delegate?.selectionStateDidChange()
    }

    fileprivate func selectedInteractionIds(withSelectionType filterSelectionType: CVSelectionType) -> Set<String> {
        AssertIsOnMainThread()

        return Set(itemMap.values.compactMap { (item: CVSelectionItem) -> String? in
            if item.selectionType.intersection(filterSelectionType).isEmpty {
                return nil
            } else {
                return item.interactionId
            }
        })
    }

    public var multiSelectSelection: Set<String> {
        AssertIsOnMainThread()

        return Set(itemMap.keys)
    }
}

// MARK: -

extension ConversationViewController {

    //    public static func canSelect(interaction: TSInteraction,
    //                                 uiMode: ConversationUIMode) -> Bool {
    //        switch uiMode {
    //        case .normal, .search:
    //            return false
    //        case .selection:
    //            switch interaction.interactionType {
    //            case .threadDetails, .unknownThreadWarning, .defaultDisappearingMessageTimer, .typingIndicator, .unreadIndicator, .dateHeader:
    //                return false
    //            case .info, .error, .call:
    //                return true
    //            case .incomingMessage, .outgoingMessage:
    //                return true
    //            case .unknown:
    //                owsFailDebug("Unknown interaction type.")
    //                return false
    //            }
    //        case .forwarding:
    //            switch interaction.interactionType {
    //            case .threadDetails, .unknownThreadWarning, .defaultDisappearingMessageTimer, .typingIndicator, .unreadIndicator, .dateHeader:
    //                return false
    //            case .info, .error, .call:
    //                return false
    //            case .incomingMessage, .outgoingMessage:
    //                return true
    //            case .unknown:
    //                owsFailDebug("Unknown interaction type.")
    //                return false
    //            }
    //        }
    //    }
    //    // TODO:
    //    let selectionType: CVSelectionType = .allContent
    //    componentDelegate.selectionState.remove(itemViewModel.interaction.uniqueId,
    //    selectionType: selectionType)
    // } else {
    //    selectionView.isSelected = true
    //    // TODO:
    //    let selectionType: CVSelectionType = .allContent
    //    componentDelegate.selectionState.add(itemViewModel.interaction.uniqueId,
    //                                         selectionType: selectionType)

    // TODO: Remove from delegate protocol.
    //    public func cvc_isMessageSelected(_ interaction: TSInteraction) -> Bool {
    //        isMessageSelected(interaction)
    //    }

    //    public func cvc_didSelectViewItem(_ itemViewModel: CVItemViewModelImpl) {
    //        didSelectMessage(itemViewModel)
    //    }
    //
    //    public func cvc_didDeselectViewItem(_ itemViewModel: CVItemViewModelImpl) {
    //        didDeselectMessage(itemViewModel)
    //    }

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
        let selectedInteractionIds = self.selectionState.multiSelectSelection

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
        let hasMultiSelectSelection = (uiMode == .selection &&
                                        !selectionState.multiSelectSelection.isEmpty)
        deleteButton.isEnabled = hasMultiSelectSelection
    }

    // TODO:
    public func ensureSelectionViewState() {
        //        guard isShowingSelectionUI else {
        //            return
        //        }
        //        clearCollectionViewSelection()
        //
        //        let selectedInteractionIds = self.selectedInteractionIds
        //        let selectedIndexPaths = selectedInteractionIds.compactMap { interactionId in
        //            indexPath(forInteractionUniqueId: interactionId)
        //        }
        //        let indexPaths = collectionView.indexPathsForVisibleItems
        //        for indexPath in indexPaths {
        //            let isSelected = selectedIndexPaths.contains(indexPath)
        //            if isSelected {
        //                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        //            } else {
        //                collectionView.deselectItem(at: indexPath, animated: false)
        //            }
        //        }
    }

    //    public func didSelectMessage(_ message: CVItemViewModel) {
    //        AssertIsOnMainThread()
    //        owsAssertDebug(isShowingSelectionUI)
    //
    //        let interactionId = message.interaction.uniqueId
    ////        guard let indexPath = indexPath(forInteractionUniqueId: interactionId) else {
    ////            owsFailDebug("indexPath was unexpectedly nil")
    ////            return
    ////        }
    ////
    ////        collectionView.selectItem(at: indexPath,
    ////                                  animated: false,
    ////                                  // TODO: Is there a better way to indicate .none?
    ////                                  scrollPosition: UICollectionView.ScrollPosition(rawValue: 0))
    //        addToSelection(interactionId)
    //
    //        updateSelectionButtons()
    //    }
    //
    //    public func didDeselectMessage(_ message: CVItemViewModel) {
    //        AssertIsOnMainThread()
    //        owsAssertDebug(isShowingSelectionUI)
    //
    //        let interactionId = message.interaction.uniqueId
    ////        guard let indexPath = indexPath(forInteractionUniqueId: interactionId) else {
    ////            owsFailDebug("indexPath was unexpectedly nil")
    ////            return
    ////        }
    ////
    ////        collectionView.deselectItem(at: indexPath, animated: false)
    //        removeFromSelection(interactionId)
    //
    //        updateSelectionButtons()
    //    }
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
                    modalActivityIndicator.dismiss { [weak self] in
                        guard let self = self else { return }
                        self.uiMode = .normal
                    }
                }
            }
        }
        alert.addAction(delete)
        present(alert, animated: true)
    }
}

// MARK: -

extension ConversationViewController: CVSelectionStateDelegate {
    public func selectionStateDidChange() {
        AssertIsOnMainThread()

        updateSelectionButtons()
    }
}
