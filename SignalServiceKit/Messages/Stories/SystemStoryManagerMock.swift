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

    public override class func fileOrFolderExists(url: URL) -> Bool {
        return true
    }

    public override class func fileSize(of: URL) throws -> UInt64 {
        return 100
    }

    public override class func deleteFile(url: URL) throws {
        return
    }

    public override class func moveFile(from fromUrl: URL, to toUrl: URL) throws {
        return
    }

    public override class func isValidImage(at url: URL) -> Bool {
        return true
    }
}

public class OnboardingStoryManagerStoryMessageFactoryMock: OnboardingStoryManagerStoryMessageFactory {

    public override class func createFromSystemAuthor(
        attachmentSource: AttachmentDataSource,
        timestamp: UInt64,
        transaction: DBWriteTransaction
    ) throws -> StoryMessage {
        return try StoryMessage.createAndInsert(
            timestamp: timestamp,
            authorAci: StoryMessage.systemStoryAuthor,
            groupId: nil,
            manifest: StoryManifest.incoming(
                receivedState: StoryReceivedState(
                    allowsReplies: false,
                    receivedTimestamp: timestamp,
                    readTimestamp: nil,
                    viewedTimestamp: nil
                )
            ),
            replyCount: 0,
            attachmentBuilder: .withoutFinalizer(.media),
            mediaCaption: nil,
            shouldLoop: false,
            transaction: transaction
        )
    }

    public override class func validateAttachmentContents(
        dataSource: DataSourcePath,
        mimeType: String
    ) async throws -> AttachmentDataSource {
        struct FakePendingAttachment: PendingAttachment {
            let blurHash: String? = nil
            let sha256ContentHash: Data = Data()
            let encryptedByteCount: UInt32 = 100
            let unencryptedByteCount: UInt32 = 100
            let mimeType: String
            let encryptionKey: Data = Data()
            let digestSHA256Ciphertext: Data = Data()
            let localRelativeFilePath: String = ""
            var renderingFlag: AttachmentReference.RenderingFlag = .default
            let sourceFilename: String?
            let validatedContentType: Attachment.ContentType = .file
            let orphanRecordId: OrphanedAttachmentRecord.IDType = 1

            mutating func removeBorderlessRenderingFlagIfPresent() {
                switch renderingFlag {
                case .borderless:
                    renderingFlag = .default
                default:
                    return
                }
            }
        }

        return AttachmentDataSource.pendingAttachment(FakePendingAttachment(
            mimeType: mimeType,
            sourceFilename: dataSource.sourceFilename
        ))
    }
}
