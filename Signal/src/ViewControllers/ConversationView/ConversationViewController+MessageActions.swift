//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension ConversationViewController {

    func presentContextMenu(with messageActions: [MessageAction],
                            focusedOn cell: UICollectionViewCell,
                            andModel model: CVItemViewModelImpl) {
        let keyboardActive = inputToolbar?.isInputViewFirstResponder ?? false
        let interaction = ChatHistoryContextMenuInteraction(delegate: self, itemViewModel: model, thread: thread, messageActions: messageActions, initiatingGestureRecognizer: collectionViewContextMenuGestureRecognizer, keyboardWasActive: keyboardActive)
        collectionViewActiveContextMenuInteraction = interaction
        cell.addInteraction(interaction)
        let cellCenterPoint = cell.frame.center
        let screenPoint = self.collectionView .convert(cellCenterPoint, from: cell)
        var presentImmediately = false
        if let secondaryClickRecognizer = collectionViewContextMenuSecondaryClickRecognizer, secondaryClickRecognizer.state == .ended {
            presentImmediately = true
        }
        interaction.initiateContextMenuGesture(locationInView: screenPoint, presentImmediately: presentImmediately)
    }

    public var isPresentingContextMenu: Bool {
        if let interaction = viewState.collectionViewActiveContextMenuInteraction, interaction.contextMenuVisible {
            return true
        }

        return false
    }

    @objc
    public func dismissMessageContextMenu(animated: Bool) {
        if let collectionViewActiveContextMenuInteraction = self.collectionViewActiveContextMenuInteraction {
            collectionViewActiveContextMenuInteraction.dismissMenu(animated: animated, completion: { })
        }
    }

    func dismissMessageContextMenuIfNecessary() {
        if shouldDismissMessageContextMenu {
            dismissMessageContextMenu(animated: true)
        }
    }

    var shouldDismissMessageContextMenu: Bool {
        guard let collectionViewActiveContextMenuInteraction = self.collectionViewActiveContextMenuInteraction else {
            return false
        }

        let messageActionInteractionId = collectionViewActiveContextMenuInteraction.itemViewModel.interaction.uniqueId
        // Check whether there is still a view item for this interaction.
        return self.indexPath(forInteractionUniqueId: messageActionInteractionId) == nil
    }

    public func reloadReactionsDetailSheetWithSneakyTransaction() {
        AssertIsOnMainThread()

        guard let reactionsDetailSheet = self.reactionsDetailSheet else {
            return
        }

        let messageId = reactionsDetailSheet.messageId

        guard let indexPath = self.indexPath(forInteractionUniqueId: messageId),
              let renderItem = self.renderItem(forIndex: indexPath.row) else {
            // The message no longer exists, dismiss the sheet.
            dismissReactionsDetailSheet(animated: true)
            return
        }
        guard let reactionState = renderItem.reactionState,
              reactionState.hasReactions else {
            // There are no longer reactions on this message, dismiss the sheet.
            dismissReactionsDetailSheet(animated: true)
            return
        }

        // Update the detail sheet with the latest reaction
        // state, in case the reactions have changed.
        databaseStorage.read { tx in
            reactionsDetailSheet.setReactionState(reactionState, transaction: tx)
        }
    }

    public func dismissReactionsDetailSheet(animated: Bool) {
        AssertIsOnMainThread()

        guard let reactionsDetailSheet = self.reactionsDetailSheet else {
            return
        }

        reactionsDetailSheet.dismiss(animated: animated) {
            self.reactionsDetailSheet = nil
        }
    }
}

extension ConversationViewController: ContextMenuInteractionDelegate {

