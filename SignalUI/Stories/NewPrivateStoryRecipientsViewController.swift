//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

public class NewPrivateStoryRecipientsViewController: BaseMemberViewController {
    var recipientSet: OrderedSet<PickedRecipient> = []

    public override var hasUnsavedChanges: Bool { !recipientSet.isEmpty }

    let selectItemsInParent: (([StoryConversationItem]) -> Void)?

    public init(selectItemsInParent: (([StoryConversationItem]) -> Void)? = nil) {
        self.selectItemsInParent = selectItemsInParent
        super.init()

        memberViewDelegate = self
    }

    // MARK: - View Lifecycle

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateBarButtons()
    }

    private func updateBarButtons() {
        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            self?.dismissPressed()
        }

        navigationItem.rightBarButtonItem = .button(
            title: CommonStrings.nextButton,
            style: .plain,
            action: { [weak self] in
                self?.nextPressed()
            }
        )
        navigationItem.rightBarButtonItem?.isEnabled = hasUnsavedChanges

        if recipientSet.isEmpty {
            title = OWSLocalizedString(
                "NEW_PRIVATE_STORY_VIEW_TITLE",
                comment: "The title for the 'new private story' view.")

        } else {
            let format = OWSLocalizedString(
                "NEW_PRIVATE_STORY_VIEW_TITLE_%d",
                tableName: "PluralAware",
                comment: "The title for the 'new private story' view if already some connections are selected. Embeds {{number}} of connections.")
            title = String.localizedStringWithFormat(format, recipientSet.count)
        }
    }

    // MARK: - Actions

    private func nextPressed() {
        AssertIsOnMainThread()

        let vc = NewPrivateStoryConfirmViewController(
            recipientSet: recipientSet,
            selectItemsInParent: selectItemsInParent
        )
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: -

extension NewPrivateStoryRecipientsViewController: MemberViewDelegate {
    public var memberViewRecipientSet: OrderedSet<PickedRecipient> { recipientSet }

    public var memberViewHasUnsavedChanges: Bool { hasUnsavedChanges }

    public func memberViewRemoveRecipient(_ recipient: PickedRecipient) {
        recipientSet.remove(recipient)
        updateBarButtons()
    }

    public func memberViewAddRecipient(_ recipient: PickedRecipient) {
        recipientSet.append(recipient)
        updateBarButtons()
    }

    public func memberViewCanAddRecipient(_ recipient: PickedRecipient) -> Bool { true }

    public func memberViewPrepareToSelectRecipient(_ recipient: PickedRecipient) -> Promise<Void> { Promise.value(()) }

    public func memberViewShouldShowMemberCount() -> Bool { false }

    public func memberViewShouldAllowBlockedSelection() -> Bool { false }

    public func memberViewMemberCountForDisplay() -> Int { recipientSet.count }

    public func memberViewIsPreExistingMember(_ recipient: PickedRecipient, transaction: SDSAnyReadTransaction) -> Bool { false }

    public func memberViewCustomIconNameForPickedMember(_ recipient: PickedRecipient) -> String? { nil }

    public func memberViewCustomIconColorForPickedMember(_ recipient: PickedRecipient) -> UIColor? { nil }

    public func memberViewDismiss() {
        dismiss(animated: true)
    }
}
