//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SystemStoryManagerMock: NSObject, SystemStoryManagerProtocol {

    /// In tests, set some other handler to this to return different results when the system under test calls enqueueOnboardingStoryDownload
    public lazy var downloadOnboardingStoryHandler: () -> Promise<Void> = { [weak self] in
        return .value(())
    }

    public func enqueueOnboardingStoryDownload() -> Promise<Void> {
        return downloadOnboardingStoryHandler()
    }

    /// In tests, set some other handler to this to return different results when the system under test calls cleanUpOnboardingStoryIfNeeded
    public lazy var cleanUpOnboardingStoryHandler: () -> Promise<Void> = { [weak self] in
        return .value(())
    }

    public func cleanUpOnboardingStoryIfNeeded() -> Promise<Void> {
        return cleanUpOnboardingStoryHandler()
    }

    public var isOnboardingStoryViewed: Bool = false

    public func isOnboardingStoryViewed(transaction: SDSAnyReadTransaction) -> Bool {
        return isOnboardingStoryViewed
    }

    public func setHasViewedOnboardingStoryOnAnotherDevice(transaction: SDSAnyWriteTransaction) {
        return
    }

    public func addStateChangedObserver(_ observer: SystemStoryStateChangeObserver) {
        fatalError("Unimplemented for tests")
    }

    public func removeStateChangedObserver(_ observer: SystemStoryStateChangeObserver) {
        fatalError("Unimplemented for tests")
    }

    public func areSystemStoriesHidden(transaction: SDSAnyReadTransaction) -> Bool {
        fatalError("Unimplemented for tests")
    }

    public func setSystemStoriesHidden(_ hidden: Bool, transaction: SDSAnyWriteTransaction) {
        fatalError("Unimplemented for tests")
    }
}

public class OnboardingStoryManagerFilesystemMock: OnboardingStoryManagerFilesystem {

    public override class func fileOrFolderExists(url: URL) -> Bool {
        return true
    }

    public override class func fileSize(of: URL) -> NSNumber? {
        return NSNumber(value: 100)
    }

    public override class func deleteFile(url: URL) throws {
        return
    }

    public override class func moveFile(from fromUrl: URL, to toUrl: URL) throws {
        return
    }

    public override class func isValidImage(at url: URL, mimeType: String?) -> Bool {
        return true
    }
}
