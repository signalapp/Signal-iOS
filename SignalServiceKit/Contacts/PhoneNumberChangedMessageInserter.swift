//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

final class PhoneNumberChangedMessageInserter: RecipientMergeObserver {
    private let groupMemberStore: GroupMemberStore
    private let interactionStore: InteractionStore
    private let threadAssociatedDataStore: ThreadAssociatedDataStore
    private let threadStore: ThreadStore

    init(
        groupMemberStore: GroupMemberStore,
        interactionStore: InteractionStore,
        threadAssociatedDataStore: ThreadAssociatedDataStore,
        threadStore: ThreadStore
    ) {
        self.groupMemberStore = groupMemberStore
        self.interactionStore = interactionStore
        self.threadAssociatedDataStore = threadAssociatedDataStore
        self.threadStore = threadStore
    }

    func willBreakAssociation(for recipient: SignalRecipient, mightReplaceNonnilPhoneNumber: Bool, tx: DBWriteTransaction) {}

    func didLearnAssociation(mergedRecipient: MergedRecipient, tx: DBWriteTransaction) {
        guard !mergedRecipient.isLocalRecipient else {
            // Don't insert change number messages when we change our own number.
            return
        }
        guard
            let aci = mergedRecipient.newRecipient.aci,
            let oldPhoneNumber = mergedRecipient.oldRecipient?.phoneNumber?.stringValue,
            let newPhoneNumber = E164(mergedRecipient.newRecipient.phoneNumber?.stringValue),
            oldPhoneNumber != newPhoneNumber.stringValue
        else {
            // Don't insert change number messages unless we've *changed* from an old
            // number to a new number.
            return
        }

        func insertChangeMessage(thread: TSThread) {
            guard thread.shouldThreadBeVisible else {
                // Skip if thread is soft deleted or otherwise not user visible.
                return
            }
            let threadAssociatedData = threadAssociatedDataStore.fetchOrDefault(for: thread, tx: tx)
            guard !threadAssociatedData.isArchived else {
                // Skip if thread is archived.
                return
            }
            let infoMessage: TSInfoMessage = .makeForPhoneNumberChange(
                thread: thread,
                aci: aci,
                oldNumber: oldPhoneNumber,
                newNumber: newPhoneNumber
            )
            interactionStore.insertInteraction(infoMessage, tx: tx)
        }

        // Only insert "change phone number" interactions for full members.
        for threadId in groupMemberStore.groupThreadIds(withFullMember: aci, tx: tx) {
            guard let thread = threadStore.fetchGroupThread(uniqueId: threadId, tx: tx) else {
                continue
            }
            insertChangeMessage(thread: thread)
        }

        // Only insert "change phone number" interaction in 1:1 thread if it already exists.
        if let thread = threadStore.fetchContactThread(recipient: mergedRecipient.newRecipient, tx: tx) {
            insertChangeMessage(thread: thread)
        }
    }
}
