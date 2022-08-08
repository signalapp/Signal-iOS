// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionMessagingKit

extension ContextMenuVC {
    struct Action {
        let icon: UIImage?
        let title: String
        let isDismissAction: Bool
        let work: () -> Void

        static func reply(_ cellViewModel: MessageViewModel, _ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: UIImage(named: "ic_reply"),
                title: "context_menu_reply".localized(),
                isDismissAction: false
            ) { delegate?.reply(cellViewModel) }
        }

        static func copy(_ cellViewModel: MessageViewModel, _ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: UIImage(named: "ic_copy"),
                title: "copy".localized(),
                isDismissAction: false
            ) { delegate?.copy(cellViewModel) }
        }

        static func copySessionID(_ cellViewModel: MessageViewModel, _ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: UIImage(named: "ic_copy"),
                title: "vc_conversation_settings_copy_session_id_button_title".localized(),
                isDismissAction: false
            ) { delegate?.copySessionID(cellViewModel) }
        }

        static func delete(_ cellViewModel: MessageViewModel, _ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: UIImage(named: "ic_trash"),
                title: "TXT_DELETE_TITLE".localized(),
                isDismissAction: false
            ) { delegate?.delete(cellViewModel) }
        }

        static func save(_ cellViewModel: MessageViewModel, _ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: UIImage(named: "ic_download"),
                title: "context_menu_save".localized(),
                isDismissAction: false
            ) { delegate?.save(cellViewModel) }
        }

        static func ban(_ cellViewModel: MessageViewModel, _ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: UIImage(named: "ic_block"),
                title: "context_menu_ban_user".localized(),
                isDismissAction: false
            ) { delegate?.ban(cellViewModel) }
        }
        
        static func banAndDeleteAllMessages(_ cellViewModel: MessageViewModel, _ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: UIImage(named: "ic_block"),
                title: "context_menu_ban_and_delete_all".localized(),
                isDismissAction: false
            ) { delegate?.banAndDeleteAllMessages(cellViewModel) }
        }
        
        static func dismiss(_ delegate: ContextMenuActionDelegate?) -> Action {
            return Action(
                icon: nil,
                title: "",
                isDismissAction: true
            ) { delegate?.contextMenuDismissed() }
        }
    }

    static func actions(for cellViewModel: MessageViewModel, currentUserIsOpenGroupModerator: Bool, delegate: ContextMenuActionDelegate?) -> [Action]? {
        // No context items for info messages
        guard cellViewModel.variant == .standardOutgoing || cellViewModel.variant == .standardIncoming else {
            return nil
        }
        
        let canReply: Bool = (
            cellViewModel.variant != .standardOutgoing || (
                cellViewModel.state != .failed &&
                cellViewModel.state != .sending
            )
        )
        let canCopy: Bool = (
            cellViewModel.cellType == .textOnlyMessage || (
                (
                    cellViewModel.cellType == .genericAttachment ||
                    cellViewModel.cellType == .mediaMessage
                ) &&
                (cellViewModel.attachments ?? []).count == 1 &&
                (cellViewModel.attachments ?? []).first?.isVisualMedia == true &&
                (cellViewModel.attachments ?? []).first?.isValid == true && (
                    (cellViewModel.attachments ?? []).first?.state == .downloaded ||
                    (cellViewModel.attachments ?? []).first?.state == .uploaded
                )
            )
        )
        let canSave: Bool = (
            cellViewModel.cellType == .mediaMessage &&
            (cellViewModel.attachments ?? [])
                .filter { attachment in
                    attachment.isValid &&
                    attachment.isVisualMedia && (
                        attachment.state == .downloaded ||
                        attachment.state == .uploaded
                    )
                }.isEmpty == false
        )
        let canCopySessionId: Bool = (
            cellViewModel.variant == .standardIncoming &&
            cellViewModel.threadVariant != .openGroup
        )
        let canDelete: Bool = (
            cellViewModel.threadVariant != .openGroup ||
            currentUserIsOpenGroupModerator
        )
        let canBan: Bool = (
            cellViewModel.threadVariant == .openGroup &&
            currentUserIsOpenGroupModerator
        )
        
        let generatedActions: [Action] = [
            (canReply ? Action.reply(cellViewModel, delegate) : nil),
            (canCopy ? Action.copy(cellViewModel, delegate) : nil),
            (canSave ? Action.save(cellViewModel, delegate) : nil),
            (canCopySessionId ? Action.copySessionID(cellViewModel, delegate) : nil),
            (canDelete ? Action.delete(cellViewModel, delegate) : nil),
            (canBan ? Action.ban(cellViewModel, delegate) : nil),
            (canBan ? Action.banAndDeleteAllMessages(cellViewModel, delegate) : nil)
        ]
        .compactMap { $0 }
        
        guard !generatedActions.isEmpty else { return [] }
        
        return generatedActions.appending(Action.dismiss(delegate))
    }
}

// MARK: - Delegate

protocol ContextMenuActionDelegate {
    func reply(_ cellViewModel: MessageViewModel)
    func copy(_ cellViewModel: MessageViewModel)
    func copySessionID(_ cellViewModel: MessageViewModel)
    func delete(_ cellViewModel: MessageViewModel)
    func save(_ cellViewModel: MessageViewModel)
    func ban(_ cellViewModel: MessageViewModel)
    func banAndDeleteAllMessages(_ cellViewModel: MessageViewModel)
    func contextMenuDismissed()
}
