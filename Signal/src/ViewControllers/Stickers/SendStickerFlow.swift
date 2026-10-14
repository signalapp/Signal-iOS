//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class SendStickerFlow: ConversationPickerDelegate {
    private let db: DB

    private let stickerMetadata: any StickerMetadata
    private let selection = ConversationPickerSelection()
    private weak var navigationController: UINavigationController?

    init(stickerMetadata: any StickerMetadata, db: DB) {
        self.stickerMetadata = stickerMetadata
        self.db = db
    }

    func present(from viewController: UIViewController) {
        let picker = ConversationPickerViewController(selection: selection)
        picker.pickerDelegate = self
        let nav = OWSNavigationController(rootViewController: picker)
        self.navigationController = nav
        viewController.present(nav, animated: true)
    }

    func sendSticker(conversations: [ConversationItem]) {
        let threads: [TSThread] = db.write { tx in
            conversations.compactMap { conversation -> TSThread? in
                guard let thread = conversation.getOrCreateThread(transaction: tx) else {
                    owsFailDebug("Missing thread for conversation item.")
                    return nil
                }
                return thread
            }
        }

        let stickerInfo = stickerMetadata.stickerInfo
        let installed = StickerManager.isStickerInstalled(stickerInfo: stickerInfo)

        for thread in threads {
            if installed {
                ThreadUtil.enqueueMessage(withInstalledSticker: stickerInfo, quotedReplyDraft: nil, thread: thread)
            } else {
                do {
                    let stickerData = try stickerMetadata.readStickerData()
                    ThreadUtil.enqueueMessage(
                        withUninstalledSticker: stickerMetadata,
                        stickerData: stickerData,
                        thread: thread,
                    )
                } catch {
                    owsFailDebug("Failed to send sticker: \(error)")
                }
            }
        }
    }

    // MARK: ConversationPickerDelegate

    func conversationPickerSelectionDidChange(_ conversationPickerViewController: ConversationPickerViewController) {}

    func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController) {
        conversationPickerViewController.dismiss(animated: true)
        sendSticker(conversations: selection.conversations)
    }

    func conversationPickerCanCancel(_ conversationPickerViewController: ConversationPickerViewController) -> Bool {
        return true
    }

    func conversationPickerDidCancel(_ conversationPickerViewController: ConversationPickerViewController) {
        self.navigationController?.dismiss(animated: true)
    }

    func approvalMode(_ conversationPickerViewController: ConversationPickerViewController) -> ApprovalMode {
        return .send
    }

    func conversationPickerDidBeginEditingText() {}

    func conversationPickerSearchBarActiveDidChange(_ conversationPickerViewController: ConversationPickerViewController) {}
}
