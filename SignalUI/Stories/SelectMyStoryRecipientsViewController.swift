//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

public class SelectMyStoryRecipientsViewController: BaseMemberViewController {
    let thread: TSPrivateStoryThread
    let mode: TSThreadStoryViewMode
    var recipientSet: OrderedSet<PickedRecipient>
    let originalRecipientSet: Set<PickedRecipient>

    override public var hasUnsavedChanges: Bool { originalRecipientSet != recipientSet.unorderedMembers }

    let completionBlock: () -> Void

    public static func load(
        for thread: TSPrivateStoryThread,
        mode: TSThreadStoryViewMode,
        tx: DBReadTransaction,
        completionBlock: @escaping () -> Void,
    ) -> SelectMyStoryRecipientsViewController {
        let storyRecipientManager = DependenciesBridge.shared.storyRecipientManager
        return SelectMyStoryRecipientsViewController(
            thread: thread,
            recipientAddresses: failIfThrows {
                try storyRecipientManager.fetchRecipients(forStoryThread: thread, tx: tx)
            }.map { $0.address },
            mode: mode,
            completionBlock: completionBlock,
        )
    }

    private init(
        thread: TSPrivateStoryThread,
        recipientAddresses: [SignalServiceAddress],
        mode: TSThreadStoryViewMode,
        completionBlock: @escaping () -> Void,
    ) {
        self.thread = thread
        self.mode = mode
        if thread.storyViewMode == mode {
            self.recipientSet = OrderedSet(recipientAddresses.map { .for(address: $0) })
        } else {
            self.recipientSet = OrderedSet()
        }
        self.originalRecipientSet = self.recipientSet.unorderedMembers
        self.completionBlock = completionBlock
        super.init()

        memberViewDelegate = self
    }

    // MARK: - View Lifecycle

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateBarButtons()
    }

    private func updateBarButtons() {
        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            self?.dismissPressed()
        }

        navigationItem.rightBarButtonItem = .systemItem(.save) { [weak self] in
            self?.savePressed()
        }
        navigationItem.rightBarButtonItem?.isEnabled = hasUnsavedChanges

        switch mode {
        case .explicit:
            if recipientSet.isEmpty {
                title = OWSLocalizedString(
                    "STORY_SELECT_ALLOWED_CONNECTIONS_VIEW_TITLE",
                    comment: "The title for the 'select connections for story' view.",
                )
            } else {
                let format = OWSLocalizedString(
                    "STORY_SELECT_ALLOWED_CONNECTIONS_VIEW_TITLE_%d",
                    tableName: "PluralAware",
                    comment: "The title for the 'select connections for story' view if already some connections are selected. Embeds {{number}} of connections.",
                )
                title = String.localizedStringWithFormat(format, recipientSet.count)
            }
        case .blockList:
            if recipientSet.isEmpty {
                title = OWSLocalizedString(
                    "STORY_SELECT_EXCLUDED_CONNECTIONS_VIEW_TITLE",
                    comment: "The title for the 'select excluded connections for story' view.",
                )
            } else {
                let format = OWSLocalizedString(
                    "STORY_SELECT_EXCLUDED_CONNECTIONS_VIEW_TITLE_%d",
                    tableName: "PluralAware",
                    comment: "The title for the 'select excluded connections for story' view if already some connections are selected. Embeds {{number}} of excluded connections.",
                )
                title = String.localizedStringWithFormat(format, recipientSet.count)
            }
        case .default, .disabled:
            owsFailDebug("Unexpected mode")
        }
    }

    // MARK: - Actions

    private func savePressed() {
        AssertIsOnMainThread()

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            let recipientIds = self.recipientSet.orderedMembers.lazy.compactMap { $0.address?.serviceId }.map {
                return recipientFetcher.fetchOrCreate(serviceId: $0, tx: transaction).id
            }
            self.thread.updateWithStoryViewMode(
                self.mode,
                storyRecipientIds: .setTo(Array(recipientIds)),
                updateStorageService: true,
                transaction: transaction,
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

    public func memberViewAddRecipient(_ recipient: PickedRecipient) -> Bool {
        recipientSet.append(recipient)
        updateBarButtons()
        return true
    }

    public func memberViewShouldShowMemberCount() -> Bool { false }

    public func memberViewShouldAllowBlockedSelection() -> Bool { mode == .blockList }

    public func memberViewMemberCountForDisplay() -> Int { recipientSet.count }

    public func memberViewIsPreExistingMember(_ recipient: PickedRecipient, transaction: DBReadTransaction) -> Bool { false }

    public func memberViewCustomIconNameForPickedMember(_ recipient: PickedRecipient) -> String? {
        mode == .blockList ? "x-circle-fill" : nil
    }

    public func memberViewCustomIconColorForPickedMember(_ recipient: PickedRecipient) -> UIColor? {
        mode == .blockList ? .ows_accentRed : nil
    }

    public func memberViewDismiss() {
        dismiss(animated: true)
    }
}
