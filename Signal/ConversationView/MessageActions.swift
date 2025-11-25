//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

protocol MessageActionsDelegate: AnyObject {
    func messageActionsShowDetailsForItem(_ itemViewModel: CVItemViewModelImpl)
    func messageActionsReplyToItem(_ itemViewModel: CVItemViewModelImpl)
    func messageActionsForwardItem(_ itemViewModel: CVItemViewModelImpl)
    func messageActionsStartedSelect(initialItem itemViewModel: CVItemViewModelImpl)
    func messageActionsDeleteItem(_ itemViewModel: CVItemViewModelImpl)
    func messageActionsSpeakItem(_ itemViewModel: CVItemViewModelImpl)
    func messageActionsStopSpeakingItem(_ itemViewModel: CVItemViewModelImpl)
    func messageActionsEditItem(_ itemViewModel: CVItemViewModelImpl)
    func messageActionsShowPaymentDetails(_ itemViewModel: CVItemViewModelImpl)
    func messageActionsEndPoll(_ itemViewModel: CVItemViewModelImpl)
    func messageActionsChangePinStatus(_ itemViewModel: CVItemViewModelImpl, pin: Bool)
}

// MARK: -

struct MessageActionBuilder {
    static func reply(itemViewModel: CVItemViewModelImpl, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(.reply,
                             accessibilityLabel: OWSLocalizedString("MESSAGE_ACTION_REPLY", comment: "Action sheet button title"),
                             accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "reply"),
                             contextMenuTitle: OWSLocalizedString("CONTEXT_MENU_REPLY", comment: "Context menu button title"),
                             contextMenuAttributes: [],
                             block: { [weak delegate] (_) in
                                delegate?.messageActionsReplyToItem(itemViewModel)

        })
    }

    static func copyText(itemViewModel: CVItemViewModelImpl, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(.copy,
                             accessibilityLabel: OWSLocalizedString("MESSAGE_ACTION_COPY_TEXT", comment: "Action sheet button title"),
                             accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "copy_text"),
                             contextMenuTitle: OWSLocalizedString("CONTEXT_MENU_COPY", comment: "Context menu button title"),
                             contextMenuAttributes: [],
                             block: { (_) in
                                itemViewModel.copyTextAction()
        })
    }

    static func showDetails(itemViewModel: CVItemViewModelImpl, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(.info,
                             accessibilityLabel: OWSLocalizedString("MESSAGE_ACTION_DETAILS", comment: "Action sheet button title"),
                             accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "show_details"),
                             contextMenuTitle: OWSLocalizedString("CONTEXT_MENU_DETAILS", comment: "Context menu button title"),
                             contextMenuAttributes: [],
                             block: { [weak delegate] (_) in
                                delegate?.messageActionsShowDetailsForItem(itemViewModel)
        })
    }

    static func deleteMessage(itemViewModel: CVItemViewModelImpl, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(.delete,
                             accessibilityLabel: OWSLocalizedString("MESSAGE_ACTION_DELETE_MESSAGE", comment: "Action sheet button title"),
                             accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "delete_message"),
                             contextMenuTitle: OWSLocalizedString("CONTEXT_MENU_DELETE_MESSAGE", comment: "Context menu button title"),
                             contextMenuAttributes: [.destructive],
                             block: { [weak delegate] (_) in
                                delegate?.messageActionsDeleteItem(itemViewModel)
        })
    }

    static func shareMedia(itemViewModel: CVItemViewModelImpl, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(.share,
                             accessibilityLabel: OWSLocalizedString("MESSAGE_ACTION_SHARE_MEDIA", comment: "Action sheet button title"),
                             accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "share_media"),
                             contextMenuTitle: OWSLocalizedString("CONTEXT_MENU_SHARE_MEDIA", comment: "Context menu button title"),
                             contextMenuAttributes: [],
                             block: { sender in
                                itemViewModel.shareMediaAction(sender: sender)
        })
    }

    static func saveMedia(itemViewModel: CVItemViewModelImpl, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(.save,
                             accessibilityLabel: OWSLocalizedString("MESSAGE_ACTION_SAVE_MEDIA", comment: "Action sheet button title"),
                             accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "save_media"),
                             contextMenuTitle: OWSLocalizedString("CONTEXT_MENU_SAVE_MEDIA", comment: "Context menu button title"),
                             contextMenuAttributes: [],
                             block: { _ in
            itemViewModel.saveMediaAction()
        })
    }

    static func forwardMessage(itemViewModel: CVItemViewModelImpl, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(.forward,
                             accessibilityLabel: OWSLocalizedString("MESSAGE_ACTION_FORWARD_MESSAGE", comment: "Action sheet button title"),
                             accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "forward_message"),
                             contextMenuTitle: OWSLocalizedString("CONTEXT_MENU_FORWARD_MESSAGE", comment: "Context menu button title"),
                             contextMenuAttributes: [],
                             block: { [weak delegate] (_) in
                                delegate?.messageActionsForwardItem(itemViewModel)
        })
    }

    static func selectMessage(itemViewModel: CVItemViewModelImpl, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(.select,
                             accessibilityLabel: OWSLocalizedString("MESSAGE_ACTION_SELECT_MESSAGE", comment: "Action sheet accessibility label"),
                             accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "select_message"),
                             contextMenuTitle: OWSLocalizedString("CONTEXT_MENU_SELECT_MESSAGE", comment: "Context menu button title"),
                             contextMenuAttributes: [],
                             block: { [weak delegate] (_) in
                                delegate?.messageActionsStartedSelect(initialItem: itemViewModel)
        })
    }

    static func editMessage(itemViewModel: CVItemViewModelImpl, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(
            .edit,
            accessibilityLabel: NSLocalizedString("MESSAGE_ACTION_EDIT_MESSAGE", comment: "Action sheet edit message accessibility label"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "edit_message"),
            contextMenuTitle: NSLocalizedString("CONTEXT_MENU_EDIT_MESSAGE", comment: "Context menu edit button title"),
            contextMenuAttributes: [],
            block: { [weak delegate] (_) in
                delegate?.messageActionsEditItem(itemViewModel)
            })
    }

    static func showPaymentDetails(
        itemViewModel: CVItemViewModelImpl,
        delegate: MessageActionsDelegate
    ) -> MessageAction {
        return MessageAction(
            .showPaymentDetails,
            accessibilityLabel: OWSLocalizedString("MESSAGE_ACTION_PAYMENT_DETAILS", comment: "Action sheet button title"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "payment_details"),
            contextMenuTitle: OWSLocalizedString("CONTEXT_MENU_PAYMENT_DETAILS", comment: "Context menu button title"),
            contextMenuAttributes: [],
            block: { [weak delegate] (_) in
                delegate?.messageActionsShowPaymentDetails(itemViewModel)
            }
        )
    }

    static func speakMessage(itemViewModel: CVItemViewModelImpl, delegate: MessageActionsDelegate) -> MessageAction {
        MessageAction(
            .speak,
            accessibilityLabel: OWSLocalizedString("MESSAGE_ACTION_SPEAK_MESSAGE", comment: "Action sheet accessibility label"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "speak_message"),
            contextMenuTitle: OWSLocalizedString("CONTEXT_MENU_SPEAK_MESSAGE", comment: "Context menu button title"),
            contextMenuAttributes: [],
            block: { [weak delegate] _ in
                delegate?.messageActionsSpeakItem(itemViewModel)
            }
        )
    }

    static func stopSpeakingMessage(itemViewModel: CVItemViewModelImpl, delegate: MessageActionsDelegate) -> MessageAction {
        MessageAction(
            .stopSpeaking,
            accessibilityLabel: OWSLocalizedString("MESSAGE_ACTION_STOP_SPEAKING_MESSAGE", comment: "Action sheet accessibility label"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "stop_speaking_message"),
            contextMenuTitle: OWSLocalizedString("CONTEXT_MENU_STOP_SPEAKING_MESSAGE", comment: "Context menu button title"),
            contextMenuAttributes: [],
            block: { [weak delegate] _ in
                delegate?.messageActionsStopSpeakingItem(itemViewModel)
            }
        )
    }

    static func endPoll(
        itemViewModel: CVItemViewModelImpl,
        delegate: MessageActionsDelegate
    ) -> MessageAction {
        return MessageAction(
            .endPoll,
            accessibilityLabel: OWSLocalizedString("POLL_DETAILS_END_POLL", comment: "Label for button to end a poll"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "end_poll"),
            contextMenuTitle: OWSLocalizedString("POLL_DETAILS_END_POLL", comment: "Label for button to end a poll"),
            contextMenuAttributes: [],
            block: { [weak delegate] (_) in
                delegate?.messageActionsEndPoll(itemViewModel)
            }
        )
    }

    static func changePinStatus(
        itemViewModel: CVItemViewModelImpl,
        delegate: MessageActionsDelegate
    ) -> MessageAction? {
        guard BuildFlags.PinnedMessages.send else {
            return nil
        }

        if let groupThread = itemViewModel.thread as? TSGroupThread,
            let groupModel = groupThread.groupModel as? TSGroupModelV2,
            let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci {
            if groupModel.access.attributes == .administrator && !groupThread.groupModel.groupMembership.isFullMemberAndAdministrator(localAci) {
                Logger.info("Sender does not have permissions to pin/unpin message in group")
                return nil
            }
        }

        guard let footerState = itemViewModel.renderItem.itemViewState.footerState else {
            return nil
        }

        if footerState.isPinnedMessage {
            return MessageAction(
                .unpin,
                accessibilityLabel: OWSLocalizedString("PINNED_MESSAGE_UNPIN_ACTION_TITLE", comment: "Label for button to unpin a message"),
                accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "pin"),
                contextMenuTitle: OWSLocalizedString("PINNED_MESSAGE_UNPIN_ACTION_TITLE", comment: "Label for button to unpin a message"),
                contextMenuAttributes: [],
                block: { [weak delegate] (_) in
                    delegate?.messageActionsChangePinStatus(itemViewModel, pin: false)
                }
            )
        }
        return MessageAction(
            .pin,
            accessibilityLabel: OWSLocalizedString("PINNED_MESSAGE_PIN_ACTION_TITLE", comment: "Label for button to pin a message"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "pin"),
            contextMenuTitle: OWSLocalizedString("PINNED_MESSAGE_PIN_ACTION_TITLE", comment: "Label for button to pin a message"),
            contextMenuAttributes: [],
            block: { [weak delegate] (_) in
                delegate?.messageActionsChangePinStatus(itemViewModel, pin: true)
            }
        )
    }
}

