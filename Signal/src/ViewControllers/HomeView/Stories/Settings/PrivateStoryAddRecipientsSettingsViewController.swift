//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit
public import SignalUI

public class PrivateStoryAddRecipientsSettingsViewController: BaseMemberViewController {
    let thread: TSPrivateStoryThread
    var recipientSet: OrderedSet<PickedRecipient> = []

    override public var hasUnsavedChanges: Bool { !recipientSet.orderedMembers.isEmpty }

    public init(thread: TSPrivateStoryThread) {
        self.thread = thread
        super.init()

        memberViewDelegate = self
    }

    // MARK: - View Lifecycle

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateBarButtons()
    }

    private func updateBarButtons() {
        navigationItem.rightBarButtonItem = .systemItem(.save) { [weak self] in
            self?.updatePressed()
        }
        navigationItem.rightBarButtonItem?.isEnabled = hasUnsavedChanges

        title = OWSLocalizedString(
            "PRIVATE_STORY_SETTINGS_ADD_VIEWER_BUTTON",
            comment: "Button to add a new viewer on the 'private story settings' view",
        )
    }

    // MARK: - Actions

    private func updatePressed() {
        AssertIsOnMainThread()

        let uniqueId = self.thread.uniqueId
        let newValues = self.recipientSet.orderedMembers.compactMap { $0.address?.serviceId }
        ModalActivityIndicatorViewController.presentAsInvisible(fromViewController: self) { modal in
            SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
                guard
                    let storyThread = TSPrivateStoryThread.anyFetchPrivateStoryThread(uniqueId: uniqueId, transaction: tx),
                    storyThread.storyViewMode == .explicit
                else {
                    // Conflict during the update; stop.
                    return
                }
                let recipientFetcher = DependenciesBridge.shared.recipientFetcher
                let recipientIds = newValues.map { recipientFetcher.fetchOrCreate(serviceId: $0, tx: tx).id }
                let storyRecipientManager = DependenciesBridge.shared.storyRecipientManager
                failIfThrows {
                    try storyRecipientManager.insertRecipientIds(recipientIds, for: storyThread, shouldUpdateStorageService: true, tx: tx)
                }
            } completion: {
                self.navigationController?.popViewController(animated: true) { modal.dismiss(animated: false) }
            }
        }
    }
}

// MARK: -

extension PrivateStoryAddRecipientsSettingsViewController: MemberViewDelegate {
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

    public func memberViewShouldAllowBlockedSelection() -> Bool { false }

    public func memberViewMemberCountForDisplay() -> Int { recipientSet.count }

    public func memberViewIsPreExistingMember(_ recipient: PickedRecipient, transaction: DBReadTransaction) -> Bool {
        guard let address = recipient.address else {
            return false
        }
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        guard let recipient = recipientDatabaseTable.fetchRecipient(address: address, tx: transaction) else {
            return false
        }
        let storyRecipientStore = DependenciesBridge.shared.storyRecipientStore
        do {
            return try storyRecipientStore.doesStoryThreadId(thread.sqliteRowId!, containRecipientId: recipient.id, tx: transaction)
        } catch {
            Logger.warn("Couldn't check if member is already in story thread: \(error)")
            return false
        }
    }

    public func memberViewCustomIconNameForPickedMember(_ recipient: PickedRecipient) -> String? { nil }

    public func memberViewCustomIconColorForPickedMember(_ recipient: PickedRecipient) -> UIColor? { nil }

    public func memberViewDismiss() {
        navigationController?.popViewController(animated: true)
    }
}
