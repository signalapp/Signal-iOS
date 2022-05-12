// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

extension ContextMenuVC {
    struct Action {
        let icon: UIImage?
        let title: String
        let work: () -> Void

        static func reply(_ item: ConversationViewModel.Item, _ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: UIImage(named: "ic_reply"),
                title: "context_menu_reply".localized()
            ) { delegate?.reply(item) }
        }

        static func copy(_ item: ConversationViewModel.Item, _ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: UIImage(named: "ic_copy"),
                title: "copy".localized()
            ) { delegate?.copy(item) }
        }

        static func copySessionID(_ item: ConversationViewModel.Item, _ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: UIImage(named: "ic_copy"),
                title: "vc_conversation_settings_copy_session_id_button_title".localized()
            ) { delegate?.copySessionID(item) }
        }

        static func delete(_ item: ConversationViewModel.Item, _ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: UIImage(named: "ic_trash"),
                title: "TXT_DELETE_TITLE".localized()
            ) { delegate?.delete(item) }
        }

        static func save(_ item: ConversationViewModel.Item, _ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: UIImage(named: "ic_download"),
                title: "context_menu_save".localized()
            ) { delegate?.save(item) }
        }

        static func ban(_ item: ConversationViewModel.Item, _ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: UIImage(named: "ic_block"),
                title: "context_menu_ban_user".localized()
            ) { delegate?.ban(item) }
        }
        
        static func banAndDeleteAllMessages(_ item: ConversationViewModel.Item, _ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: UIImage(named: "ic_block"),
                title: "context_menu_ban_and_delete_all".localized()
            ) { delegate?.banAndDeleteAllMessages(item) }
        }
    }

    static func actions(for item: ConversationViewModel.Item, currentUserIsOpenGroupModerator: Bool, delegate: ContextMenuActionDelegate?) -> [Action]? {
        // No context items for info messages
        guard item.interactionVariant == .standardOutgoing || item.interactionVariant == .standardIncoming else {
            return nil
        }
        
        let canReply: Bool = (
            item.interactionVariant != .standardOutgoing || (
                item.state != .failed &&
                item.state != .sending
            )
        )
        let canCopy: Bool = (
            item.cellType == .textOnlyMessage || (
                (
                    item.cellType == .genericAttachment ||
                    item.cellType == .mediaMessage
                ) &&
                (item.attachments ?? []).count == 1 &&
                (item.attachments ?? []).first?.isVisualMedia == true &&
                (item.attachments ?? []).first?.isValid == true && (
                    (item.attachments ?? []).first?.state == .downloaded ||
                    (item.attachments ?? []).first?.state == .uploaded
                )
            )
        )
        let canSave: Bool = (
            item.cellType == .mediaMessage &&
            (item.attachments ?? [])
                .filter { attachment in
                    attachment.isValid &&
                    attachment.isVisualMedia && (
                        attachment.state == .downloaded ||
                        attachment.state == .uploaded
                    )
                }.isEmpty == false
        )
        let canCopySessionId: Bool = (
            item.interactionVariant == .standardIncoming &&
            item.threadVariant != .openGroup
        )
        let canDelete: Bool = (
            item.threadVariant != .openGroup ||
            currentUserIsOpenGroupModerator
        )
        let canBan: Bool = (
            item.threadVariant == .openGroup &&
            currentUserIsOpenGroupModerator
        )
        
        return [
            (canReply ? Action.reply(item, delegate) : nil),
            (canCopy ? Action.copy(item, delegate) : nil),
            (canSave ? Action.save(item, delegate) : nil),
            (canCopySessionId ? Action.copySessionID(item, delegate) : nil),
            (canDelete ? Action.delete(item, delegate) : nil),
            (canBan ? Action.ban(item, delegate) : nil),
            (canBan ? Action.banAndDeleteAllMessages(item, delegate) : nil)
        ]
        .compactMap { $0 }
    }
}

// MARK: - Delegate

protocol ContextMenuActionDelegate {
    func reply(_ item: ConversationViewModel.Item)
    func copy(_ item: ConversationViewModel.Item)
    func copySessionID(_ item: ConversationViewModel.Item)
    func delete(_ item: ConversationViewModel.Item)
    func save(_ item: ConversationViewModel.Item)
    func ban(_ item: ConversationViewModel.Item)
    func banAndDeleteAllMessages(_ item: ConversationViewModel.Item)
}
