//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public final class MessageBackupStoryStore {

    private let storyStore: StoryStore

    init(storyStore: StoryStore) {
        self.storyStore = storyStore
    }

    // MARK: - Archiving

    func getOrCreateStoryContextAssociatedData(
        for aci: Aci,
        context: MessageBackup.RecipientArchivingContext
    ) throws -> StoryContextAssociatedData {
        return storyStore.getOrCreateStoryContextAssociatedData(for: aci, tx: context.tx)
    }

    func getOrCreateStoryContextAssociatedData(
        for groupThread: TSGroupThread,
        context: MessageBackup.RecipientArchivingContext
    ) throws -> StoryContextAssociatedData {
        return storyStore.getOrCreateStoryContextAssociatedData(forGroupThread: groupThread, tx: context.tx)
    }

    // MARK: - Restoring

    func createMyStory(
        name: String,
        allowReplies: Bool,
        viewMode: TSThreadStoryViewMode,
        addresses: [MessageBackup.ContactAddress],
        context: MessageBackup.RecipientRestoringContext
    ) throws {
        // TODO: [BackupsPerf] create and insert this one go, instead of get or create then update.
        let myStory = storyStore.getOrCreateMyStory(tx: context.tx)
        storyStore.update(
            storyThread: myStory,
            name: name,
            allowReplies: allowReplies,
            viewMode: viewMode,
            addresses: addresses.map { $0.asInteropAddress() },
            updateStorageService: false,
            updateHasSetMyStoryPrivacyIfNeeded: false,
            tx: context.tx
        )
    }

    func insert(
        _ storyThread: TSPrivateStoryThread,
        context: MessageBackup.RecipientRestoringContext
    ) throws {
        // TODO: [BackupsPerf] insert this directly; ensure all side effects of
        // sdsSave (which storystore calls) are accounted for.
        storyStore.insert(storyThread: storyThread, tx: context.tx)
    }

    func createStoryContextAssociatedData(
        for aci: Aci,
        isHidden: Bool,
        context: MessageBackup.RecipientRestoringContext
    ) throws {
        // TODO: [BackupsPerf] create and insert this one go, instead of get or create then update.
        let storyContext = storyStore.getOrCreateStoryContextAssociatedData(for: aci, tx: context.tx)
        storyStore.updateStoryContext(
            storyContext,
            updateStorageService: false,
            isHidden: isHidden,
            tx: context.tx
        )
    }

    func createStoryContextAssociatedData(
        for groupThread: TSGroupThread,
        isHidden: Bool,
        context: MessageBackup.RecipientRestoringContext
    ) throws {
        // TODO: [BackupsPerf] create and insert this one go, instead of get or create then update.
        let storyContext = storyStore.getOrCreateStoryContextAssociatedData(forGroupThread: groupThread, tx: context.tx)
        storyStore.updateStoryContext(
            storyContext,
            updateStorageService: false,
            isHidden: isHidden,
            tx: context.tx
        )
    }
}
