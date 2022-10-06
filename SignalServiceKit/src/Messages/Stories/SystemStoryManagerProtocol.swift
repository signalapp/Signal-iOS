//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

extension NSNotification.Name {
    public static let onboardingStoryStateDidChange = NSNotification.Name("onboardingStoryStateDidChange")
}

/// Expose to objc for dependency injection support (SSKEnvironment is objc-only) but put the
/// actual methods on a swift protocol that inherits from this one.
@objc
public protocol SystemStoryManagerProtocolObjc: AnyObject {}

public protocol SystemStoryManagerProtocol: SystemStoryManagerProtocolObjc {

    /// Downloads the onboarding story if it has not been downloaded before.
    /// Called on its own when the main app starts up.
    func enqueueOnboardingStoryDownload() -> Promise<Void>

    /// If the onboarding story is downloaded, has been viewed, and meets the conditions
    /// to be expired, deletes it and cleans up references.
    /// Called on its own when the app is backgrounded.
    func cleanUpOnboardingStoryIfNeeded() -> Promise<Void>

    func isOnboardingStoryViewed(transaction: SDSAnyReadTransaction) -> Bool

    func setHasViewedOnboardingStoryOnAnotherDevice(transaction: SDSAnyWriteTransaction)

    // MARK: Hidden State

    func addStateChangedObserver(_ observer: SystemStoryStateChangeObserver)

    func removeStateChangedObserver(_ observer: SystemStoryStateChangeObserver)

    func areSystemStoriesHidden(transaction: SDSAnyReadTransaction) -> Bool

    /// Sets system stories hidden state. If hiding, marks the onboarding story as viewed.
    func setSystemStoriesHidden(_ hidden: Bool, transaction: SDSAnyWriteTransaction)
}

public protocol SystemStoryStateChangeObserver: NSObject {

    func systemStoryHiddenStateDidChange(rowIds: [Int64])
}
