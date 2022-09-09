//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

// TODO: Support stubbing out OWSFileSystem more generally. This is a temporary
// SystemStoryManager-scoped wrapper to avoid refactoring all usages of OWSFileSystem.
@objc
public class OnboardingStoryManagerFilesystem: NSObject {

    public class func fileOrFolderExists(url: URL) -> Bool {
        return OWSFileSystem.fileOrFolderExists(url: url)
    }

    public class func fileSize(of url: URL) -> NSNumber? {
        return OWSFileSystem.fileSize(of: url)
    }

    public class func deleteFile(url: URL) throws {
        try OWSFileSystem.deleteFile(url: url)
    }

    public class func moveFile(from fromUrl: URL, to toUrl: URL) throws {
        try OWSFileSystem.moveFile(from: fromUrl, to: toUrl)
    }

    public class func isValidImage(at url: URL, mimeType: String?) -> Bool {
        return NSData.ows_isValidImage(at: url, mimeType: mimeType)
    }
}

@objc
public class SystemStoryManager: NSObject, Dependencies, SystemStoryManagerProtocol {

    private let fileSystem: OnboardingStoryManagerFilesystem.Type

    private let kvStore = SDSKeyValueStore(collection: "OnboardingStory")

    private let queue = DispatchQueue(label: "OnboardingStoryDownload", qos: .background)

    private lazy var chainedPromise = ChainedPromise<Void>(queue: queue)

    @objc
    public override convenience init() {
        self.init(fileSystem: OnboardingStoryManagerFilesystem.self)
    }

