//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc
public class SelectMyStoryRecipientsViewController: BaseMemberViewController {
    let thread: TSPrivateStoryThread
    let mode: TSThreadStoryViewMode
    var recipientSet: OrderedSet<PickedRecipient>
    let originalRecipientSet: OrderedSet<PickedRecipient>

    override var hasUnsavedChanges: Bool { originalRecipientSet != recipientSet }

    let completionBlock: () -> Void

    public required init(thread: TSPrivateStoryThread, mode: TSThreadStoryViewMode, completionBlock: @escaping () -> Void) {
        self.thread = thread
        self.mode = mode
        if thread.storyViewMode == mode {
            self.recipientSet = OrderedSet(thread.addresses.map { .for(address: $0) })
        } else {
            self.recipientSet = OrderedSet()
        }
        self.originalRecipientSet = self.recipientSet
        self.completionBlock = completionBlock
        super.init()

        memberViewDelegate = self
    }

    // MARK: - View Lifecycle

    @objc
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateBarButtons()
    }

    private func updateBarButtons() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(dismissPressed))

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(savePressed))
        navigationItem.rightBarButtonItem?.isEnabled = hasUnsavedChanges

        switch mode {
        case .explicit:
            if recipientSet.isEmpty {
                title = NSLocalizedString(
                    "STORY_SELECT_ALLOWED_CONNECTIONS_VIEW_TITLE",
                    comment: "The title for the 'select connections for story' view.")

            } else {
                let format = NSLocalizedString(
                    "STORY_SELECT_ALLOWED_CONNECTIONS_VIEW_TITLE_%d",
                    tableName: "PluralAware",
                    comment: "The title for the 'select connections for story' view if already some connections are selected. Embeds {{number}} of connections.")
                title = String.localizedStringWithFormat(format, recipientSet.count)
            }
        case .blockList:
            if recipientSet.isEmpty {
                title = NSLocalizedString(
                    "STORY_SELECT_EXCLUDED_CONNECTIONS_VIEW_TITLE",
                    comment: "The title for the 'select excluded connections for story' view.")

            } else {
                let format = NSLocalizedString(
                    "STORY_SELECT_EXCLUDED_CONNECTIONS_VIEW_TITLE_%d",
                    tableName: "PluralAware",
                    comment: "The title for the 'select excluded connections for story' view if already some connections are selected. Embeds {{number}} of excluded connections.")
                title = String.localizedStringWithFormat(format, recipientSet.count)
            }
        case .none:
            owsFailDebug("Unexpected mode")
        }
    }

    // MARK: - Actions

    @objc
    func savePressed() {
        AssertIsOnMainThread()

        databaseStorage.write { transaction in
            self.thread.updateWithStoryViewMode(
                self.mode,
                addresses: self.recipientSet.orderedMembers.compactMap { $0.address },
                transaction: transaction
            )
        }

        completionBlock()

        dismiss(animated: true)
    }
}

// MARK: -

extension SelectMyStoryRecipientsViewController: MemberViewDelegate {
    var memberViewRecipientSet: OrderedSet<PickedRecipient> { recipientSet }

    var memberViewHasUnsavedChanges: Bool { hasUnsavedChanges }

    func memberViewRemoveRecipient(_ recipient: PickedRecipient) {
        recipientSet.remove(recipient)
        updateBarButtons()
    }

    func memberViewAddRecipient(_ recipient: PickedRecipient) {
        recipientSet.append(recipient)
        updateBarButtons()
    }

    func memberViewCanAddRecipient(_ recipient: PickedRecipient) -> Bool { true }

    func memberViewWillRenderRecipient(_ recipient: PickedRecipient) {}

    func memberViewPrepareToSelectRecipient(_ recipient: PickedRecipient) -> AnyPromise { AnyPromise(Promise.value(())) }

    func memberViewShowInvalidRecipientAlert(_ recipient: PickedRecipient) {}

    func memberViewNoUuidSubtitleForRecipient(_ recipient: PickedRecipient) -> String? { nil }

    func memberViewGetRecipientStateForRecipient(_ recipient: PickedRecipient, transaction: SDSAnyReadTransaction) -> RecipientPickerRecipientState? { nil }

    func memberViewShouldShowMemberCount() -> Bool { false }

    func memberViewShouldAllowBlockedSelection() -> Bool { mode == .blockList }

    func memberViewMemberCountForDisplay() -> Int { recipientSet.count }

    func memberViewIsPreExistingMember(_ recipient: PickedRecipient, transaction: SDSAnyReadTransaction) -> Bool { false }

    func memberViewDismiss() {
        dismiss(animated: true)
    }
}
