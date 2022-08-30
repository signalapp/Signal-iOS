//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

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
}