    public func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint) -> ContextMenuConfiguration? {

        return ContextMenuConfiguration(identifier: UUID() as NSCopying, actionProvider: { [weak self] _ in

            guard let self = self else {
                owsFailDebug("conversationViewController was unexpectedly nil")
                return ContextMenu([])
            }

            var contextMenuActions: [ContextMenuAction] = []
            if let actions = self.collectionViewActiveContextMenuInteraction?.messageActions {

                let actionOrder: [MessageAction.MessageActionType] = [
                    .reply,
                    .forward,
                    .copy,
                    .share,
                    .select,
                    .speak,
                    .stopSpeaking,
                    .info,
                    .delete
                ]

                for type in actionOrder {
                    let actionWithType = actions.first { $0.actionType == type }
                    if let messageAction = actionWithType {
                        contextMenuActions.append(ContextMenuAction(
                            title: messageAction.contextMenuTitle,
                            image: messageAction.contextMenuIcon,
                            attributes: messageAction.contextMenuAttributes,
                            handler: { _ in
                                messageAction.block(nil)
                            }
                        ))
                    }
                }
            }

            return ContextMenu(contextMenuActions)
        })
    }

    public func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: ContextMenuConfiguration) -> ContextMenuTargetedPreview? {

        guard let contextInteraction = interaction as? ChatHistoryContextMenuInteraction else {
            owsFailDebug("Expected ChatHistoryContextMenuInteraction.")
            return nil
        }

        guard let cell = contextInteraction.view as? CVCell else {
            owsFailDebug("Expected context interaction view to be of CVCell type")
            return nil
        }

        guard let componentView = cell.componentView else {
            owsFailDebug("Expected cell to have component view")
            return nil
        }

        var accessories = cell.rootComponent?.contextMenuAccessoryViews(componentView: componentView) ?? []

        // Add reaction bar if necessary
        if thread.canSendReactionToThread && shouldShowReactionPickerForInteraction(contextInteraction.itemViewModel.interaction) {
            let reactionBarAccessory = ContextMenuRectionBarAccessory(thread: self.thread, itemViewModel: contextInteraction.itemViewModel)
            reactionBarAccessory.didSelectReactionHandler = { [weak self] (message: TSMessage, reaction: String, isRemoving: Bool) in

                guard let self = self else {
                    owsFailDebug("conversationViewController was unexpectedly nil")
                    return
                }

                self.databaseStorage.asyncWrite { transaction in
                    ReactionManager.localUserReacted(
                        to: message.uniqueId,
                        emoji: reaction,
                        isRemoving: isRemoving,
                        tx: transaction
                    )
                }
            }
            accessories.append(reactionBarAccessory)
        }

        var alignment: ContextMenuTargetedPreview.Alignment = .center
        let interactionType = contextInteraction.itemViewModel.interaction.interactionType
        let isRTL = CurrentAppContext().isRTL
        if interactionType == .incomingMessage {
            alignment = isRTL ? .right : .left
        } else if interactionType == .outgoingMessage {
            alignment = isRTL ? .left : .right
        }

        if let componentView = cell.componentView, let contentView = componentView.contextMenuContentView?() {
            let preview = ContextMenuTargetedPreview(view: contentView, alignment: alignment, accessoryViews: accessories)
            preview?.auxiliaryView = componentView.contextMenuAuxiliaryContentView?()
            return preview
        } else {
            return ContextMenuTargetedPreview(view: cell, alignment: alignment, accessoryViews: accessories)

        }
    }

    public func contextMenuInteraction(_ interaction: ContextMenuInteraction, willDisplayMenuForConfiguration: ContextMenuConfiguration) {
        // Reset scroll view pan gesture recognizer, so CV does not scroll behind context menu post presentation on user swipe
        collectionView.panGestureRecognizer.isEnabled = false
        collectionView.panGestureRecognizer.isEnabled = true

        if let contextInteraction = interaction as? ChatHistoryContextMenuInteraction, let cell = contextInteraction.view as? CVCell, let componentView = cell.componentView {
            componentView.contextMenuPresentationWillBegin?()
        }

        dismissKeyBoard()
    }

    public func contextMenuInteraction(_ interaction: ContextMenuInteraction, willEndForConfiguration: ContextMenuConfiguration) {

    }

    public func contextMenuInteraction(_ interaction: ContextMenuInteraction, didEndForConfiguration: ContextMenuConfiguration) {
        if let contextInteraction = interaction as? ChatHistoryContextMenuInteraction, let cell = contextInteraction.view as? CVCell, let componentView = cell.componentView {
            componentView.contextMenuPresentationDidEnd?()

            // Restore the keyboard unless the context menu item presented
            // a view controller.
            if contextInteraction.keyboardWasActive {
                if self.presentedViewController == nil {
                    popKeyBoard()
                } else {
                    // If we're not going to restore the keyboard, update
                    // chat history layout.
                    self.loadCoordinator.enqueueReload()
                }
            }
        }

        collectionViewActiveContextMenuInteraction = nil
    }

    public func shouldShowReactionPickerForInteraction(_ interaction: TSInteraction) -> Bool {
        guard !threadViewModel.hasPendingMessageRequest else { return false }
        guard threadViewModel.isLocalUserFullMemberOfThread else { return false }

        switch interaction {
        case let outgoingMessage as TSOutgoingMessage:
            if outgoingMessage.wasRemotelyDeleted { return false }

            switch outgoingMessage.messageState {
            case .failed, .sending, .pending:
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
