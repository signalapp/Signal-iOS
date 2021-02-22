
extension ContextMenuVC {

    struct Action {
        let icon: UIImage
        let title: String
        let work: () -> Void

        static func reply(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate) -> Action {
            let title = "Reply"
            return Action(icon: UIImage(named: "ic_reply")!, title: title) { delegate.reply(viewItem) }
        }

        static func copy(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate) -> Action {
            let title = "Copy"
            return Action(icon: UIImage(named: "ic_copy")!, title: title) { delegate.copy(viewItem) }
        }

        static func copySessionID(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate) -> Action {
            let title = "Copy Session ID"
            return Action(icon: UIImage(named: "ic_copy")!, title: title) { delegate.copySessionID(viewItem) }
        }

        static func delete(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate) -> Action {
            let title = "Delete"
            return Action(icon: UIImage(named: "ic_trash")!, title: title) { delegate.delete(viewItem) }
        }

        static func save(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate) -> Action {
            let title = "Save"
            return Action(icon: UIImage(named: "ic_download")!, title: title) { delegate.save(viewItem) }
        }

        static func ban(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate) -> Action {
            let title = "Ban User"
            return Action(icon: UIImage(named: "ic_block")!, title: title) { delegate.ban(viewItem) }
        }
    }

    static func actions(for viewItem: ConversationViewItem, delegate: ContextMenuActionDelegate) -> [Action] {
        func isReplyingAllowed() -> Bool {
            guard let message = viewItem.interaction as? TSOutgoingMessage else { return true }
            switch message.messageState {
            case .failed, .sending: return false
            default: return true
            }
        }
        switch viewItem.messageCellType {
        case .textOnlyMessage:
            var result: [Action] = []
            if isReplyingAllowed() { result.append(Action.reply(viewItem, delegate)) }
            result.append(Action.copy(viewItem, delegate))
            let isGroup = viewItem.isGroupThread
            if isGroup && viewItem.interaction is TSIncomingMessage { result.append(Action.copySessionID(viewItem, delegate)) }
            if !isGroup || viewItem.userCanDeleteGroupMessage { result.append(Action.delete(viewItem, delegate)) }
            if isGroup && viewItem.interaction is TSIncomingMessage && viewItem.userHasModerationPermission { result.append(Action.ban(viewItem, delegate)) }
            return result
        case .mediaMessage, .audio, .genericAttachment:
            var result: [Action] = []
            if isReplyingAllowed() { result.append(Action.reply(viewItem, delegate)) }
            if viewItem.canCopyMedia() { result.append(Action.copy(viewItem, delegate)) }
            if viewItem.canSaveMedia() { result.append(Action.save(viewItem, delegate)) }
            let isGroup = viewItem.isGroupThread
            if isGroup && viewItem.interaction is TSIncomingMessage { result.append(Action.copySessionID(viewItem, delegate)) }
            if !isGroup || viewItem.userCanDeleteGroupMessage { result.append(Action.delete(viewItem, delegate)) }
            if isGroup && viewItem.interaction is TSIncomingMessage && viewItem.userHasModerationPermission { result.append(Action.ban(viewItem, delegate)) }
            return result
        default: return []
        }
    }
}

// MARK: Delegate
protocol ContextMenuActionDelegate {
    
    func reply(_ viewItem: ConversationViewItem)
    func copy(_ viewItem: ConversationViewItem)
    func copySessionID(_ viewItem: ConversationViewItem)
    func delete(_ viewItem: ConversationViewItem)
    func save(_ viewItem: ConversationViewItem)
    func ban(_ viewItem: ConversationViewItem)
}