    init(fileSystem: OnboardingStoryManagerFilesystem.Type) {
        self.fileSystem = fileSystem
        super.init()

        if CurrentAppContext().isMainApp {
            AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
                _ = self?.enqueueOnboardingStoryDownload()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - API

    public func enqueueOnboardingStoryDownload() -> Promise<Void> {
        guard RemoteConfig.stories else {
            owsFailDebug("Onboarding story feature flag disabled")
            return .init(error: OWSAssertionError("Onboarding story unavailable"))
        }

        return chainedPromise.enqueue { [weak self] in
            return self?.downloadOnboardingStoryIfNeeded() ?? .init(error: OWSAssertionError("SystemStoryManager unretained"))
        }
    }

    public func cleanUpOnboardingStoryIfNeeded() -> Promise<Void> {
        guard RemoteConfig.stories else {
            owsFailDebug("Onboarding story feature flag disabled")
            return .init(error: OWSAssertionError("Onboarding story unavailable"))
        }

        return chainedPromise.enqueue { [weak self] () -> Promise<DownloadStatus> in
            return self?.checkDownloadStatus() ?? .init(error: OWSAssertionError("SystemStoryManager unretained"))
        }.map(on: queue) { _ in () }
    }

    // MARK: Hidden State

    private var stateChangeObservers = [SystemStoryStateChangeObserver]()

    public func addStateChangedObserver(_ observer: SystemStoryStateChangeObserver) {
        stateChangeObservers.append(observer)
    }

    public func removeStateChangedObserver(_ observer: SystemStoryStateChangeObserver) {
        stateChangeObservers.removeAll(where: { $0 == observer })
    }

    public func areSystemStoriesHidden(transaction: SDSAnyReadTransaction) -> Bool {
        // No need to make this serial with the other calls, db transactions cover us.
        kvStore.getBool(Constants.kvStoreHiddenStateKey, defaultValue: false, transaction: transaction)
    }

    public func setSystemStoriesHidden(_ hidden: Bool, transaction: SDSAnyWriteTransaction) {
        var changedRowIds = [Int64]()
        defer {
            DispatchQueue.main.async {
                self.stateChangeObservers.forEach { $0.systemStoryHiddenStateDidChange(rowIds: changedRowIds) }
            }
        }

        // No need to make this serial with the other calls, db transactions cover us.
        kvStore.setBool(hidden, key: Constants.kvStoreHiddenStateKey, transaction: transaction)

        guard
            let rawStatus = kvStore.getData(Constants.kvStoreOnboardingStoryStatusKey, transaction: transaction),
            let onboardingStatus = try? JSONDecoder().decode(DownloadStatus.self, from: rawStatus),
            let messageUniqueIds = onboardingStatus.messageUniqueIds,
            !messageUniqueIds.isEmpty
        else {
            return
        }
        let stories = StoryFinder.listStoriesWithUniqueIds(messageUniqueIds, transaction: transaction)
        stories.forEach {
            if hidden {
                $0.markAsViewed(at: Date().ows_millisecondsSince1970, circumstance: .onThisDevice, transaction: transaction)
            }
            if let rowId = $0.id {
                changedRowIds.append(rowId)
            }
        }
    }

    public func isOnboardingStoryViewed(transaction: SDSAnyReadTransaction) -> Bool {
        let status = downloadStatus(transaction: transaction)
        guard status.isDownloaded, let messageUniqueIds = status.messageUniqueIds, !messageUniqueIds.isEmpty else {
            return false
        }
        let stories = StoryFinder.listStoriesWithUniqueIds(messageUniqueIds, transaction: transaction)
        guard !stories.isEmpty else {
            // If they were deleted, we assume they were viewed and then deleted.
            return true
        }

        return stories.contains(where: { $0.localUserViewedTimestamp != nil })
    }

    // MARK: - Event Observation

    private var isObservingBackgrounding = false

    private func beginObservingAppBackground() {
        guard CurrentAppContext().isMainApp, !isObservingBackgrounding else {
            return
        }
        isObservingBackgrounding = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
    }

    private func stopObservingAppBackground() {
        isObservingBackgrounding = false
        NotificationCenter.default.removeObserver(self, name: .OWSApplicationDidEnterBackground, object: nil)
    }

    @objc
    private func didEnterBackground() {
        _ = self.cleanUpOnboardingStoryIfNeeded()
    }

    // MARK: - Implementation

    private func downloadOnboardingStoryIfNeeded() -> Promise<Void> {
        return checkDownloadStatus()
            .then(on: queue) { [weak self] (downloadStatus: DownloadStatus) -> Promise<Void> in
                guard !downloadStatus.isDownloaded else {
                    // Already done.
                    return .value(())
                }
                guard let strongSelf = self else {
                    return .init(error: OWSAssertionError("SystemStoryManager unretained"))
                }
                let urlSession = Self.signalService.urlSessionForUpdates2()
                return strongSelf.fetchFilenames(urlSession: urlSession)
                    .then(on: strongSelf.queue) { [weak self] (fileNames: [String]) -> Promise<[TSAttachmentStream]> in
                        let promises = fileNames.compactMap {
                            self?.downloadOnboardingAsset(urlSession: urlSession, url: $0)
                        }
                        return Promise.when(fulfilled: promises)
                    }
                    .then(on: strongSelf.queue) { [weak self] (attachmentStreams: [TSAttachmentStream]) -> Promise<Void> in
                        guard let strongSelf = self else {
                            return .init(error: OWSAssertionError("SystemStoryManager unretained"))
                        }
                        return strongSelf.databaseStorage.write(.promise) { transaction in
                            let uniqueIds = try strongSelf.createStoryMessages(
                                attachmentStreams: attachmentStreams,
                                transaction: transaction
                            )
                            try strongSelf.markDownloaded(
                                messageUniqueIds: uniqueIds,
                                transaction: transaction
                            )
                        }
                    }
                }
    }

    private struct DownloadStatus: Codable {
        var messageUniqueIds: [String]?

        var isDownloaded: Bool { return messageUniqueIds?.isEmpty == false }

        static var requiresDownload: Self { return .init(messageUniqueIds: nil) }
    }

    private func checkDownloadStatus() -> Promise<DownloadStatus> {
        return databaseStorage.write(.promise) { [weak self] transaction in
            guard let strongSelf = self else {
                throw OWSAssertionError("SystemStoryManager unretained")
            }
            return strongSelf.checkDownloadStatus(forceDeleteIfDownloaded: false, transaction: transaction)
        }
    }

    private func checkDownloadStatus(
        forceDeleteIfDownloaded: Bool,
        transaction: SDSAnyWriteTransaction
    ) -> DownloadStatus {
        let status = downloadStatus(transaction: transaction)
        if status.isDownloaded {
            // clean up opportunistically.
            try? self.cleanUpStoriesIfNeeded(
                messageUniqueIds: status.messageUniqueIds,
                forceDeleteIfDownloaded: forceDeleteIfDownloaded,
                transaction: transaction
            )
        }
        return status
    }

    private func downloadStatus(transaction: SDSAnyReadTransaction) -> DownloadStatus {
        guard
            let rawStatus = kvStore.getData(Constants.kvStoreOnboardingStoryStatusKey, transaction: transaction),
            let status = try? JSONDecoder().decode(DownloadStatus.self, from: rawStatus)
        else {
            return .requiresDownload
        }
        return status
    }

    private func cleanUpStoriesIfNeeded(
        messageUniqueIds: [String]?,
        forceDeleteIfDownloaded: Bool,
        transaction: SDSAnyWriteTransaction
    ) throws {
        guard let messageUniqueIds = messageUniqueIds, !messageUniqueIds.isEmpty else {
            self.stopObservingAppBackground()
            throw OWSAssertionError("No messages")
        }
        let stories = StoryFinder.listStoriesWithUniqueIds(messageUniqueIds, transaction: transaction)
        guard !stories.isEmpty else {
            return
        }

        var shouldDelete = forceDeleteIfDownloaded

        // If they exist and are expired, delete them.
        if
            let minViewTime = stories.lazy.compactMap(\.localUserViewedTimestamp).min(),
            Date().timeIntervalSince(Date(millisecondsSince1970: minViewTime)) >= Constants.postViewingTimeout
        {
            shouldDelete = true
        }

        if shouldDelete {
            stories.forEach {
                $0.sdsRemove(transaction: transaction)
            }
            // We've already cleaned up, no need to observe background anymore.
            self.stopObservingAppBackground()
        } else {
            // We should observe in the background so we delete later on.
            self.beginObservingAppBackground()
        }
    }

    private func fetchFilenames(
        urlSession: OWSURLSessionProtocol
    ) -> Promise<[String]> {
        return urlSession.dataTaskPromise(
            Constants.manifestPath,
            method: .get
        ).map(on: queue) { (response: HTTPResponse) throws -> [String] in
            guard
                let json = response.responseBodyJson,
                let responseDictionary = json as? [String: AnyObject],
                let version = responseDictionary[Constants.manifestVersionKey] as? String,
                let languages = responseDictionary[Constants.manifestLanguagesKey] as? [String: AnyObject]
            else {
                throw OWSAssertionError("Missing or invalid JSON")
            }
            guard
                let assetFilenames = Locale.current.languageCode.map({ languageCode in
                    languages[languageCode] as? [String]
                }) ?? (languages[Constants.fallbackLanguageCode] as? [String])
            else {
                throw OWSAssertionError("Unable to locate onboarding image set")
            }
            return assetFilenames.map {
                return Constants.imagePath(version: version, filename: $0)
            }
        }
    }

    private func downloadOnboardingAsset(
        urlSession: OWSURLSessionProtocol,
        url: String
    ) -> Promise<TSAttachmentStream> {
        return urlSession.downloadTaskPromise(
            url,
            method: .get
        ).map(on: self.queue) { [fileSystem] result in
            let resultUrl = result.downloadUrl

            guard fileSystem.fileOrFolderExists(url: resultUrl) else {
                throw OWSAssertionError("Onboarding story url missing")
            }
            guard
                fileSystem.isValidImage(at: resultUrl, mimeType: Constants.imageExtension),
                let byteCount = fileSystem.fileSize(of: resultUrl)
            else {
                throw OWSAssertionError("Invalid onboarding asset")
            }

            let attachmentStream = TSAttachmentStream(
                contentType: Constants.imageMimeType,
                byteCount: UInt32(truncating: byteCount),
                sourceFilename: resultUrl.lastPathComponent,
                caption: nil,
                albumMessageId: nil
            )
            attachmentStream.isUploaded = false
            attachmentStream.cdnKey = ""
            attachmentStream.cdnNumber = 0

            guard let attachmentFilePath = attachmentStream.originalFilePath else {
                throw OWSAssertionError("Created an attachment from a file but no filePath")
            }
            let finalUrl = URL(fileURLWithPath: attachmentFilePath)
            if fileSystem.fileOrFolderExists(url: finalUrl) {
                // Delete an existing file, doesn't matter since we just redownloaded.
                try fileSystem.deleteFile(url: finalUrl)
            }
            // Move from the temporary download location to its final location.
            try fileSystem.moveFile(from: resultUrl, to: finalUrl)

            return attachmentStream
        }
    }

    /// Returns unique Ids for the created messages. Fails if any one message creation fails.
    private func createStoryMessages(
        attachmentStreams: [TSAttachmentStream],
        transaction: SDSAnyWriteTransaction
    ) throws -> [String] {
        let baseTimestamp = Date().ows_millisecondsSince1970
        let ids = try attachmentStreams.lazy.enumerated().map { (i, attachment) throws -> String in
            let message = try StoryMessage.createFromSystemAuthor(
                attachment: attachment,
                // Ensure timestamps are unique since they are sometimes used for uniquing.
                timestamp: baseTimestamp + UInt64(i),
                transaction: transaction
            )
            return message.uniqueId
        }
        // start observing so we delete when we need to.
        self.beginObservingAppBackground()
        return ids
    }

    private func markDownloaded(
        messageUniqueIds: [String],
        transaction: SDSAnyWriteTransaction
    ) throws {
        try kvStore.setData(
            JSONEncoder().encode(DownloadStatus(messageUniqueIds: messageUniqueIds)),
            key: Constants.kvStoreOnboardingStoryStatusKey,
            transaction: transaction
        )
    }

    internal enum Constants {
        static let kvStoreOnboardingStoryStatusKey = "OnboardingStoryStatus"
        static let kvStoreHiddenStateKey = "SystemStoriesAreHidden"

        static let manifestPath = "dynamic/ios/stories/onboarding/manifest.json"
        static let manifestVersionKey = "version"
        static let manifestLanguagesKey = "languages"
        static let fallbackLanguageCode = "en"

        static func imagePath(version: String, filename: String) -> String {
            return "static/ios/stories/onboarding"
                .appendingPathComponent(version)
                .appendingPathComponent(filename)
                + Constants.imageExtension
        }
        static let imageExtension = ".jpg"
        static let imageMimeType = OWSMimeTypeImageJpeg
        static let imageWidth = 1125
        static let imageHeight = 1998

        static let postViewingTimeout: TimeInterval = 24 /* hrs */ * 60 * 60
    }
}
