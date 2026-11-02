//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

struct CVSelectionType: OptionSet {
    let rawValue: UInt

    static var none: CVSelectionType { CVSelectionType(rawValue: 0) }
    static let primaryContent = CVSelectionType(rawValue: 1 << 0)
    static let secondaryContent = CVSelectionType(rawValue: 1 << 1)
    static var allContent: CVSelectionType { primaryContent.union(secondaryContent) }
}

struct CVSelectionItem {
    let interactionId: String
    let interactionType: OWSInteractionType
    let isForwardable: Bool

    let selectionType: CVSelectionType

    init(
        interactionId: String,
        interactionType: OWSInteractionType,
        isForwardable: Bool,
        selectionType: CVSelectionType,
    ) {

        self.interactionId = interactionId
        self.interactionType = interactionType
        self.isForwardable = isForwardable
        self.selectionType = selectionType
    }

    init(
        interaction: TSInteraction,
        hasRenderableContent: Bool,
        selectionType: CVSelectionType,
    ) {

        self.interactionId = interaction.uniqueId
        self.interactionType = interaction.interactionType
        if let message = interaction as? TSMessage {
            self.isForwardable = (
                hasRenderableContent &&
                    !message.isViewOnceMessage &&
                    !message.wasRemotelyDeleted &&
                    !message.isPoll,
            )
        } else {
            self.isForwardable = false
        }
        self.selectionType = selectionType
    }
}

protocol CVSelectionStateDelegate: AnyObject {
    func selectionStateDidChange()
}

// MARK: -

// In selection mode, represents which interactions (or portions thereof) are currently selected.
class CVSelectionState {
    weak var delegate: CVSelectionStateDelegate?

    // A map of interaction uniqueId-to-CVSelectionItem.
    //
    // For items in this map, selectionType should never be .none.
    private var itemMap = [String: CVSelectionItem]()

    var interactionCount: Int { itemMap.count }

    func add(interaction: TSInteraction, hasRenderableContent: Bool, selectionType: CVSelectionType) {
        guard !selectionType.isEmpty else {
            owsFailDebug("Cannot add or remote empty selection type.")
            return
        }

        let interactionId = interaction.uniqueId
        owsAssertDebug(!isSelected(interactionId, selectionType: selectionType))

        if let oldItem = itemMap[interactionId] {
            let newItem = CVSelectionItem(
                interaction: interaction,
                hasRenderableContent: hasRenderableContent,
                selectionType: oldItem.selectionType.union(selectionType),
            )
            owsAssertDebug(!newItem.selectionType.isEmpty)
            owsAssertDebug(oldItem.interactionId == newItem.interactionId)
            owsAssertDebug(oldItem.interactionType == newItem.interactionType)
            guard oldItem.selectionType != newItem.selectionType else {
                owsFailDebug("Did not change state.")
                return
            }
            itemMap[interactionId] = newItem
        } else {
            let newItem = CVSelectionItem(
                interaction: interaction,
                hasRenderableContent: hasRenderableContent,
                selectionType: selectionType,
            )
            itemMap[interactionId] = newItem
        }
        delegate?.selectionStateDidChange()
    }

    func add(itemViewModel: CVItemViewModel, selectionType: CVSelectionType) {
        add(
            interaction: itemViewModel.interaction,
            hasRenderableContent: itemViewModel.hasRenderableContent,
            selectionType: selectionType,
        )
    }

    func remove(interaction: TSInteraction, hasRenderableContent: Bool, selectionType: CVSelectionType) {
        guard !selectionType.isEmpty else {
            owsFailDebug("Cannot add or remote empty selection type.")
            return
        }

        let interactionId = interaction.uniqueId
        owsAssertDebug(isSelected(interactionId, selectionType: selectionType))

        if let oldItem = itemMap[interactionId] {
            let newItem = CVSelectionItem(
                interaction: interaction,
                hasRenderableContent: hasRenderableContent,
                selectionType: oldItem.selectionType.subtracting(selectionType),
            )
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

    func remove(itemViewModel: CVItemViewModel, selectionType: CVSelectionType) {
        remove(
            interaction: itemViewModel.interaction,
            hasRenderableContent: itemViewModel.hasRenderableContent,
            selectionType: selectionType,
        )
    }

    func isSelected(_ interactionId: String, selectionType: CVSelectionType) -> Bool {
        guard let oldItem = itemMap[interactionId] else {
            return false
        }
        owsAssertDebug(oldItem.selectionType != .none)
        return oldItem.selectionType.contains(selectionType)
    }

    func hasAnySelection(_ interactionId: String) -> Bool {
        guard let oldItem = itemMap[interactionId] else {
            return false
        }
        owsAssertDebug(oldItem.selectionType != .none)
        return true
    }

    func hasAnySelection(interaction: TSInteraction) -> Bool {
        hasAnySelection(interaction.uniqueId)
    }

    func reset() {
        guard !itemMap.isEmpty else {
            return
        }

        itemMap.removeAll()

        delegate?.selectionStateDidChange()
    }

    var selectionItems: [CVSelectionItem] {
        Array(itemMap.values)
    }

    var selectionCanBeDeleted: Bool {
        guard !itemMap.isEmpty else {
            return false
        }
        for item in itemMap.values {
            switch item.interactionType {
            case .threadDetails, .unknownThreadWarning, .defaultDisappearingMessageTimer, .typingIndicator, .unreadIndicator, .dateHeader, .collapseSet:
                return false
            case .outgoingMessage where item.selectionType != .allContent:
                return false
            case .info, .error, .call:
                break
            case .incomingMessage, .outgoingMessage, .releaseNotesMessage:
                break
            case .unknown:
                owsFailDebug("Unknown interaction type.")
                return false
            }
        }
        return true
    }

    var selectionCanBeForwarded: Bool {
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
            case .threadDetails, .unknownThreadWarning, .defaultDisappearingMessageTimer, .typingIndicator, .unreadIndicator, .dateHeader, .collapseSet:
                return false
            case .info, .error, .call:
                return false
            case .incomingMessage, .outgoingMessage, .releaseNotesMessage:
                break
            case .unknown:
                owsFailDebug("Unknown interaction type.")
                return false
            }
        }
        return true
    }
}

