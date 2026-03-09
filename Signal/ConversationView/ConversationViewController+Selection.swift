//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
public import SignalUI
import LibSignalClient

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

// MARK: -

public protocol CVSelectionStateDelegate: AnyObject {
    func selectionStateDidChange()
}

// MARK: -

// In selection mode, represents which interactions (or portions thereof) are currently selected.
public class CVSelectionState: NSObject {
    public weak var delegate: CVSelectionStateDelegate?

    // A map of interaction uniqueId-to-CVSelectionItem.
    //
    // For items in this map, selectionType should never be .none.
    private var itemMap = [String: CVSelectionItem]()

    public var interactionCount: Int { itemMap.count }

    public func add(interaction: TSInteraction, hasRenderableContent: Bool, selectionType: CVSelectionType) {
        AssertIsOnMainThread()

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

    public func add(itemViewModel: CVItemViewModel, selectionType: CVSelectionType) {
        add(
            interaction: itemViewModel.interaction,
            hasRenderableContent: itemViewModel.hasRenderableContent,
            selectionType: selectionType,
        )
    }

    public func remove(interaction: TSInteraction, hasRenderableContent: Bool, selectionType: CVSelectionType) {
        AssertIsOnMainThread()

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

    public func remove(itemViewModel: CVItemViewModel, selectionType: CVSelectionType) {
        remove(
            interaction: itemViewModel.interaction,
            hasRenderableContent: itemViewModel.hasRenderableContent,
            selectionType: selectionType,
        )
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
            case .outgoingMessage where item.selectionType != .allContent:
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
        let adminDeleteManager = DependenciesBridge.shared.adminDeleteManager

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

        var deleteType: AdminDeleteManager.DeleteType = []
        let canDeleteForEveryone: Bool = db.read { tx in
            selectionItems.allSatisfy { selectionItem in
                guard
                    let message = TSMessage.fetchMessageViaCache(
                        uniqueId: selectionItem.interactionId,
                        transaction: tx,
                    )
                else {
                    return false
                }

                if message.isIncoming {
                    deleteType.update(with: .admin)
                } else {
                    deleteType.update(with: .regular)
                }

                let canAdminDelete = adminDeleteManager.canAdminDeleteMessage(message: message, thread: thread, tx: tx)
                return message.canBeRemotelyDeletedByNonAdmin || canAdminDelete
            }
        }

        if canDeleteForEveryone {
            let deleteForEveryoneAction = ActionSheetAction(
                title: CommonStrings.deleteForEveryoneButton,
                style: .destructive,
            ) { [weak self] _ in
                guard let self else { return }
                TSInteraction.showDeleteForEveryoneConfirmationIfNecessary(
                    deleteType: deleteType,
                    completion: {
                        ModalActivityIndicatorViewController.present(
                            fromViewController: self,
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
        let adminDeleteManager = DependenciesBridge.shared.adminDeleteManager

        guard !selectionItems.isEmpty else { return }
        guard let latestThread = TSThread.fetchViaCache(uniqueId: thread.uniqueId, transaction: tx) else {
            return owsFailDebug("Trying to delete messages without a thread.")
        }

        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx) else {
            return owsFailDebug("LocalIdentifiers missing during message deletion.")
        }

        selectionItems.forEach {
            guard
                let message = TSMessage.fetchMessageViaCache(
                    uniqueId: $0.interactionId,
                    transaction: tx,
                )
            else {
                return
            }

            let canAdminDelete = adminDeleteManager.canAdminDeleteMessage(message: message, thread: thread, tx: tx)

            guard
                let deleteMessage = TSInteraction.buildDeleteMessage(
                    thread: thread,
                    message: message,
                    localIdentifiers: localIdentifiers,
                    canAdminDelete: canAdminDelete,
                    tx: tx,
                )
            else {
                return owsFailDebug("Failure to build outgoing delete for everyone.")
            }

            // TODO: pending send state for incoming messages
            (message as? TSOutgoingMessage)?.updateWithRecipientAddressStates(
                deleteMessage.recipientAddressStates,
                tx: tx,
            )

            if message.canBeRemotelyDeletedByNonAdmin {
                do {
                    try TSMessage.tryToRemotelyDeleteMessageAsNonAdmin(
                        fromAuthor: localIdentifiers.aci,
                        sentAtTimestamp: message.timestamp,
                        threadUniqueId: latestThread.uniqueId,
                        serverTimestamp: 0, // TSOutgoingMessage won't have server timestamp.
                        transaction: tx,
                    )
                } catch {
                    return owsFailDebug("Unable to remotely delete message")
                }
            } else if
                canAdminDelete,
                let groupThread = thread as? TSGroupThread
            {
                let originalMessageAuthorAci: Aci?
                if let incomingMessage = (message as? TSIncomingMessage) {
                    originalMessageAuthorAci = incomingMessage.authorAddress.aci
                } else {
                    originalMessageAuthorAci = localIdentifiers.aci
                }

                guard let originalMessageAuthorAci else {
                    owsFailDebug("Unable to admin delete without original message author")
                    return
                }
                do {
                    try DependenciesBridge.shared.adminDeleteManager.tryToAdminDeleteMessage(
                        originalMessageAuthorAci: originalMessageAuthorAci,
                        deleteAuthorAci: localIdentifiers.aci,
                        sentAtTimestamp: message.timestamp,
                        groupThread: groupThread,
                        threadUniqueId: latestThread.uniqueId,
                        serverTimestamp: 0, // TSOutgoingMessage won't have server timestamp.
                        transaction: tx,
                    )
                } catch {
                    return owsFailDebug("Unable to remotely delete message")
                }
            } else {
                owsFailDebug("Unable to delete as admin or as non-admin")
                return
            }

            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: deleteMessage,
            )

            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
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

    public func updateSelectionButtons() {
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
}

// MARK: - Selection

extension ConversationViewController {

    var cancelSelectionBarButtonItem: UIBarButtonItem {
        .cancelButton { [weak self] in
            self?.uiMode = .normal
        }
    }

    var deleteAllBarButtonItem: UIBarButtonItem {
        return .button(
            title: OWSLocalizedString(
                "CONVERSATION_VIEW_DELETE_ALL_MESSAGES",
                comment: "button text to delete all items in the current conversation",
            ),
            style: .plain,
            action: { [weak self] in
                self?.didTapDeleteAll()
            },
        )
    }

    func didTapDeleteAll() {
        let db = DependenciesBridge.shared.db
        let threadSoftDeleteManager = DependenciesBridge.shared.threadSoftDeleteManager

        let thread = self.thread
        let alert = ActionSheetController(title: nil, message: OWSLocalizedString("DELETE_ALL_MESSAGES_IN_CONVERSATION_ALERT_BODY", comment: "action sheet body"))
        alert.addAction(OWSActionSheets.cancelAction)
        let deleteTitle = OWSLocalizedString("DELETE_ALL_MESSAGES_IN_CONVERSATION_BUTTON", comment: "button text")
        let delete = ActionSheetAction(title: deleteTitle, style: .destructive) { [weak self] _ in
            guard let self else { return }
            ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { [weak self] modalActivityIndicator in
                guard let self else { return }
                db.write {
                    threadSoftDeleteManager.removeAllInteractions(
                        thread: thread,
                        sendDeleteForMeSyncMessage: true,
                        tx: $0,
                    )
                }
                DispatchQueue.main.async {
                    modalActivityIndicator.dismiss { [weak self] in
                        guard let self else { return }
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
