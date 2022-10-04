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

    public override var hasUnsavedChanges: Bool { originalRecipientSet != recipientSet }

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
        case .default, .disabled:
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
                updateStorageService: true,
                transaction: transaction
            )
        }

        completionBlock()

        dismiss(animated: true)
    }
}

// MARK: -

extension SelectMyStoryRecipientsViewController: MemberViewDelegate {
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

    public func memberViewWillRenderRecipient(_ recipient: PickedRecipient) {}

    public func memberViewPrepareToSelectRecipient(_ recipient: PickedRecipient) -> AnyPromise { AnyPromise(Promise.value(())) }

    public func memberViewShowInvalidRecipientAlert(_ recipient: PickedRecipient) {}

    public func memberViewNoUuidSubtitleForRecipient(_ recipient: PickedRecipient) -> String? { nil }

    public func memberViewShouldShowMemberCount() -> Bool { false }

    public func memberViewShouldAllowBlockedSelection() -> Bool { mode == .blockList }

    public func memberViewMemberCountForDisplay() -> Int { recipientSet.count }

    public func memberViewIsPreExistingMember(_ recipient: PickedRecipient, transaction: SDSAnyReadTransaction) -> Bool { false }

    public func memberViewCustomIconNameForPickedMember(_ recipient: PickedRecipient) -> String? {
        mode == .blockList ? "x-circle-solid-24" : nil
    }

    public func memberViewCustomIconColorForPickedMember(_ recipient: PickedRecipient) -> UIColor? {
        mode == .blockList ? .ows_accentRed : nil
    }

    public func memberViewDismiss() {
        dismiss(animated: true)
    }
}
