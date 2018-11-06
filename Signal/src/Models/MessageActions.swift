//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
protocol MessageActionsDelegate: class {
    func messageActionsShowDetailsForItem(_ conversationViewItem: ConversationViewItem)
    func messageActionsReplyToItem(_ conversationViewItem: ConversationViewItem)
}

struct MessageActionBuilder {
    static func reply(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MenuAction {
        return MenuAction(image: #imageLiteral(resourceName: "ic_reply"),
                          title: NSLocalizedString("MESSAGE_ACTION_REPLY", comment: "Action sheet button title"),
                          subtitle: nil,
                          block: { [weak delegate] (_) in
                            delegate?.messageActionsReplyToItem(conversationViewItem)

        })
    }

    static func copyText(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MenuAction {
        return MenuAction(image: #imageLiteral(resourceName: "ic_copy"),
                          title: NSLocalizedString("MESSAGE_ACTION_COPY_TEXT", comment: "Action sheet button title"),
                          subtitle: nil,
                          block: { (_) in
                            conversationViewItem.copyTextAction()
        })
    }

    static func showDetails(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MenuAction {
        return MenuAction(image: #imageLiteral(resourceName: "ic_info"),
                          title: NSLocalizedString("MESSAGE_ACTION_DETAILS", comment: "Action sheet button title"),
                          subtitle: nil,
                          block: { [weak delegate] (_) in
                            delegate?.messageActionsShowDetailsForItem(conversationViewItem)
        })
    }

    static func deleteMessage(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MenuAction {
        return MenuAction(image: #imageLiteral(resourceName: "ic_trash"),
                          title: NSLocalizedString("MESSAGE_ACTION_DELETE_MESSAGE", comment: "Action sheet button title"),
                          subtitle: NSLocalizedString("MESSAGE_ACTION_DELETE_MESSAGE_SUBTITLE", comment: "Action sheet button subtitle"),
                          block: { (_) in
                            conversationViewItem.deleteAction()
        })
    }

    static func copyMedia(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MenuAction {
        return MenuAction(image: #imageLiteral(resourceName: "ic_copy"),
                          title: NSLocalizedString("MESSAGE_ACTION_COPY_MEDIA", comment: "Action sheet button title"),
                          subtitle: nil,
                          block: { (_) in
                            conversationViewItem.copyMediaAction()
        })
    }

    static func saveMedia(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MenuAction {
        return MenuAction(image: #imageLiteral(resourceName: "ic_download"),
                          title: NSLocalizedString("MESSAGE_ACTION_SAVE_MEDIA", comment: "Action sheet button title"),
                          subtitle: nil,
                          block: { (_) in
                            conversationViewItem.saveMediaAction()
        })
    }
}

@objc
class ConversationViewItemActions: NSObject {

    @objc
    class func textActions(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> [MenuAction] {
        var actions: [MenuAction] = []

        let replyAction = MessageActionBuilder.reply(conversationViewItem: conversationViewItem, delegate: delegate)
        actions.append(replyAction)

        if conversationViewItem.hasBodyTextActionContent {
            let copyTextAction = MessageActionBuilder.copyText(conversationViewItem: conversationViewItem, delegate: delegate)
            actions.append(copyTextAction)
        }

        let deleteAction = MessageActionBuilder.deleteMessage(conversationViewItem: conversationViewItem, delegate: delegate)
        actions.append(deleteAction)

        let showDetailsAction = MessageActionBuilder.showDetails(conversationViewItem: conversationViewItem, delegate: delegate)
        actions.append(showDetailsAction)

        return actions
    }

    @objc
    class func mediaActions(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> [MenuAction] {
        var actions: [MenuAction] = []

        let replyAction = MessageActionBuilder.reply(conversationViewItem: conversationViewItem, delegate: delegate)
        actions.append(replyAction)

        if conversationViewItem.hasMediaActionContent {
            if conversationViewItem.canCopyMedia() {
                let copyMediaAction = MessageActionBuilder.copyMedia(conversationViewItem: conversationViewItem, delegate: delegate)
                actions.append(copyMediaAction)
            }
            if conversationViewItem.canSaveMedia() {
                let saveMediaAction = MessageActionBuilder.saveMedia(conversationViewItem: conversationViewItem, delegate: delegate)
                actions.append(saveMediaAction)
            }
        }

        let deleteAction = MessageActionBuilder.deleteMessage(conversationViewItem: conversationViewItem, delegate: delegate)
        actions.append(deleteAction)

        let showDetailsAction = MessageActionBuilder.showDetails(conversationViewItem: conversationViewItem, delegate: delegate)
        actions.append(showDetailsAction)

        return actions
    }

    @objc
    class func quotedMessageActions(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> [MenuAction] {
        let replyAction = MessageActionBuilder.reply(conversationViewItem: conversationViewItem, delegate: delegate)
        let deleteAction = MessageActionBuilder.deleteMessage(conversationViewItem: conversationViewItem, delegate: delegate)
        let showDetailsAction = MessageActionBuilder.showDetails(conversationViewItem: conversationViewItem, delegate: delegate)

        return [replyAction, deleteAction, showDetailsAction]
    }

    @objc
    class func infoMessageActions(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> [MenuAction] {
        let deleteAction = MessageActionBuilder.deleteMessage(conversationViewItem: conversationViewItem, delegate: delegate)

        return [deleteAction]
    }
}
