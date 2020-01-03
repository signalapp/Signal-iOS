//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
protocol MessageActionsDelegate: class {
    func messageActionsShowDetailsForItem(_ conversationViewItem: ConversationViewItem)
    func messageActionsReplyToItem(_ conversationViewItem: ConversationViewItem)
    func messageActionsForwardItem(_ conversationViewItem: ConversationViewItem)
}

// MARK: -

struct MessageActionBuilder {
    static func reply(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MessageAction {
        let image = Theme.iconImage(.messageActionReply)
        return MessageAction(image: image,
                             accessibilityLabel: NSLocalizedString("MESSAGE_ACTION_REPLY", comment: "Action sheet button title"),
                             accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "reply"),
                             block: { [weak delegate] (_) in
                                delegate?.messageActionsReplyToItem(conversationViewItem)

        })
    }

    static func copyText(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MessageAction {
        let image = Theme.iconImage(.messageActionCopy)
        return MessageAction(image: image,
                             accessibilityLabel: NSLocalizedString("MESSAGE_ACTION_COPY_TEXT", comment: "Action sheet button title"),
                             accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "copy_text"),
                             block: { (_) in
                                conversationViewItem.copyTextAction()
        })
    }

    static func showDetails(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MessageAction {
        let image = Theme.iconImage(.info)
        return MessageAction(image: image,
                             accessibilityLabel: NSLocalizedString("MESSAGE_ACTION_DETAILS", comment: "Action sheet button title"),
                             accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "show_details"),
                             block: { [weak delegate] (_) in
                                delegate?.messageActionsShowDetailsForItem(conversationViewItem)
        })
    }

    static func deleteMessage(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MessageAction {
        let image = Theme.iconImage(.messageActionDelete)
        return MessageAction(image: image,
                             accessibilityLabel: NSLocalizedString("MESSAGE_ACTION_DELETE_MESSAGE", comment: "Action sheet button title"),
                             accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "delete_message"),
                             block: { (_) in
                                conversationViewItem.deleteAction()
        })
    }

    static func shareMedia(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MessageAction {
        let image = Theme.iconImage(.messageActionShare)
        return MessageAction(image: image,
                             accessibilityLabel: NSLocalizedString("MESSAGE_ACTION_SHARE_MEDIA", comment: "Action sheet button title"),
                             accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "share_media"),
                             block: { sender in
                                conversationViewItem.shareMediaAction(sender)
        })
    }

    static func forwardMessage(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MessageAction {
        let image = Theme.iconImage(.messageActionForward)
        return MessageAction(image: image,
                             accessibilityLabel: NSLocalizedString("MESSAGE_ACTION_FORWARD_MESSAGE", comment: "Action sheet button title"),
                             accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "forward_message"),
                             block: { [weak delegate] (_) in
                                delegate?.messageActionsForwardItem(conversationViewItem)
        })
    }
}

@objc
class ConversationViewItemActions: NSObject {

    @objc
    class func textActions(conversationViewItem: ConversationViewItem, shouldAllowReply: Bool, delegate: MessageActionsDelegate) -> [MessageAction] {
        var actions: [MessageAction] = []

        let showDetailsAction = MessageActionBuilder.showDetails(conversationViewItem: conversationViewItem, delegate: delegate)
        actions.append(showDetailsAction)

        let deleteAction = MessageActionBuilder.deleteMessage(conversationViewItem: conversationViewItem, delegate: delegate)
        actions.append(deleteAction)

        if conversationViewItem.hasBodyTextActionContent {
            let copyTextAction = MessageActionBuilder.copyText(conversationViewItem: conversationViewItem, delegate: delegate)
            actions.append(copyTextAction)
        }

        if shouldAllowReply {
            let replyAction = MessageActionBuilder.reply(conversationViewItem: conversationViewItem, delegate: delegate)
            actions.append(replyAction)
        }

        if conversationViewItem.canForwardMessage() {
            actions.append(MessageActionBuilder.forwardMessage(conversationViewItem: conversationViewItem, delegate: delegate))
        }

        return actions
    }

    @objc
    class func mediaActions(conversationViewItem: ConversationViewItem, shouldAllowReply: Bool, delegate: MessageActionsDelegate) -> [MessageAction] {
        var actions: [MessageAction] = []

        let showDetailsAction = MessageActionBuilder.showDetails(conversationViewItem: conversationViewItem, delegate: delegate)
        actions.append(showDetailsAction)

        let deleteAction = MessageActionBuilder.deleteMessage(conversationViewItem: conversationViewItem, delegate: delegate)
        actions.append(deleteAction)

        if conversationViewItem.hasMediaActionContent {
            if conversationViewItem.canShareMedia() {
                let copyMediaAction = MessageActionBuilder.shareMedia(conversationViewItem: conversationViewItem, delegate: delegate)
                actions.append(copyMediaAction)
            }
        }

        if shouldAllowReply {
            let replyAction = MessageActionBuilder.reply(conversationViewItem: conversationViewItem, delegate: delegate)
            actions.append(replyAction)
        }

        if conversationViewItem.canForwardMessage() {
            actions.append(MessageActionBuilder.forwardMessage(conversationViewItem: conversationViewItem, delegate: delegate))
        }

        return actions
    }

    @objc
    class func quotedMessageActions(conversationViewItem: ConversationViewItem, shouldAllowReply: Bool, delegate: MessageActionsDelegate) -> [MessageAction] {
        var actions: [MessageAction] = []

        let showDetailsAction = MessageActionBuilder.showDetails(conversationViewItem: conversationViewItem, delegate: delegate)
        actions.append(showDetailsAction)

        let deleteAction = MessageActionBuilder.deleteMessage(conversationViewItem: conversationViewItem, delegate: delegate)
        actions.append(deleteAction)

        if shouldAllowReply {
            let replyAction = MessageActionBuilder.reply(conversationViewItem: conversationViewItem, delegate: delegate)
            actions.append(replyAction)
        }

        if conversationViewItem.canForwardMessage() {
            actions.append(MessageActionBuilder.forwardMessage(conversationViewItem: conversationViewItem, delegate: delegate))
        }

        return actions
    }

    @objc
    class func infoMessageActions(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> [MessageAction] {
        let deleteAction = MessageActionBuilder.deleteMessage(conversationViewItem: conversationViewItem, delegate: delegate)
        return [deleteAction]
    }
}
