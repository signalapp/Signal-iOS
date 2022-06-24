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

        if recipientSet.isEmpty {
            title = NSLocalizedString(
                "NEW_GROUP_SELECT_MEMBERS_VIEW_TITLE",
                comment: "The title for the 'select members for new group' view.")

        } else {
            let format = NSLocalizedString(
                "NEW_GROUP_MEMBERS_VIEW_TITLE_%d",
                tableName: "PluralAware",
                comment: "The title for the 'select members for new group' view if already some members are selected. Embeds {{number}} of members.")
            title = String.localizedStringWithFormat(format, recipientSet.count)
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

    func memberViewMemberCountForDisplay() -> Int { recipientSet.count }

    func memberViewIsPreExistingMember(_ recipient: PickedRecipient, transaction: SDSAnyReadTransaction) -> Bool { false }

    func memberViewDismiss() {
        dismiss(animated: true)
    }
}
