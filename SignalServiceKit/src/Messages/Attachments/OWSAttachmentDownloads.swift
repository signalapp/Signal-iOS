//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension OWSAttachmentDownloads {

    // MARK: - Dependencies

    private class var signalService: OWSSignalService {
        return .shared()
    }

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private class var profileManager: ProfileManagerProtocol {
        return SSKEnvironment.shared.profileManager
    }

    // MARK: - Enqueue

    func downloadPromise(attachmentPointer: TSAttachmentPointer,
                         category: AttachmentCategory,
                         bypassPendingMessageRequest: Bool) -> Promise<TSAttachmentStream> {
        return Promise { resolver in
            self.download(attachmentPointer: attachmentPointer,
                          category: category,
                          bypassPendingMessageRequest: bypassPendingMessageRequest,
                          success: resolver.fulfill,
                          failure: resolver.reject)
        }.map { attachments in
            assert(attachments.count == 1)
            guard let attachment = attachments.first else {
                throw OWSAssertionError("Missing attachment.")
            }
            return attachment
        }
    }

    @objc(downloadAttachmentPointer:category:bypassPendingMessageRequest:success:failure:)
    func download(attachmentPointer: TSAttachmentPointer,
                  category: AttachmentCategory,
                  bypassPendingMessageRequest: Bool,
                  success: @escaping ([TSAttachmentStream]) -> Void,
                  failure: @escaping (Error) -> Void) {
        download(attachmentPointer: attachmentPointer,
                 nullableMessage: nil,
                 category: category,
                 bypassPendingMessageRequest: bypassPendingMessageRequest,
                 success: success,
                 failure: failure)
    }

    @objc(downloadAttachmentPointer:message:category:bypassPendingMessageRequest:success:failure:)
    func download(attachmentPointer: TSAttachmentPointer,
                  message: TSMessage,
                  category: AttachmentCategory,
                  bypassPendingMessageRequest: Bool,
                  success: @escaping ([TSAttachmentStream]) -> Void,
                  failure: @escaping (Error) -> Void) {
        download(attachmentPointer: attachmentPointer,
                 nullableMessage: message,
                 category: category,
                 bypassPendingMessageRequest: bypassPendingMessageRequest,
                 success: success,
                 failure: failure)
    }

    private func download(attachmentPointer: TSAttachmentPointer,
                          nullableMessage message: TSMessage?,
                          category: AttachmentCategory,
                          bypassPendingMessageRequest: Bool,
                          success: @escaping ([TSAttachmentStream]) -> Void,
                          failure: @escaping (Error) -> Void) {

        guard !CurrentAppContext().isRunningTests else {
            Self.serialQueue.async {
                failure(OWSAttachmentDownloads.buildError())
            }
            return
        }

        let attachmentReference = AttachmentReference.attachmentPointer(attachmentPointer: attachmentPointer,
                                                                        category: category)
        enqueueJobs(forAttachmentReferences: [attachmentReference],
                    message: message,
                    bypassPendingMessageRequest: bypassPendingMessageRequest,
                    success: success,
                    failure: failure)
    }

    @objc
    func downloadAllAttachments(forThread thread: TSThread,
                                transaction: SDSAnyReadTransaction) {

        var promises = [Promise<Void>]()
        let unfairLock = UnfairLock()
        var attachmentStreams = [TSAttachmentStream]()

        do {
            let finder = GRDBInteractionFinder(threadUniqueId: thread.uniqueId)
            try finder.enumerateMessagesWithAttachments(transaction: transaction.unwrapGrdbRead) { (message, _) in
                let (promise, resolver) = Promise<Void>.pending()
                promises.append(promise)
                self.downloadAttachments(forMessageId: message.uniqueId,
                                         attachmentGroup: .allAttachmentsIncoming,
                                         bypassPendingMessageRequest: false,
                                         success: { downloadedAttachments in
                                            unfairLock.withLock {
                                                attachmentStreams.append(contentsOf: downloadedAttachments)
                                            }
                                            resolver.fulfill(())
                                         },
                                         failure: { error in
                                            resolver.reject(error)
                                         })
            }

            guard !promises.isEmpty else {
                return
            }

            // Block until _all_ promises have either succeeded or failed.
            _ = firstly(on: .global()) {
                when(fulfilled: promises)
            }.done(on: Self.serialQueue) { _ in
                let attachmentStreamsCopy = unfairLock.withLock { attachmentStreams }
                Logger.info("Successfully downloaded attachments for whitelisted thread: \(attachmentStreamsCopy.count).")
            }.catch(on: Self.serialQueue) { error in
                Logger.warn("Failed to download attachments for whitelisted thread.")
                owsFailDebugUnlessNetworkFailure(error)
            }
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

//    @objc(downloadAllAttachmentsForMessageId:bypassPendingMessageRequest:success:failure:)
//    func downloadAllAttachments(forMessageId messageId: String,
//                                bypassPendingMessageRequest: Bool,
//                                success: @escaping ([TSAttachmentStream]) -> Void,
//                                failure: @escaping (Error) -> Void) {
//        downloadAttachments(forMessageId: messageId,
//                            attachmentGroup: .allAttachments,
//                            bypassPendingMessageRequest: bypassPendingMessageRequest,
//                            success: success,
//                            failure: failure)
//    }
//
//    @objc(downloadBodyAttachmentsForMessageId:bypassPendingMessageRequest:success:failure:)
//    func downloadBodyAttachments(forMessageId messageId: String,
//                                 bypassPendingMessageRequest: Bool,
//                                 success: @escaping ([TSAttachmentStream]) -> Void,
//                                 failure: @escaping (Error) -> Void) {
//        downloadAttachments(forMessageId: messageId,
//                            attachmentGroup: .bodyAttachments,
//                            bypassPendingMessageRequest: bypassPendingMessageRequest,
//                            success: success,
//                            failure: failure)
//    }

    // TODO: Can we simplify this?
    @objc
    enum AttachmentGroup: UInt, Equatable {
        case allAttachmentsIncoming
        case bodyAttachmentsIncoming
        case allAttachmentsOfAnyKind
        case bodyAttachmentsOfAnyKind

        var justIncomingAttachments: Bool {
            switch self {
            case .bodyAttachmentsOfAnyKind, .allAttachmentsOfAnyKind:
                return false
            case .bodyAttachmentsIncoming, .allAttachmentsIncoming:
                return true
            }
        }

        var justBodyAttachments: Bool {
            switch self {
            case .allAttachmentsIncoming, .allAttachmentsOfAnyKind:
                return false
            case .bodyAttachmentsIncoming, .bodyAttachmentsOfAnyKind:
                return true
            }
        }
    }

    @objc
    enum AttachmentCategory: UInt, Equatable {
        case bodyMediaImage
        case bodyMediaVideo
        case bodyAudioVoiceMemo
        case bodyAudioOther
        case bodyFile
        case stickerSmall
        case stickerLarge
        case quotedReplyThumbnail
        case linkedPreviewThumbnail
        case contactShareAvatar
        case other
    }

    private enum AttachmentReference {
        case attachmentStream(attachmentStream: TSAttachmentStream, category: AttachmentCategory)
        case attachmentPointer(attachmentPointer: TSAttachmentPointer, category: AttachmentCategory)

        var category: AttachmentCategory {
            switch self {
            case .attachmentPointer(_, let category):
                return category
            case .attachmentStream(_, let category):
                return category
            }
        }
    }

    private class func loadAttachmentReferences(forMessage message: TSMessage,
                                                attachmentGroup: AttachmentGroup,
                                                transaction: SDSAnyReadTransaction) -> [AttachmentReference] {

        var references = [AttachmentReference]()
        var attachmentIds = Set<String>()

        func addReference(attachment: TSAttachment, category: AttachmentCategory) {

            if let attachmentPointer = attachment as? TSAttachmentPointer {
                if attachmentPointer.pointerType == .restoring {
                    Logger.warn("Ignoring restoring attachment.")
                    return
                }
                if attachmentGroup.justIncomingAttachments,
                   attachmentPointer.pointerType != .incoming {
                    Logger.warn("Ignoring non-incoming attachment.")
                    return
                }
            }

            let attachmentId = attachment.uniqueId
            guard !attachmentIds.contains(attachmentId) else {
                // Ignoring duplicate
                return
            }
            attachmentIds.insert(attachmentId)

            if let attachmentStream = attachment as? TSAttachmentStream {
                references.append(.attachmentStream(attachmentStream: attachmentStream, category: category))
            } else if let attachmentPointer = attachment as? TSAttachmentPointer {
                references.append(.attachmentPointer(attachmentPointer: attachmentPointer, category: category))
            } else {
                owsFailDebug("Invalid attachment: \(type(of: attachment))")
            }
        }

        func addReference(attachmentId: String, category: AttachmentCategory) {
            guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentId,
                                                         transaction: transaction) else {
                owsFailDebug("Missing attachment: \(attachmentId)")
                return
            }
            addReference(attachment: attachment, category: category)
        }

        for attachmentId in message.attachmentIds {
            guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentId,
                                                         transaction: transaction) else {
                owsFailDebug("Missing attachment: \(attachmentId)")
                continue
            }
            let category: AttachmentCategory = {
                if attachment.isImage {
                    return .bodyMediaImage
                } else if attachment.isVideo {
                    return .bodyMediaVideo
                } else if attachment.isVoiceMessage {
                    return .bodyAudioVoiceMemo
                } else if attachment.isAudio {
                    return .bodyAudioOther
                } else {
                    return .bodyFile
                }
            }()
            addReference(attachment: attachment, category: category)
        }

        guard !attachmentGroup.justBodyAttachments else {
            return references
        }

        if let quotedMessage = message.quotedMessage {
            for attachmentId in quotedMessage.thumbnailAttachmentStreamIds() {
                addReference(attachmentId: attachmentId, category: .quotedReplyThumbnail)
            }
            if let attachmentId = quotedMessage.thumbnailAttachmentPointerId() {
                addReference(attachmentId: attachmentId, category: .quotedReplyThumbnail)
            }
        }

        if let attachmentId = message.contactShare?.avatarAttachmentId {
            addReference(attachmentId: attachmentId, category: .contactShareAvatar)
        }

        if let attachmentId = message.linkPreview?.imageAttachmentId {
            addReference(attachmentId: attachmentId, category: .linkedPreviewThumbnail)
        }

        if let attachmentId = message.messageSticker?.attachmentId {
            if let attachment = TSAttachment.anyFetch(uniqueId: attachmentId,
                                                      transaction: transaction) {
                owsAssertDebug(attachment.byteCount > 0)
                let autoDownloadSizeThreshold: UInt32 = 100 * 1024
                if attachment.byteCount > autoDownloadSizeThreshold {
                    addReference(attachmentId: attachmentId, category: .stickerLarge)
                } else {
                    addReference(attachmentId: attachmentId, category: .stickerSmall)
                }
            } else {
                owsFailDebug("Missing attachment: \(attachmentId)")
            }
        }

        return references
    }

    // TODO: This replaces downloadAttachmentsForMessage().
    @objc
    func downloadAttachments(forMessageId messageId: String,
                             attachmentGroup: AttachmentGroup,
                             bypassPendingMessageRequest: Bool,
                             success: @escaping ([TSAttachmentStream]) -> Void,
                             failure: @escaping (Error) -> Void) {

        Self.serialQueue.async {
            guard !CurrentAppContext().isRunningTests else {
                failure(Self.buildError())
                return
            }
            Self.databaseStorage.read { transaction in
                guard let message = TSMessage.anyFetchMessage(uniqueId: messageId, transaction: transaction) else {
                    failure(Self.buildError())
                    return
                }
                let attachmentReferences = Self.loadAttachmentReferences(forMessage: message,
                                                                         attachmentGroup: attachmentGroup,
                                                                         transaction: transaction)
                guard !attachmentReferences.isEmpty else {
                    success([])
                    return
                }
                Self.serialQueue.async {
                    self.enqueueJobs(forAttachmentReferences: attachmentReferences,
                                     message: message,
                                     bypassPendingMessageRequest: bypassPendingMessageRequest,
                                     success: { attachmentStreams in
                                        success(attachmentStreams)

                                        Self.updateQuotedMessageThumbnail(messageId: messageId,
                                                                          attachmentReferences: attachmentReferences,
                                                                          attachmentStreams: attachmentStreams)
                                     },
                                     failure: failure)
                }
            }
        }
    }

    private class func updateQuotedMessageThumbnail(messageId: String,
                                                    attachmentReferences: [AttachmentReference],
                                                    attachmentStreams: [TSAttachmentStream]) {
        guard !attachmentStreams.isEmpty else {
            // Don't bothe
            return
        }
        let quotedMessageThumbnailDownloads = attachmentReferences.filter { $0.category == .quotedReplyThumbnail }
        guard !quotedMessageThumbnailDownloads.isEmpty else {
            return
        }
        Self.databaseStorage.write { transaction in
            guard let message = TSMessage.anyFetchMessage(uniqueId: messageId, transaction: transaction) else {
                Logger.warn("Missing message.")
                return
            }
            guard let thumbnailAttachmentPointerId = message.quotedMessage?.thumbnailAttachmentPointerId(),
                  !thumbnailAttachmentPointerId.isEmpty else {
                return
            }
            guard let quotedMessageThumbnail = (attachmentStreams.filter { $0.uniqueId == thumbnailAttachmentPointerId }.first) else {
                return
            }
            message.setQuotedMessageThumbnailAttachmentStream(quotedMessageThumbnail)
        }
    }

    private func enqueueJobs(forAttachmentReferences attachmentReferences: [AttachmentReference],
                             message: TSMessage?,
                             bypassPendingMessageRequest: Bool,
                             success: @escaping ([TSAttachmentStream]) -> Void,
                             failure: @escaping (Error) -> Void) {

        Self.serialQueue.async {

            let hasPendingMessageRequest: Bool = {
                guard !bypassPendingMessageRequest,
                      let message = message,
                      !message.isOutgoing else {
                    return false
                }
                return Self.databaseStorage.read { transaction in
                    let thread = message.thread(transaction: transaction)
                    // If the message that created this attachment was the first message in the
                    // thread, the thread may not yet be marked visible. In that case, just check
                    // if the thread is whitelisted. We know we just received a message.
                    if !thread.shouldThreadBeVisible {
                        return !Self.profileManager.isThread(inProfileWhitelist: thread,
                                                             transaction: transaction)
                    } else {
                        return GRDBThreadFinder.hasPendingMessageRequest(thread: thread,
                                                                         transaction: transaction.unwrapGrdbRead)
                    }
                }
            }()

            let unfairLock = UnfairLock()
            var promises = [Promise<Void>]()
            var attachmentStreams = [TSAttachmentStream]()
            for attachmentReference in attachmentReferences {
                switch attachmentReference {
                case .attachmentStream(let attachmentStream, _):
                    unfairLock.withLock {
                        attachmentStreams.append(attachmentStream)
                    }
                case .attachmentPointer(let attachmentPointer, let category):
                    if attachmentPointer.isVisualMedia,
                       hasPendingMessageRequest,
                       let message = message,
                       message.messageSticker == nil,
                       !message.isViewOnceMessage {
                        Logger.info("Not queueing visual media download for thread with pending message request")

                        Self.databaseStorage.asyncWrite { transaction in
                            attachmentPointer.updateAttachmentPointerState(from: .enqueued,
                                                                           to: .pendingMessageRequest,
                                                                           transaction: transaction)
                        }

                        continue
                    }

                    let (promise, resolver) = Promise<Void>.pending()
                    promises.append(promise)
                    self.enqueueJob(forAttachmentId: attachmentPointer.uniqueId,
                                    message: message,
                                    success: { attachmentStream in
                                        unfairLock.withLock {
                                            attachmentStreams.append(attachmentStream)
                                        }
                                        resolver.fulfill(())
                                    },
                                    failure: { error in
                                        resolver.reject(error)
                                    })
                }
            }

            guard !promises.isEmpty else {
                success(attachmentStreams)
                return
            }

            // Block until _all_ promises have either succeeded or failed.
            _ = firstly(on: .global()) {
                when(fulfilled: promises)
            }.done(on: Self.serialQueue) { _ in
                let attachmentStreamsCopy = unfairLock.withLock { attachmentStreams }
                Logger.info("Attachment downloads succeeded: \(attachmentStreamsCopy.count).")

                success(attachmentStreamsCopy)
            }.catch(on: Self.serialQueue) { error in
                Logger.warn("Attachment downloads failed.")
                owsFailDebugUnlessNetworkFailure(error)

                failure(error)
            }
        }
    }

    @objc
    static func buildError() -> Error {
        OWSErrorWithCodeDescription(.attachmentDownloadFailed,
                                    NSLocalizedString("ERROR_MESSAGE_ATTACHMENT_DOWNLOAD_FAILED",
                                                      comment: "Error message indicating that attachment download(s) failed."))
    }

    // MARK: -

    @objc
    static let serialQueue: DispatchQueue = {
        return DispatchQueue(label: "org.whispersystems.signal.download",
                             qos: .utility,
                             autoreleaseFrequency: .workItem)
    }()

    // We want to avoid large downloads from a compromised or buggy service.
    private static let maxDownloadSize = 150 * 1024 * 1024

    @objc
    func retrieveAttachment(job: OWSAttachmentDownloadJob,
                            attachmentPointer: TSAttachmentPointer,
                            success: @escaping (TSAttachmentStream) -> Void,
                            failure: @escaping (Error) -> Void) {
        firstly {
            Self.retrieveAttachment(job: job, attachmentPointer: attachmentPointer)
        }.done(on: Self.serialQueue) { (attachmentStream: TSAttachmentStream) in
            success(attachmentStream)
        }.catch(on: Self.serialQueue) { (error: Error) in
            failure(error)
        }
    }

    private class func retrieveAttachment(job: OWSAttachmentDownloadJob,
                                          attachmentPointer: TSAttachmentPointer) -> Promise<TSAttachmentStream> {

        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "retrieveAttachment")

        return firstly(on: Self.serialQueue) { () -> Promise<URL> in
            Self.download(job: job, attachmentPointer: attachmentPointer)
        }.then(on: Self.serialQueue) { (encryptedFileUrl: URL) -> Promise<TSAttachmentStream> in
            Self.decrypt(encryptedFileUrl: encryptedFileUrl,
                         attachmentPointer: attachmentPointer)
        }.ensure(on: Self.serialQueue) {
            guard backgroundTask != nil else {
                owsFailDebug("Missing backgroundTask.")
                return
            }
            backgroundTask = nil
        }
    }

    private class DownloadState {
        let job: OWSAttachmentDownloadJob
        let attachmentPointer: TSAttachmentPointer

        required init(job: OWSAttachmentDownloadJob, attachmentPointer: TSAttachmentPointer) {
            self.job = job
            self.attachmentPointer = attachmentPointer
        }
    }

    func test() {}

    private class func download(job: OWSAttachmentDownloadJob,
                                attachmentPointer: TSAttachmentPointer) -> Promise<URL> {

        let downloadState = DownloadState(job: job, attachmentPointer: attachmentPointer)

        return firstly(on: Self.serialQueue) { () -> Promise<URL> in
            Self.downloadAttempt(downloadState: downloadState)
        }
    }

    private class func downloadAttempt(downloadState: DownloadState,
                                       resumeData: Data? = nil,
                                       attemptIndex: UInt = 0) -> Promise<URL> {

        return firstly(on: Self.serialQueue) { () -> Promise<OWSUrlDownloadResponse> in
            let attachmentPointer = downloadState.attachmentPointer
            let urlSession = self.signalService.urlSessionForCdn(cdnNumber: attachmentPointer.cdnNumber)
            let urlPath = try Self.urlPath(for: downloadState)
            let headers: [String: String] = [
                "Content-Type": OWSMimeTypeApplicationOctetStream
            ]

            let progress = { (task: URLSessionTask, progress: Progress) in
                Self.handleDownloadProgress(downloadState: downloadState,
                                            task: task,
                                            progress: progress)
            }

            if let resumeData = resumeData {
                return urlSession.urlDownloadTaskPromise(resumeData: resumeData,
                                                         progress: progress)
            } else {
                return urlSession.urlDownloadTaskPromise(urlPath,
                                                         method: .get,
                                                         headers: headers,
                                                         progress: progress)
            }
        }.map(on: Self.serialQueue) { (response: OWSUrlDownloadResponse) in
            let downloadUrl = response.downloadUrl
            guard let fileSize = OWSFileSystem.fileSize(of: downloadUrl) else {
                throw OWSAssertionError("Could not determine attachment file size.")
            }
            guard fileSize.int64Value <= Self.maxDownloadSize else {
                throw OWSAssertionError("Attachment download length exceeds max size.")
            }
            return downloadUrl
        }.recover(on: Self.serialQueue) { (error: Error) -> Promise<URL> in
            Logger.warn("Error: \(error)")

            let maxAttemptCount = 16
            if IsNetworkConnectivityFailure(error),
                attemptIndex < maxAttemptCount {

                return firstly {
                    // Wait briefly before retrying.
                    after(seconds: 0.25)
                }.then { () -> Promise<URL> in
                    if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
                        !resumeData.isEmpty {
                        return self.downloadAttempt(downloadState: downloadState, resumeData: resumeData, attemptIndex: attemptIndex + 1)
                    } else {
                        return self.downloadAttempt(downloadState: downloadState, attemptIndex: attemptIndex + 1)
                    }
                }
            } else {
                throw error
            }
        }
    }

    private class func urlPath(for downloadState: DownloadState) throws -> String {

        let attachmentPointer = downloadState.attachmentPointer
        let urlPath: String
        if attachmentPointer.cdnKey.count > 0 {
            guard let encodedKey = attachmentPointer.cdnKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                throw OWSAssertionError("Invalid cdnKey.")
            }
            urlPath = "attachments/\(encodedKey)"
        } else {
            urlPath = String(format: "attachments/%llu", attachmentPointer.serverId)
        }
        return urlPath
    }

    private class func handleDownloadProgress(downloadState: DownloadState,
                                              task: URLSessionTask,
                                              progress: Progress) {
        // Don't do anything until we've received at least one byte of data.
        guard progress.completedUnitCount > 0 else {
            return
        }

        guard progress.totalUnitCount <= maxDownloadSize,
            progress.completedUnitCount <= maxDownloadSize else {
                // A malicious service might send a misleading content length header,
                // so....
                //
                // If the current downloaded bytes or the expected total byes
                // exceed the max download size, abort the download.
                owsFailDebug("Attachment download exceed expected content length: \(progress.totalUnitCount), \(progress.completedUnitCount).")
                task.cancel()
                return
        }

        downloadState.job.progress = CGFloat(progress.fractionCompleted)

        // Use a slightly non-zero value to ensure that the progress
        // indicator shows up as quickly as possible.
        let progressTheta: Double = 0.001
        Self.fireProgressNotification(progress: max(progressTheta, progress.fractionCompleted),
                                      attachmentId: downloadState.attachmentPointer.uniqueId)
    }

    // MARK: -

    private class func decrypt(encryptedFileUrl: URL,
                               attachmentPointer: TSAttachmentPointer) -> Promise<TSAttachmentStream> {

        // Use serialQueue to ensure that we only load into memory
        // & decrypt a single attachment at a time.
        return firstly(on: Self.serialQueue) { () -> TSAttachmentStream in
            let cipherText = try Data(contentsOf: encryptedFileUrl)
            return try Self.decrypt(cipherText: cipherText,
                                    attachmentPointer: attachmentPointer)
        }.ensure(on: Self.serialQueue) {
            do {
                try OWSFileSystem.deleteFileIfExists(url: encryptedFileUrl)
            } catch {
                owsFailDebug("Error: \(error).")
            }
        }
    }

    private class func decrypt(cipherText: Data,
                               attachmentPointer: TSAttachmentPointer) throws -> TSAttachmentStream {

        guard let encryptionKey = attachmentPointer.encryptionKey else {
            throw OWSAssertionError("Missing encryptionKey.")
        }
        return try autoreleasepool {
            let plaintext: Data = try Cryptography.decryptAttachment(cipherText,
                                                                     withKey: encryptionKey,
                                                                     digest: attachmentPointer.digest,
                                                                     unpaddedSize: attachmentPointer.byteCount)

            let attachmentStream = databaseStorage.read { transaction in
                TSAttachmentStream(pointer: attachmentPointer, transaction: transaction)
            }
            try attachmentStream.write(plaintext)
            return attachmentStream
        }
    }

    // MARK: -

    @objc
    static let attachmentDownloadProgressNotification = Notification.Name("AttachmentDownloadProgressNotification")
    @objc
    static let attachmentDownloadProgressKey = "attachmentDownloadProgressKey"
    @objc
    static let attachmentDownloadAttachmentIDKey = "attachmentDownloadAttachmentIDKey"

    private class func fireProgressNotification(progress: Double, attachmentId: String) {
        NotificationCenter.default.postNotificationNameAsync(attachmentDownloadProgressNotification,
                                                             object: nil,
                                                             userInfo: [
                                                                attachmentDownloadProgressKey: NSNumber(value: progress),
                                                                attachmentDownloadAttachmentIDKey: attachmentId
        ])
    }
}
