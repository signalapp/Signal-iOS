//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol StoryBadgeCountObserver: AnyObject {

    var isStoriesTabActive: Bool { get }

    func didUpdateStoryBadge(_ badge: String?)
}

public class StoryBadgeCountManager: NSObject, Dependencies {

    private weak var observer: StoryBadgeCountObserver?

    /// Should only be called once per object lifetime.
    public func beginObserving(observer: StoryBadgeCountObserver) {
        self.observer = observer

        Self.databaseStorage.appendDatabaseChangeDelegate(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(computeBadgeCount),
            name: .storiesEnabledStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(computeBadgeCount),
            name: .onboardingStoryStateDidChange,
            object: nil
        )

        // Trigger an update immediately
        computeBadgeCount()
    }

    public func markAllStoriesRead() {
        databaseStorage.write { transaction in
            // No-ops if the story was already read.
            Self.systemStoryManager.setHasReadOnboardingStory(transaction: transaction, updateStorageService: true)

            var latestStoryPerContext = [StoryContext: StoryMessage]()

            StoryFinder.enumerateUnreadIncomingStories(transaction: transaction, block: { storyMessage, _ in
                let latestKnownTimestamp = latestStoryPerContext[storyMessage.context]?.timestamp ?? Date.distantPast.ows_millisecondsSince1970
                if storyMessage.timestamp > latestKnownTimestamp {
                    latestStoryPerContext[storyMessage.context] = storyMessage
                }
            })
            for storyMessage in latestStoryPerContext.values {
                storyMessage.markAsRead(
                    at: Date.ows_millisecondTimestamp(),
                    circumstance: .onThisDevice,
                    transaction: transaction
                )
            }
        }
    }

    @objc
    private func computeBadgeCount() {
        guard observer != nil else { return }

        guard RemoteConfig.stories else { return }

        let (count, isFailed) = databaseStorage.read { transaction -> (Int, Bool) in
            if StoryFinder.hasFailedStories(transaction: transaction) {
                return (0, true)
            }
            guard self.observer?.isStoriesTabActive.negated ?? false else {
                // Don't bother querying if the stories tab is active.
                // Set the badge to nil, as everything should be instantly marked read, but
                // until the update goes through the db queue, we may get a count which would
                // cause the badge to flicker.
                return (0, false)
            }
            let unviewedStoriesCount = StoryFinder.unviewedSenderCount(transaction: transaction)
            return (unviewedStoriesCount, false)
        }
        DispatchQueue.main.async {
            guard let observer = self.observer else {
                return
            }
            if observer.isStoriesTabActive {
                // Mark everything read as soon as it comes in.
                self.markAllStoriesRead()
            }
            guard !isFailed else {
                // If we have failed stories, always update.
                observer.didUpdateStoryBadge("!")
                return
            }
            observer.didUpdateStoryBadge(count == 0 ? nil : "\(count)")
        }
    }
}

extension StoryBadgeCountManager: DatabaseChangeDelegate {
    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        if databaseChanges.didUpdateModel(collection: StoryContextAssociatedData.collection()) ||
            databaseChanges.didUpdateModel(collection: StoryMessage.collection()) {
            computeBadgeCount()
        }
    }

    public func databaseChangesDidUpdateExternally() {
        computeBadgeCount()
    }

    public func databaseChangesDidReset() {
        computeBadgeCount()
    }
}