class MessageActions: NSObject {

    class func textActions(itemViewModel: CVItemViewModelImpl, shouldAllowReply: Bool, delegate: MessageActionsDelegate) -> [MessageAction] {
        var actions: [MessageAction] = []

        let showDetailsAction = MessageActionBuilder.showDetails(itemViewModel: itemViewModel, delegate: delegate)
        actions.append(showDetailsAction)

        let deleteAction = MessageActionBuilder.deleteMessage(itemViewModel: itemViewModel, delegate: delegate)
        actions.append(deleteAction)

        if itemViewModel.canCopyOrShareOrSpeakText {
            let copyTextAction = MessageActionBuilder.copyText(itemViewModel: itemViewModel, delegate: delegate)
            actions.append(copyTextAction)
        }

        if shouldAllowReply {
            let replyAction = MessageActionBuilder.reply(itemViewModel: itemViewModel, delegate: delegate)
            actions.append(replyAction)
        }

        if itemViewModel.canForwardMessage {
            actions.append(MessageActionBuilder.forwardMessage(itemViewModel: itemViewModel, delegate: delegate))
        }

        let selectAction = MessageActionBuilder.selectMessage(itemViewModel: itemViewModel, delegate: delegate)
        actions.append(selectAction)

        if itemViewModel.canEditMessage {
            let editAction = MessageActionBuilder.editMessage(itemViewModel: itemViewModel, delegate: delegate)
            actions.append(editAction)
        }

