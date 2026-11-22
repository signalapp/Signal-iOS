//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public final class SendStickerFlow: ConversationPickerDelegate {
    private let db: DB

    private let stickerMetadata: any StickerMetadata
    private let stickerManager: StickerManager
    private let selection = ConversationPickerSelection()
    private weak var navigationController: UINavigationController?

    public init(stickerMetadata: any StickerMetadata, stickerManager: StickerManager, db: DB) {
        self.stickerMetadata = stickerMetadata
        self.stickerManager = stickerManager
        self.db = db
    }

    public func present(from viewController: UIViewController) {
        let picker = ConversationPickerViewController(selection: selection)
        picker.pickerDelegate = self
        let nav = OWSNavigationController(rootViewController: picker)
        self.navigationController = nav
        viewController.present(nav, animated: true)
    }

    public func sendSticker(conversations: [ConversationItem]) {
        let threads: [TSThread] = db.write { tx in
            conversations.compactMap { conversation -> TSThread? in
                guard let thread = conversation.getOrCreateThread(transaction: tx) else {
                    owsFailDebug("Missing thread for conversation item.")
                    return nil
                }
                return thread
            }
        }

        for thread in threads {
            ThreadUtil.enqueueMessage(
                withSticker: stickerMetadata,
                quotedReplyDraft: nil,
                thread: thread,
            )
        }
    }

    // MARK: ConversationPickerDelegate

    public func conversationPickerSelectionDidChange(_ conversationPickerViewController: ConversationPickerViewController) {}

    public func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController) {
        conversationPickerViewController.dismiss(animated: true)
        sendSticker(conversations: selection.conversations)
    }

    public func conversationPickerCanCancel(_ conversationPickerViewController: ConversationPickerViewController) -> Bool {
        return true
    }

    public func conversationPickerDidCancel(_ conversationPickerViewController: ConversationPickerViewController) {
        self.navigationController?.dismiss(animated: true)
    }

    public func approvalMode(_ conversationPickerViewController: ConversationPickerViewController) -> ApprovalMode {
        return .send
    }

    public func conversationPickerDidBeginEditingText() {}

    public func conversationPickerSearchBarActiveDidChange(_ conversationPickerViewController: ConversationPickerViewController) {}
}