extension ConversationViewController {

    func buildSelectionToolbar() -> MessageActionsToolbar {
        let deleteMessagesAction = MessageAction(
            .delete,
            accessibilityLabel: OWSLocalizedString(
                "MESSAGE_ACTION_DELETE_SELECTED_MESSAGES",
                comment: "accessibility label",
            ),
            accessibilityIdentifier: UIView.accessibilityIdentifier(
                containerName: "message_action",
                name: "delete_selected_messages",
            ),
            contextMenuTitle: "Delete Selected",
            contextMenuAttributes: [],
            block: { [weak self] _ in self?.didTapDeleteSelectedItems() },
        )
        let forwardMessagesAction = MessageAction(
            .forward,
            accessibilityLabel: OWSLocalizedString(
                "MESSAGE_ACTION_FORWARD_SELECTED_MESSAGES",
                comment: "Action sheet button title",
            ),
            accessibilityIdentifier: UIView.accessibilityIdentifier(
                containerName: "message_action",
                name: "forward_selected_messages",
            ),
            contextMenuTitle: "Forward Selected",
            contextMenuAttributes: [],
            block: { [weak self] _ in self?.didTapForwardSelectedItems() },
        )

        let toolbarMode = MessageActionsToolbar.Mode.selection(
            deleteMessagesAction: deleteMessagesAction,
            forwardMessagesAction: forwardMessagesAction,
        )
        let toolbar = MessageActionsToolbar(mode: toolbarMode)
        toolbar.actionDelegate = self
        return toolbar
    }

    func didTapDeleteSelectedItems() {
        let db = DependenciesBridge.shared.db
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        let selectionItems = self.selectionState.selectionItems
        guard !selectionItems.isEmpty else {
            owsFailDebug("Invalid selection.")
            return
        }

        let alert = ActionSheetController(
            title: nil,
            message: String.localizedStringWithFormat(
                OWSLocalizedString(
                    "DELETE_SELECTED_MESSAGES_IN_CONVERSATION_ALERT_%d",
                    tableName: "PluralAware",
                    comment: "action sheet body. Embeds {{number of selected messages}} which will be deleted.",
                ),
                selectionItems.count,
            ),
        )
        alert.addAction(OWSActionSheets.cancelAction)

        let deleteForMeAction = ActionSheetAction(
            title: CommonStrings.deleteForMeButton,
            style: .destructive,
        ) { [weak self] _ in
            guard let self else { return }

            ModalActivityIndicatorViewController.present(
                fromViewController: self,
                title: CommonStrings.deletingModal,
                canCancel: false,
            ) { [weak self] modalActivityIndicator in
                guard let self else { return }
                let thread = self.thread

                await db.awaitableWrite { tx in
                    self.deleteSelectedItemsForMe(
                        selectionItems: selectionItems,
                        thread: thread,
                        tx: tx,
                    )
                }

                modalActivityIndicator.dismiss {
                    self.uiMode = .normal
                }
            }
        }
        alert.addAction(deleteForMeAction)

        // Every selected message must be eligible to offer delete for everyone.
        let deleteTypes: Set<TSMessage.DeleteForEveryoneType>? = db.read { tx in
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
                return nil
            }
            let remoteConfig = RemoteConfig.current
            let now = Date()
            var deleteTypes = Set<TSMessage.DeleteForEveryoneType>()
            for selectionItem in selectionItems {
                guard
                    let message = TSMessage.fetchMessageViaCache(
                        uniqueId: selectionItem.interactionId,
                        transaction: tx,
                    ),
                    let deleteType = message.deleteForEveryoneType(
                        thread: thread,
                        localIdentifiers: localIdentifiers,
                        remoteConfig: remoteConfig,
                        now: now,
                    )
                else {
                    return nil
                }
                deleteTypes.insert(deleteType)
            }
            return deleteTypes
        }