        if itemViewModel.canCopyOrShareOrSpeakText {
            // If the user started speaking a message and then turns of the "speak selection" OS setting,
            // we still want to let them turn it off.
            if AppEnvironment.shared.speechManagerRef.isSpeaking {
                let stopSpeakingAction = MessageActionBuilder.stopSpeakingMessage(itemViewModel: itemViewModel, delegate: delegate)
                actions.append(stopSpeakingAction)
            } else if UIAccessibility.isSpeakSelectionEnabled {
                let speakAction = MessageActionBuilder.speakMessage(itemViewModel: itemViewModel, delegate: delegate)
                actions.append(speakAction)
            }
        }

        if let pinAction = MessageActionBuilder.changePinStatus(itemViewModel: itemViewModel, delegate: delegate) {
            actions.append(pinAction)
        }

        return actions
    }

    class func mediaActions(itemViewModel: CVItemViewModelImpl, shouldAllowReply: Bool, delegate: MessageActionsDelegate) -> [MessageAction] {
        var actions: [MessageAction] = []

        let showDetailsAction = MessageActionBuilder.showDetails(itemViewModel: itemViewModel, delegate: delegate)
        actions.append(showDetailsAction)

        let deleteAction = MessageActionBuilder.deleteMessage(itemViewModel: itemViewModel, delegate: delegate)
        actions.append(deleteAction)

        if itemViewModel.canShareMedia {
            let shareMediaAction = MessageActionBuilder.shareMedia(itemViewModel: itemViewModel, delegate: delegate)
            actions.append(shareMediaAction)
        }

        if itemViewModel.canSaveMedia {
            let saveMediaAction = MessageActionBuilder.saveMedia(itemViewModel: itemViewModel, delegate: delegate)
            actions.append(saveMediaAction)
        }

        if shouldAllowReply {
            let replyAction = MessageActionBuilder.reply(itemViewModel: itemViewModel, delegate: delegate)
            actions.append(replyAction)
        }

        if itemViewModel.canForwardMessage {
            actions.append(MessageActionBuilder.forwardMessage(itemViewModel: itemViewModel, delegate: delegate))
        }

