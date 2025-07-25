//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension NSNotification.Name {
    public static let onboardingStoryStateDidChange = NSNotification.Name("onboardingStoryStateDidChange")
}

public enum OnboardingStoryViewSource {
    case local(timestamp: UInt64, shouldUpdateStorageService: Bool)
    case otherDevice
}

public protocol SystemStoryManagerProtocol {

    /// Downloads the onboarding story if it has not been downloaded before.
    /// Called on its own when the main app starts up.
    func enqueueOnboardingStoryDownload() -> Task<Void, any Error>

    /// If the onboarding story is downloaded, has been viewed, and meets the conditions
    /// to be expired, deletes it and cleans up references.
    /// Called on its own when the app is backgrounded.
    func cleanUpOnboardingStoryIfNeeded() -> Task<Void, any Error>

    /// "Read" means the user went to the stories tab with the onboarding story available.
    /// If its viewed, its also read.
    /// Reading doesn't cause the story to get cleaned up and deleted.
    func isOnboardingStoryRead(transaction: DBReadTransaction) -> Bool

    /// "Viewed" means the user actually opened the onboarding story.
    func isOnboardingStoryViewed(transaction: DBReadTransaction) -> Bool

    /// "Read" means the user went to the stories tab with the onboarding story available.
    /// Reading doesn't cause the story to get cleaned up and deleted.
    func setHasReadOnboardingStory(transaction: DBWriteTransaction, updateStorageService: Bool)

    /// "Viewed" means the user actually opened the onboarding story.
    func setHasViewedOnboardingStory(source: OnboardingStoryViewSource, transaction: DBWriteTransaction) throws

    func isOnboardingOverlayViewed(transaction: DBReadTransaction) -> Bool
    func setOnboardingOverlayViewed(value: Bool, transaction: DBWriteTransaction)

    /// Whether the "group story education sheet" has been viewed.
    /// - Note
    /// This feature has not been implemented on iOS, but we can learn about
    /// this property via Storage Service or a Backup and so persist it.
    func isGroupStoryEducationSheetViewed(tx: DBReadTransaction) -> Bool

    /// Mark the "group story education sheet" as having been viewed.
    /// - Note
    /// This feature has not been implemented on iOS, but we can learn about
    /// this property via Storage Service or a Backup and so persist it.
    func setGroupStoryEducationSheetViewed(tx: DBWriteTransaction)

    // MARK: Hidden State

    func addStateChangedObserver(_ observer: SystemStoryStateChangeObserver)

    func removeStateChangedObserver(_ observer: SystemStoryStateChangeObserver)

    func areSystemStoriesHidden(transaction: DBReadTransaction) -> Bool

    /// Sets system stories hidden state. If hiding, marks the onboarding story as viewed.
    func setSystemStoriesHidden(_ hidden: Bool, transaction: DBWriteTransaction)
}

public protocol SystemStoryStateChangeObserver: NSObject {

    func systemStoryHiddenStateDidChange(rowIds: [Int64])
}
