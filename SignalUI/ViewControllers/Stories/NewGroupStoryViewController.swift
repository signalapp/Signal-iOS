//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

class NewGroupStoryViewController: ConversationPickerViewController {
    var selectItemsInParent: (([StoryConversationItem]) -> Void)?

    init(selectItemsInParent: (([StoryConversationItem]) -> Void)? = nil) {
        self.selectItemsInParent = selectItemsInParent
        super.init(selection: ConversationPickerSelection())
        pickerDelegate = self
        sectionOptions = .groups
        threadFilter = { thread in
            guard let groupThread = thread as? TSGroupThread else { return false }
            return !groupThread.isStorySendEnabled
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("NEW_GROUP_STORY_VIEW_CONTROLLER_TITLE", comment: "Title for the 'new group story' view")
    }
}

extension NewGroupStoryViewController: ConversationPickerDelegate {
    func conversationPickerSelectionDidChange(_ conversationPickerViewController: ConversationPickerViewController) {

    }

    func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController) {
        let selectedConversations = selection.conversations.lazy.compactMap { $0 as? GroupConversationItem }

        databaseStorage.asyncWrite { transaction in
            for conversation in selectedConversations {
                guard let groupThread = conversation.getExistingThread(transaction: transaction) as? TSGroupThread else { continue }
                groupThread.updateWithStorySendEnabled(true, transaction: transaction)
            }
        } completion: {
            self.dismiss(animated: true)
            self.selectItemsInParent?(selectedConversations.map { StoryConversationItem(backingItem: .groupStory($0)) })
        }
    }

    func conversationPickerCanCancel(_ conversationPickerViewController: ConversationPickerViewController) -> Bool {
        return true
    }

    func conversationPickerDidCancel(_ conversationPickerViewController: ConversationPickerViewController) {
        dismiss(animated: true)
    }

    func approvalMode(_ conversationPickerViewController: ConversationPickerViewController) -> ApprovalMode {
        .select
    }

    func conversationPickerDidBeginEditingText() {

    }

    func conversationPickerSearchBarActiveDidChange(_ conversationPickerViewController: ConversationPickerViewController) {

    }
}