        if itemViewModel.canEditMessage {
            let editAction = MessageActionBuilder.editMessage(itemViewModel: itemViewModel, delegate: delegate)
            actions.append(editAction)
        }

        let selectAction = MessageActionBuilder.selectMessage(itemViewModel: itemViewModel, delegate: delegate)
        actions.append(selectAction)

        if let pinAction = MessageActionBuilder.changePinStatus(itemViewModel: itemViewModel, delegate: delegate) {
            actions.append(pinAction)
        }

        return actions
    }

    class func quotedMessageActions(itemViewModel: CVItemViewModelImpl, shouldAllowReply: Bool, delegate: MessageActionsDelegate) -> [MessageAction] {
        var actions: [MessageAction] = []

        let showDetailsAction = MessageActionBuilder.showDetails(itemViewModel: itemViewModel, delegate: delegate)
        actions.append(showDetailsAction)

        let deleteAction = MessageActionBuilder.deleteMessage(itemViewModel: itemViewModel, delegate: delegate)
        actions.append(deleteAction)

        if shouldAllowReply {
            let replyAction = MessageActionBuilder.reply(itemViewModel: itemViewModel, delegate: delegate)
            actions.append(replyAction)
        }

        if itemViewModel.canForwardMessage {
            actions.append(MessageActionBuilder.forwardMessage(itemViewModel: itemViewModel, delegate: delegate))
        }

        if itemViewModel.canEditMessage {
            let editAction = MessageActionBuilder.editMessage(itemViewModel: itemViewModel, delegate: delegate)
            actions.append(editAction)
        }

        let selectAction = MessageActionBuilder.selectMessage(itemViewModel: itemViewModel, delegate: delegate)
        actions.append(selectAction)

        if let pinAction = MessageActionBuilder.changePinStatus(itemViewModel: itemViewModel, delegate: delegate) {
            actions.append(pinAction)
        }

        return actions
    }

    class func paymentActions(
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool,
        delegate: MessageActionsDelegate
    ) -> [MessageAction] {
        var actions: [MessageAction] = []

        let showDetailsAction = MessageActionBuilder.showDetails(
            itemViewModel: itemViewModel,
            delegate: delegate
        )
        actions.append(showDetailsAction)

        let deleteAction = MessageActionBuilder.deleteMessage(
            itemViewModel: itemViewModel,
            delegate: delegate
        )
        actions.append(deleteAction)

        let showPaymentDetailsAction = MessageActionBuilder.showPaymentDetails(
            itemViewModel: itemViewModel,
            delegate: delegate
        )
        actions.append(showPaymentDetailsAction)

        if shouldAllowReply {
            let replyAction = MessageActionBuilder.reply(
                itemViewModel: itemViewModel,
                delegate: delegate
            )
            actions.append(replyAction)
        }

        let selectAction = MessageActionBuilder.selectMessage(
            itemViewModel: itemViewModel,
            delegate: delegate
        )
        actions.append(selectAction)

        if let pinAction = MessageActionBuilder.changePinStatus(itemViewModel: itemViewModel, delegate: delegate) {
            actions.append(pinAction)
        }

        return actions
    }

    class func pollActions(
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool,
        delegate: MessageActionsDelegate
    ) -> [MessageAction] {
        var actions: [MessageAction] = []

        let showDetailsAction = MessageActionBuilder.showDetails(
            itemViewModel: itemViewModel,
            delegate: delegate
        )
        actions.append(showDetailsAction)

        let deleteAction = MessageActionBuilder.deleteMessage(
            itemViewModel: itemViewModel,
            delegate: delegate
        )
        actions.append(deleteAction)

        if shouldAllowReply {
            let replyAction = MessageActionBuilder.reply(itemViewModel: itemViewModel, delegate: delegate)
            actions.append(replyAction)
        }

        let selectAction = MessageActionBuilder.selectMessage(
            itemViewModel: itemViewModel,
            delegate: delegate
        )
        actions.append(selectAction)

        if let poll = itemViewModel.componentState.poll?.state.poll, poll.ownerIsLocalUser, !poll.isEnded {
            let endPollAction = MessageActionBuilder.endPoll(
                itemViewModel: itemViewModel,
                delegate: delegate
            )
            actions.append(endPollAction)
        }

        if let pinAction = MessageActionBuilder.changePinStatus(itemViewModel: itemViewModel, delegate: delegate) {
            actions.append(pinAction)
        }

        return actions
    }

    class func infoMessageActions(itemViewModel: CVItemViewModelImpl, delegate: MessageActionsDelegate) -> [MessageAction] {
        let deleteAction = MessageActionBuilder.deleteMessage(itemViewModel: itemViewModel, delegate: delegate)
        let selectAction = MessageActionBuilder.selectMessage(itemViewModel: itemViewModel, delegate: delegate)
        return [deleteAction, selectAction]
    }
}