        if let deleteTypes {
            let deleteForEveryoneAction = ActionSheetAction(
                title: CommonStrings.deleteForEveryoneButton,
                style: .destructive,
            ) { [weak self] _ in
                guard let self else { return }
                TSInteraction.showDeleteForEveryoneConfirmationIfNecessary(
                    deleteTypes: deleteTypes,
                    completion: { [self] in
                        ModalActivityIndicatorViewController.present(
                            fromViewController: self,
                            title: CommonStrings.deletingModal,
                            canCancel: false,
                        ) { @MainActor [weak self] modalActivityIndicator in
                            guard let self else { return }
                            let thread = self.thread
                            await db.awaitableWrite { tx in
                                self.deleteSelectedItemsForEveryone(
                                    selectionItems: selectionItems,
                                    thread: thread,
                                    tx: tx,
                                )
                            }

                            modalActivityIndicator.dismiss {
                                self.uiMode = .normal
                            }
                        }
                    },
                )
            }
            alert.addAction(deleteForEveryoneAction)
        }

        present(alert, animated: true)
    }

    private func deleteSelectedItemsForMe(
        selectionItems: [CVSelectionItem],
        thread: TSThread,
        tx: DBWriteTransaction,
    ) {
        let interactionDeleteManager = DependenciesBridge.shared.interactionDeleteManager

        let interactionsToDelete = selectionItems.compactMap { item in
            TSInteraction.fetchViaCache(
                uniqueId: item.interactionId,
                transaction: tx,
            )
        }

        interactionDeleteManager.delete(
            interactions: interactionsToDelete,
            sideEffects: .custom(
                deleteForMeSyncMessage: .sendSyncMessage(interactionsThread: thread),
            ),
            tx: tx,
        )
    }

    private func deleteSelectedItemsForEveryone(
        selectionItems: [CVSelectionItem],
        thread: TSThread,
        tx: DBWriteTransaction,
    ) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        guard let latestThread = TSThread.fetchViaCache(uniqueId: thread.uniqueId, transaction: tx) else {
            return owsFailDebug("Trying to delete messages without a thread.")
        }
        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            return owsFailDebug("LocalIdentifiers missing during message deletion.")
        }

        for selectionItem in selectionItems {
            guard
                let message = TSMessage.fetchMessageViaCache(
                    uniqueId: selectionItem.interactionId,
                    transaction: tx,
                )
            else {
                continue
            }
            _ = TSInteraction.deleteForEveryone(
                message: message,
                thread: latestThread,
                localIdentifiers: localIdentifiers,
                tx: tx,
            )
        }
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

    func updateSelectionButtons() {
        guard let selectionToolbar = self.selectionToolbar else {
            owsFailDebug("Missing selectionToolbar.")
            return
        }

        selectionToolbar.updateContent()

        if let deleteButton = selectionToolbar.buttonItem(for: .delete) {
            deleteButton.isEnabled = (
                uiMode == .selection &&
                    selectionState.selectionCanBeDeleted,
            )
        } else {
            owsFailDebug("deleteButton was unexpectedly nil")
            return
        }

        if let forwardButton = selectionToolbar.buttonItem(for: .forward) {
            forwardButton.isEnabled = (
                uiMode == .selection &&
                    selectionState.selectionCanBeForwarded,
            )
        } else {
            owsFailDebug("forwardButton was unexpectedly nil")
            return
        }
    }

    var cancelSelectionBarButtonItem: UIBarButtonItem {
        .cancelButton { [weak self] in
            self?.uiMode = .normal
        }
    }

    var deleteAllBarButtonItem: UIBarButtonItem {
        .button(title: OWSLocalizedString(
            "CONVERSATION_VIEW_DELETE_ALL_MESSAGES",
            comment: "button text to delete all items in the current conversation",
        )) { [weak self] in
            self?.didTapDeleteAll()
        }
    }

    func didTapDeleteAll() {
        let db = DependenciesBridge.shared.db
        let threadDeletionManager = DependenciesBridge.shared.threadDeletionManager
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        let thread = self.thread
        let alert = ActionSheetController(title: nil, message: OWSLocalizedString("DELETE_ALL_MESSAGES_IN_CONVERSATION_ALERT_BODY", comment: "action sheet body"))
        alert.addAction(OWSActionSheets.cancelAction)
        let deleteTitle = OWSLocalizedString("DELETE_ALL_MESSAGES_IN_CONVERSATION_BUTTON", comment: "button text")
        let delete = ActionSheetAction(title: deleteTitle, style: .destructive) { [weak self] _ in
            guard let self else { return }
            ModalActivityIndicatorViewController.present(
                fromViewController: self,
                title: CommonStrings.deletingModal,
                canCancel: false,
            ) { [weak self] modal in
                guard let self else { return }
                db.write { tx in
                    let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx).owsFailUnwrap("never registered")
                    threadDeletionManager.removeAllInteractions(
                        thread: thread,
                        deleteForMeSyncMessagePolicy: .send(localIdentifiers),
                        tx: tx,
                    )
                }
                DispatchQueue.main.async { [self] in
                    modal.dismiss { [weak self] in
                        guard let self else { return }
                        self.uiMode = .normal
                    }
                }
            }
        }
        alert.addAction(delete)
        present(alert, animated: true)
    }

    func selectionStateDidChange() {
        updateSelectionButtons()
    }
}
