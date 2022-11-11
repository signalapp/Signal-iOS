//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging

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
    public let isForwardable: Bool

    public let selectionType: CVSelectionType

    init(interactionId: String,
         interactionType: OWSInteractionType,
         isForwardable: Bool,
         selectionType: CVSelectionType) {

        self.interactionId = interactionId
        self.interactionType = interactionType
        self.isForwardable = isForwardable
        self.selectionType = selectionType
    }

    init(interaction: TSInteraction,
         selectionType: CVSelectionType) {

        self.interactionId = interaction.uniqueId
        self.interactionType = interaction.interactionType
        if let message = interaction as? TSMessage {
            self.isForwardable = (message.hasRenderableContent() &&
                                    !message.isViewOnceMessage &&
                                    !message.wasRemotelyDeleted)
        } else {
            self.isForwardable = false
        }
        self.selectionType = selectionType
    }
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

    public var interactionCount: Int { itemMap.count }

    public func add(interaction: TSInteraction, selectionType: CVSelectionType) {
        AssertIsOnMainThread()

        guard !selectionType.isEmpty else {
            owsFailDebug("Cannot add or remote empty selection type.")
            return
        }

        let interactionId = interaction.uniqueId
        owsAssertDebug(!isSelected(interactionId, selectionType: selectionType))

        if let oldItem = itemMap[interactionId] {
            let newItem = CVSelectionItem(interaction: interaction,
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
            let newItem = CVSelectionItem(interaction: interaction,
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
        owsAssertDebug(isSelected(interactionId, selectionType: selectionType))

        if let oldItem = itemMap[interactionId] {
            let newItem = CVSelectionItem(interaction: interaction,
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

    public var selectionItems: [CVSelectionItem] {
        AssertIsOnMainThread()

        return Array(itemMap.values)
    }
}

// MARK: -

extension CVSelectionState {

    public var selectionCanBeDeleted: Bool {
        guard !itemMap.isEmpty else {
            return false
        }
        for item in itemMap.values {
            switch item.interactionType {
            case .threadDetails, .unknownThreadWarning, .defaultDisappearingMessageTimer, .typingIndicator, .unreadIndicator, .dateHeader:
                return false
            case .info, .error, .call:
                break
            case .incomingMessage, .outgoingMessage:
                break
            case .unknown:
                owsFailDebug("Unknown interaction type.")
                return false
            }
        }
        return true
    }

    public var selectionCanBeForwarded: Bool {
        guard !itemMap.isEmpty else {
            return false
        }
        let maxForwardCount: Int = 32
        guard itemMap.count <= maxForwardCount else {
            return false
        }
        for item in itemMap.values {
            guard item.isForwardable else {
                return false
            }

            switch item.interactionType {
            case .threadDetails, .unknownThreadWarning, .defaultDisappearingMessageTimer, .typingIndicator, .unreadIndicator, .dateHeader:
                return false
            case .info, .error, .call:
                return false
            case .incomingMessage, .outgoingMessage:
                break
            case .unknown:
                owsFailDebug("Unknown interaction type.")
                return false
            }
        }
        return true
    }
}

// MARK: -

extension ConversationViewController {

    public func buildSelectionToolbar() -> MessageActionsToolbar {
        let deleteMessagesAction = MessageAction(
            .delete,
            accessibilityLabel: NSLocalizedString("MESSAGE_ACTION_DELETE_SELECTED_MESSAGES",
                                                  comment: "accessibility label"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action",
                                                                    name: "delete_selected_messages"),
            contextMenuTitle: "Delete Selected",
            contextMenuAttributes: [],
            block: { [weak self] _ in self?.didTapDeleteSelectedItems() }
        )
        let forwardMessagesAction = MessageAction(
            .forward,
            accessibilityLabel: NSLocalizedString("MESSAGE_ACTION_FORWARD_SELECTED_MESSAGES",
                                                  comment: "Action sheet button title"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action",
                                                                    name: "forward_selected_messages"),
            contextMenuTitle: "Forward Selected",
            contextMenuAttributes: [],
            block: { [weak self] _ in self?.didTapForwardSelectedItems() }
        )

        let toolbarMode = MessageActionsToolbar.Mode.selection(deleteMessagesAction: deleteMessagesAction,
                                                               forwardMessagesAction: forwardMessagesAction)
        let toolbar = MessageActionsToolbar(mode: toolbarMode)
        toolbar.actionDelegate = self
        return toolbar
    }

    func didTapDeleteSelectedItems() {
        let selectionItems = self.selectionState.selectionItems
        guard !selectionItems.isEmpty else {
            owsFailDebug("Invalid selection.")
            return
        }

        let messageFormat = NSLocalizedString("DELETE_SELECTED_MESSAGES_IN_CONVERSATION_ALERT_%d", tableName: "PluralAware",
                                              comment: "action sheet body. Embeds {{number of selected messages}} which will be deleted.")
        let message = String.localizedStringWithFormat(messageFormat, selectionItems.count)
        let alert = ActionSheetController(title: nil, message: message)
        alert.addAction(OWSActionSheets.cancelAction)

        let delete = ActionSheetAction(title: CommonStrings.deleteForMeButton, style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { [weak self] modalActivityIndicator in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    Self.deleteSelectedItems(selectionItems: selectionItems)
                    modalActivityIndicator.dismiss {
                        self.uiMode = .normal
                    }
                }
            }
        }
        alert.addAction(delete)
        present(alert, animated: true)
    }

    private static func deleteSelectedItems(selectionItems: [CVSelectionItem]) {
        databaseStorage.write { transaction in
            for selectionItem in selectionItems {
                Self.deleteSelectedItem(selectionItem: selectionItem, transaction: transaction)
            }
        }
    }

    private static func deleteSelectedItem(selectionItem: CVSelectionItem,
                                           transaction: SDSAnyWriteTransaction) {
        guard let interaction = TSInteraction.anyFetch(uniqueId: selectionItem.interactionId,
                                                       transaction: transaction) else {
            Logger.warn("Missing interaction.")
            return
        }

        let selectionType = selectionItem.selectionType

        func tryPartialDelete() -> Bool {
            guard let message = interaction as? TSMessage else {
                owsFailDebug("Invalid interaction: \(type(of: interaction)).")
                return false
            }
            guard let componentState = CVLoader.buildStandaloneComponentState(interaction: interaction,
                                                                              transaction: transaction) else {
                owsFailDebug("Could not load componentState.")
                return false
            }
            guard componentState.hasPrimaryAndSecondaryContentForSelection else {
                owsFailDebug("Invalid componentState.")
                return false
            }
            if selectionType == .primaryContent {
                message.removeMediaAndShareAttachments(transaction: transaction)
            } else {
                message.removeBodyText(transaction: transaction)
            }
            return true
        }

        if selectionType == .allContent {
            // Fall through to delete the entire interaction.
        } else if selectionType == .primaryContent ||
                    selectionType == .secondaryContent {
            // Try to partially delete the interaction.
            if tryPartialDelete() {
                return
            }
        } else {
            owsFailDebug("Invalid selectionType: \(selectionType.rawValue).")
        }

        interaction.anyRemove(transaction: transaction)
    }

    func didTapForwardSelectedItems() {
        AssertIsOnMainThread()

        let selectionItems = self.selectionState.selectionItems
        guard !selectionItems.isEmpty else {
            owsFailDebug("Invalid selection.")
            return
        }
        ForwardMessageViewController.present(forSelectionItems: selectionItems, from: self, delegate: self)
    }

    public func updateSelectionButtons() {
        guard let selectionToolbar = self.selectionToolbar else {
            owsFailDebug("Missing selectionToolbar.")
            return
        }

        selectionToolbar.updateContent()

        if let deleteButton = selectionToolbar.buttonItem(for: .delete) {
            deleteButton.isEnabled = (uiMode == .selection &&
                                        selectionState.selectionCanBeDeleted)
        } else {
            owsFailDebug("deleteButton was unexpectedly nil")
            return
        }

        if let forwardButton = selectionToolbar.buttonItem(for: .forward) {
            forwardButton.isEnabled = (uiMode == .selection &&
                                        selectionState.selectionCanBeForwarded)
        } else {
            owsFailDebug("forwardButton was unexpectedly nil")
            return
        }
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
