
extension ContextMenuVC {

    struct Action {
        let icon: UIImage?
        let title: String
        let tag: String
        let work: () -> Void

        static func reply(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate?) -> Action {
            let title = "Reply"
            let tag = "reply"
            return Action(icon: UIImage(named: "ic_reply")!, title: title, tag: tag) { delegate?.reply(viewItem) }
        }

        static func copy(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate?) -> Action {
            let title = "Copy"
            let tag = "copy"
            return Action(icon: UIImage(named: "ic_copy")!, title: title, tag: tag) { delegate?.copy(viewItem) }
        }

        static func copySessionID(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate?) -> Action {
            let title = "Copy Session ID"
            let tag = "copySessionID"
            return Action(icon: UIImage(named: "ic_copy")!, title: title, tag: tag) { delegate?.copySessionID(viewItem) }
        }

        static func delete(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate?) -> Action {
            let title = "Delete"
            let tag = "delete"
            return Action(icon: UIImage(named: "ic_trash")!, title: title, tag: tag) { delegate?.delete(viewItem) }
        }
        
        static func deleteLocally(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate?) -> Action {
            let title = "Delete for me"
            let tag = "deleteforme"
            return Action(icon: nil, title: title, tag: tag) { delegate?.deleteLocally(viewItem) }
        }
        
        static func deleteForEveryone(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate?) -> Action {
            let tag = "deleteforeveryone"
            var title = "Delete for everyone"
            if !viewItem.isGroupThread {
                title = "Delete for me and \(viewItem.interaction.thread.name())"
            }
            return Action(icon: nil, title: title, tag: tag) { delegate?.deleteForEveryone(viewItem) }
        }

        static func save(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate?) -> Action {
            let title = "Save"
            let tag = "save"
            return Action(icon: UIImage(named: "ic_download")!, title: title, tag: tag) { delegate?.save(viewItem) }
        }

        static func ban(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate?) -> Action {
            let title = "Ban User"
            let tag = "banUser"
            return Action(icon: UIImage(named: "ic_block")!, title: title, tag: tag) { delegate?.ban(viewItem) }
        }
        
        static func banAndDeleteAllMessages(_ viewItem: ConversationViewItem, _ delegate: ContextMenuActionDelegate?) -> Action {
            let title = "Ban and Delete All"
            let tag = "banAndDeleteAll"
            return Action(icon: UIImage(named: "ic_block")!, title: title, tag: tag) { delegate?.banAndDeleteAllMessages(viewItem) }
        }
    }
    
    static func deleteActions(for viewItem: ConversationViewItem, delegate: ContextMenuActionDelegate?) -> [Action] {
        switch viewItem.interaction.interactionType() {
        case .outgoingMessage:
            if let message = viewItem.interaction as? TSMessage, let _ = message.serverHash {
                return [Action.deleteForEveryone(viewItem, delegate), Action.deleteLocally(viewItem, delegate)]
            }
            return [Action.deleteLocally(viewItem, delegate)]
        case .incomingMessage:
            return [Action.deleteLocally(viewItem, delegate)]
        default: return [] // Should never occur
        }
        
    }

    static func actions(for viewItem: ConversationViewItem, delegate: ContextMenuActionDelegate?) -> [Action] {
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
            if isGroup && viewItem.interaction is TSIncomingMessage && viewItem.userHasModerationPermission {
                result.append(Action.ban(viewItem, delegate))
                result.append(Action.banAndDeleteAllMessages(viewItem, delegate))
            }
            return result
        case .mediaMessage, .audio, .genericAttachment:
            var result: [Action] = []
            if isReplyingAllowed() { result.append(Action.reply(viewItem, delegate)) }
            if viewItem.canCopyMedia() { result.append(Action.copy(viewItem, delegate)) }
            if viewItem.canSaveMedia() { result.append(Action.save(viewItem, delegate)) }
            let isGroup = viewItem.isGroupThread
            if isGroup && viewItem.interaction is TSIncomingMessage { result.append(Action.copySessionID(viewItem, delegate)) }
            if !isGroup || viewItem.userCanDeleteGroupMessage { result.append(Action.delete(viewItem, delegate)) }
            if isGroup && viewItem.interaction is TSIncomingMessage && viewItem.userHasModerationPermission {
                result.append(Action.ban(viewItem, delegate))
                result.append(Action.banAndDeleteAllMessages(viewItem, delegate))
            }
            return result
        default: return []
        }
    }
}

// MARK: Delegate
protocol ContextMenuActionDelegate : class {
    
    func reply(_ viewItem: ConversationViewItem)
    func copy(_ viewItem: ConversationViewItem)
    func copySessionID(_ viewItem: ConversationViewItem)
    func delete(_ viewItem: ConversationViewItem)
    func deleteLocally(_ viewItem: ConversationViewItem)
    func deleteForEveryone(_ viewItem: ConversationViewItem)
    func save(_ viewItem: ConversationViewItem)
    func ban(_ viewItem: ConversationViewItem)
    func banAndDeleteAllMessages(_ viewItem: ConversationViewItem)
}
