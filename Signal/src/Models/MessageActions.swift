//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

protocol MessageActionsDelegate: AnyObject {
    func messageActionsShowDetailsForItem(_ itemViewModel: CVItemViewModelImpl)
    func messageActionsReplyToItem(_ itemViewModel: CVItemViewModelImpl)
    func messageActionsForwardItem(_ itemViewModel: CVItemViewModelImpl)
    func messageActionsStartedSelect(initialItem itemViewModel: CVItemViewModelImpl)
    func messageActionsDeleteItem(_ itemViewModel: CVItemViewModelImpl)
    func messageActionsSpeakItem(_ itemViewModel: CVItemViewModelImpl)
    func messageActionsStopSpeakingItem(_ itemViewModel: CVItemViewModelImpl)
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

        if itemViewModel.canCopyOrShareOrSpeakText {
            // If the user started speaking a message and then turns of the "speak selection" OS setting,
            // we still want to let them turn it off.
            if self.speechManager.isSpeaking {
                let stopSpeakingAction = MessageActionBuilder.stopSpeakingMessage(itemViewModel: itemViewModel, delegate: delegate)
                actions.append(stopSpeakingAction)
            } else if UIAccessibility.isSpeakSelectionEnabled {
                let speakAction = MessageActionBuilder.speakMessage(itemViewModel: itemViewModel, delegate: delegate)
                actions.append(speakAction)
            }
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

        if shouldAllowReply {
            let replyAction = MessageActionBuilder.reply(itemViewModel: itemViewModel, delegate: delegate)
            actions.append(replyAction)
        }

        if itemViewModel.canForwardMessage {
            actions.append(MessageActionBuilder.forwardMessage(itemViewModel: itemViewModel, delegate: delegate))
        }

        let selectAction = MessageActionBuilder.selectMessage(itemViewModel: itemViewModel, delegate: delegate)
        actions.append(selectAction)

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

        let selectAction = MessageActionBuilder.selectMessage(itemViewModel: itemViewModel, delegate: delegate)
        actions.append(selectAction)

        return actions
    }

    class func infoMessageActions(itemViewModel: CVItemViewModelImpl, delegate: MessageActionsDelegate) -> [MessageAction] {
        let deleteAction = MessageActionBuilder.deleteMessage(itemViewModel: itemViewModel, delegate: delegate)
        let selectAction = MessageActionBuilder.selectMessage(itemViewModel: itemViewModel, delegate: delegate)
        return [deleteAction, selectAction]
    }
}
