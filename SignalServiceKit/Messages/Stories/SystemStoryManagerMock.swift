//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SystemStoryManagerMock: SystemStoryManagerProtocol {

    /// In tests, set some other handler to this to return different results when the system under test calls enqueueOnboardingStoryDownload
    public lazy var downloadOnboardingStoryHandler: () -> Task<Void, any Error> = {
        return Task {}
    }

    public func enqueueOnboardingStoryDownload() -> Task<Void, any Error> {
        return downloadOnboardingStoryHandler()
    }

    /// In tests, set some other handler to this to return different results when the system under test calls cleanUpOnboardingStoryIfNeeded
    public lazy var cleanUpOnboardingStoryHandler: () -> Task<Void, any Error> = {
        return Task {}
    }

    public func cleanUpOnboardingStoryIfNeeded() -> Task<Void, any Error> {
        return cleanUpOnboardingStoryHandler()
    }

    public var isOnboardingStoryRead: Bool = false

    public func isOnboardingStoryRead(transaction: DBReadTransaction) -> Bool {
        return isOnboardingStoryRead
    }

    public var isOnboardingStoryViewed: Bool = false

    public func isOnboardingStoryViewed(transaction: DBReadTransaction) -> Bool {
        return isOnboardingStoryViewed
    }

    public func setHasReadOnboardingStory(transaction: DBWriteTransaction, updateStorageService: Bool) {
        return
    }

    public func setHasViewedOnboardingStory(source: OnboardingStoryViewSource, transaction: DBWriteTransaction) {
        return
    }

    public var isOnboardingOverlayViewed: Bool = false
    public func isOnboardingOverlayViewed(transaction: DBReadTransaction) -> Bool {
        return isOnboardingOverlayViewed
    }

    public func setOnboardingOverlayViewed(value: Bool, transaction: DBWriteTransaction) {
        return
    }

    public var isGroupStoryEducationSheetViewed: Bool = false
    public func isGroupStoryEducationSheetViewed(tx: DBReadTransaction) -> Bool {
        return isGroupStoryEducationSheetViewed
    }

    public func setGroupStoryEducationSheetViewed(tx: DBWriteTransaction) {
        isGroupStoryEducationSheetViewed = true
    }

    public func addStateChangedObserver(_ observer: SystemStoryStateChangeObserver) {
        fatalError("Unimplemented for tests")
    }

    public func removeStateChangedObserver(_ observer: SystemStoryStateChangeObserver) {
        fatalError("Unimplemented for tests")
    }

    public var areSystemStoriesHidden: Bool = false

    public func areSystemStoriesHidden(transaction: DBReadTransaction) -> Bool {
        return areSystemStoriesHidden
    }

    public func setSystemStoriesHidden(_ hidden: Bool, transaction: DBWriteTransaction) {
        fatalError("Unimplemented for tests")
    }
}

public class OnboardingStoryManagerFilesystemMock: OnboardingStoryManagerFilesystem {

    override public class func fileOrFolderExists(url: URL) -> Bool {
        return true
    }

    override public class func fileSize(of: URL) throws -> UInt64 {
        return 100
    }

    override public class func deleteFile(url: URL) throws {
        return
    }

    override public class func moveFile(from fromUrl: URL, to toUrl: URL) throws {
        return
    }

    override public class func isValidImage(at url: URL) -> Bool {
        return true
    }
}

public class OnboardingStoryManagerStoryMessageFactoryMock: OnboardingStoryManagerStoryMessageFactory {

    override public class func createFromSystemAuthor(
        attachmentSource: AttachmentDataSource,
        timestamp: UInt64,
        transaction: DBWriteTransaction,
    ) throws -> StoryMessage {
        let storyMessage = StoryMessage(
            timestamp: timestamp,
            authorAci: StoryMessage.systemStoryAuthor,
            groupId: nil,
            manifest: StoryManifest.incoming(
                receivedState: StoryReceivedState(
                    allowsReplies: false,
                    receivedTimestamp: timestamp,
                    readTimestamp: nil,
                    viewedTimestamp: nil,
                ),
            ),
            attachment: .media,
            replyCount: 0,
        )
        storyMessage.anyInsert(transaction: transaction)
        return storyMessage
    }

    override public class func validateAttachmentContents(
        dataSource: DataSourcePath,
        mimeType: String,
    ) async throws -> AttachmentDataSource {
        let pendingAttachment = PendingAttachment(
            blurHash: nil,
            sha256ContentHash: Data(),
            encryptedByteCount: 100,
            unencryptedByteCount: 100,
            mimeType: mimeType,
            encryptionKey: Data(),
            digestSHA256Ciphertext: Data(),
            localRelativeFilePath: "",
            renderingFlag: .default,
            sourceFilename: dataSource.sourceFilename,
            validatedContentType: .file,
            orphanRecordId: 1,
        )
        return AttachmentDataSource.pendingAttachment(pendingAttachment)
    }
}
