//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

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
                guard Self.tsAccountManager.isOnboarded() else {
                    // Observe when the account is ready before we try and download.
                    self?.observeOnboardingChanges()
                    return
                }
                self?.enqueueOnboardingStoryDownload()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - API

    @discardableResult
    public func enqueueOnboardingStoryDownload() -> Promise<Void> {
        guard RemoteConfig.stories else {
            owsFailDebug("Onboarding story feature flag disabled")
            return .init(error: OWSAssertionError("Onboarding story unavailable"))
        }

        return chainedPromise.enqueue { [weak self] in
            return self?.downloadOnboardingStoryIfNeeded() ?? .init(error: OWSAssertionError("SystemStoryManager unretained"))
        }
    }

    @discardableResult
    public func cleanUpOnboardingStoryIfNeeded() -> Promise<Void> {
        guard RemoteConfig.stories else {
            owsFailDebug("Onboarding story feature flag disabled")
            return .init(error: OWSAssertionError("Onboarding story unavailable"))
        }

        return chainedPromise.enqueue { [weak self] () -> Promise<OnboardingStoryDownloadStatus> in
            return self?.checkOnboardingStoryDownloadStatus() ?? .init(error: OWSAssertionError("SystemStoryManager unretained"))
        }.asVoid()
    }

    public func isOnboardingStoryViewed(transaction: SDSAnyReadTransaction) -> Bool {
        let status = onboardingStoryViewStatus(transaction: transaction)
        switch status.status {
        case .notViewed:
            return false
        case .viewedOnThisDevice, .viewedOnAnotherDevice:
            return true
        }
    }

    public func setHasViewedOnboardingStoryOnAnotherDevice(transaction: SDSAnyWriteTransaction) {
        try? setOnboardingStoryViewedOnAnotherDevice(transaction: transaction)
        self.cleanUpOnboardingStoryIfNeeded()
    }

    // MARK: Hidden State

    private var stateChangeObservers = [SystemStoryStateChangeObserver]()

    public func addStateChangedObserver(_ observer: SystemStoryStateChangeObserver) {
        stateChangeObservers.append(observer)
    }

    public func removeStateChangedObserver(_ observer: SystemStoryStateChangeObserver) {
        stateChangeObservers.removeAll(where: { $0 == observer })
    }

    public func setSystemStoriesHidden(_ hidden: Bool, transaction: SDSAnyWriteTransaction) {
        var changedRowIds = [Int64]()
        defer {
            DispatchQueue.main.async {
                self.stateChangeObservers.forEach { $0.systemStoryHiddenStateDidChange(rowIds: changedRowIds) }
            }
        }

        // No need to make this serial with the other calls, db transactions cover us.
        self.setSystemStoryHidden(hidden, transaction: transaction)

        let onboardingStatus = onboardingStoryDownloadStatus(transaction: transaction)
        guard
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

    // MARK: - Internal Event Observation

    private func observeOnboardingChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onboardingStateDidChange),
            name: .onboardingStateDidChange,
            object: nil
        )
    }

    @objc private func onboardingStateDidChange() {
        guard Self.tsAccountManager.isOnboarded() else {
            return
        }
        NotificationCenter.default.removeObserver(self, name: .onboardingStateDidChange, object: nil)
        _ = self.enqueueOnboardingStoryDownload()
    }

    private var isObservingOnboardingStoryEvents = false
    private var storyMessagesObservation: DatabaseCancellable?

    private func beginObservingOnboardingStoryEventsIfNeeded(downloadStatus: OnboardingStoryDownloadStatus) {
        guard
            CurrentAppContext().isMainApp,
            !isObservingOnboardingStoryEvents,
            downloadStatus.isDownloaded,
            let messageUniqueIds = downloadStatus.messageUniqueIds
        else {
            return
        }

        let viewStatus = Self.databaseStorage.read {
            self.onboardingStoryViewStatus(transaction: $0)
        }
        switch viewStatus.status {
        case .viewedOnThisDevice, .viewedOnAnotherDevice:
            // No need to observe if we've already viewed.
            return
        case .notViewed:
            break
        }

        isObservingOnboardingStoryEvents = true

        // Observe app background to opportunistically delete timed out stories.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )

        // Observe view state changes for the stories.
        let observation = ValueObservation.tracking { db throws in
            try StoryMessage
                .filter(messageUniqueIds.contains(Column(StoryMessage.columnName(.uniqueId))))
                .fetchAll(db)
        }
        // Ignore the first emission that fires right away, we
        // want subsequent updates only.
        var hasEmitted = false
        storyMessagesObservation?.cancel()
        storyMessagesObservation = observation.start(
            in: databaseStorage.grdbStorage.pool,
            onError: { error in
                owsFailDebug("Failed to observe story view state: \(error))")
            }, onChange: { [weak self] changedModels in
                guard hasEmitted else {
                    hasEmitted = true
                    return
                }
                guard
                    let viewedTimstamp = changedModels
                        .lazy
                        .compactMap(\.localUserViewedTimestamp)
                        .min()
                else {
                    return
                }
                do {
                    try Self.databaseStorage.write {
                        try self?.setOnboardingStoryViewedOnThisDevice(atTimestamp: viewedTimstamp, transaction: $0)
                    }
                    self?.cleanUpOnboardingStoryIfNeeded()
                    self?.stopObservingOnboardingStoryEvents()
                } catch {
                    return
                }
            }
        )
    }

    private func stopObservingOnboardingStoryEvents() {
        isObservingOnboardingStoryEvents = false
        storyMessagesObservation?.cancel()
        storyMessagesObservation = nil
        NotificationCenter.default.removeObserver(self, name: .OWSApplicationDidEnterBackground, object: nil)
    }

    @objc
    private func didEnterBackground() {
        self.cleanUpOnboardingStoryIfNeeded()
    }

    // MARK: - Implementation

    private func downloadOnboardingStoryIfNeeded() -> Promise<Void> {
        let knownViewStatus = Self.databaseStorage.read {
            self.onboardingStoryViewStatus(transaction: $0)
        }
        switch knownViewStatus.status {
        case .viewedOnAnotherDevice:
            // We already know things are viewed, we can stop right away.
            return .value(())
        case .viewedOnThisDevice:
            // Already viewed, take the opportunity to clean up if we have to, but don't force it.
            return self.checkOnboardingStoryDownloadStatus().asVoid()
        case .notViewed:
            // Sync to check if we viewed on another device since last time we synced.
            return self.syncOnboardingStoryViewStatus()
                .then(on: queue) { [weak self] (viewStatus: OnboardingStoryViewStatus) -> Promise<Void> in
                    guard let strongSelf = self else {
                        return .init(error: OWSAssertionError("SystemStoryManager unretained"))
                    }
                    switch viewStatus.status {
                    case .viewedOnAnotherDevice:
                        // Already viewed, immediately delete anything we already downloaded.
                        return strongSelf.checkOnboardingStoryDownloadStatus(forceDeletingIfDownloaded: true).asVoid()
                    case .viewedOnThisDevice:
                        // Already viewed, take the opportunity to clean up if we have to, but don't force it.
                        return strongSelf.checkOnboardingStoryDownloadStatus().asVoid()
                    case .notViewed:
                        return strongSelf.downloadOnboardingStoryIfUndownloaded()
                    }
                }
        }
    }

    private func syncOnboardingStoryViewStatus() -> Promise<OnboardingStoryViewStatus> {
        Self.storageServiceManager.restoreOrCreateManifestIfNecessary()
            .then(on: queue) { [weak self] _ -> Promise<OnboardingStoryViewStatus> in
                guard let strongSelf = self else {
                    return .init(error: OWSAssertionError("SystemStoryManager unretained"))
                }
                // At this point, we will have synced the AccountRecord, which would call
                // `SystemStoryManager.setHasViewedOnboardingStoryOnAnotherDevice()` and write
                // to the database. Read from the database to get whatever the latest value is.
                return Self.databaseStorage.read(.promise) { transaction in
                    return strongSelf.onboardingStoryViewStatus(transaction: transaction)
                }
            }
    }

    private func downloadOnboardingStoryIfUndownloaded() -> Promise<Void> {
        return checkOnboardingStoryDownloadStatus()
            .then(on: queue) { [weak self] (downloadStatus: OnboardingStoryDownloadStatus) -> Promise<Void> in
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
                            try strongSelf.markOnboardingStoryDownloaded(
                                messageUniqueIds: uniqueIds,
                                transaction: transaction
                            )
                        }
                    }
                }
    }

    private func checkOnboardingStoryDownloadStatus(forceDeletingIfDownloaded: Bool = false) -> Promise<OnboardingStoryDownloadStatus> {
        return databaseStorage.write(.promise) { transaction -> OnboardingStoryDownloadStatus in
            let status = self.onboardingStoryDownloadStatus(transaction: transaction)
            if status.isDownloaded {
                // clean up opportunistically.
                try? self.cleanUpOnboardingStoriesIfNeeded(
                    messageUniqueIds: status.messageUniqueIds,
                    forceDeleteIfDownloaded: forceDeletingIfDownloaded,
                    transaction: transaction
                )
            }
            return status
        }.map(on: queue) { status -> OnboardingStoryDownloadStatus in
            DispatchQueue.main.async {
                self.beginObservingOnboardingStoryEventsIfNeeded(downloadStatus: status)
            }
            return status
        }
    }

    // MARK: Story Deletion

    private func cleanUpOnboardingStoriesIfNeeded(
        messageUniqueIds: [String]?,
        forceDeleteIfDownloaded: Bool,
        transaction: SDSAnyWriteTransaction
    ) throws {
        var forceDelete = forceDeleteIfDownloaded

        let viewStatus = self.onboardingStoryViewStatus(transaction: transaction)

        let viewedTimestamp: UInt64?
        var markViewedIfNotFound = false
        switch viewStatus.status {
        case .notViewed:
            // Legacy clients might have viewed stories from before we recorded viewed status.
            viewedTimestamp = nil
            markViewedIfNotFound = true
        case .viewedOnAnotherDevice:
            // Delete right away.
            forceDelete = true
            viewedTimestamp = nil
        case .viewedOnThisDevice:
            guard let timestamp = viewStatus.viewedTimestamp else {
                throw OWSAssertionError("Invalid view status")
            }
            viewedTimestamp = timestamp
        }

        let isExpired = viewedTimestamp.map {
            Date().timeIntervalSince(Date(millisecondsSince1970: $0)) >= Constants.postViewingTimeout
        } ?? false

        guard isExpired || forceDelete || markViewedIfNotFound else {
            return
        }

        guard let messageUniqueIds = messageUniqueIds, !messageUniqueIds.isEmpty else {
            throw OWSAssertionError("No messages")
        }
        let stories = StoryFinder.listStoriesWithUniqueIds(messageUniqueIds, transaction: transaction)
        guard !stories.isEmpty else {
            if markViewedIfNotFound {
                // this is a legacy client with stories that were viewed before
                // we kept track of viewed state independently.
                try self.setOnboardingStoryViewedOnThisDevice(
                    atTimestamp: Date.distantPast.ows_millisecondsSince1970,
                    transaction: transaction
                )
            }
            return
        }

        stories.forEach {
            $0.sdsRemove(transaction: transaction)
        }
    }

    // MARK: Downloading

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
        return ids
    }

    // MARK: - KV Store

    // MARK: Onboarding Story View Status

    private struct OnboardingStoryViewStatus: Codable {
        enum Status: Int, Codable {
            case notViewed
            case viewedOnThisDevice
            case viewedOnAnotherDevice
        }

        let status: Status
        // only set for viewedOnThisDevice
        let viewedTimestamp: UInt64?
    }

    private func onboardingStoryViewStatus(transaction: SDSAnyReadTransaction) -> OnboardingStoryViewStatus {
        guard
            let rawStatus = kvStore.getData(Constants.kvStoreOnboardingStoryViewStatusKey, transaction: transaction),
            let status = try? JSONDecoder().decode(OnboardingStoryViewStatus.self, from: rawStatus)
        else {
            return OnboardingStoryViewStatus(status: .notViewed, viewedTimestamp: nil)
        }
        return status
    }

    private func setOnboardingStoryViewedOnAnotherDevice(transaction: SDSAnyWriteTransaction) throws {
        try kvStore.setData(
            JSONEncoder().encode(OnboardingStoryViewStatus(status: .viewedOnAnotherDevice, viewedTimestamp: nil)),
            key: Constants.kvStoreOnboardingStoryViewStatusKey,
            transaction: transaction
        )
    }

    // TODO: exposed to internal for testing, it really shouldn't be. But we dont have
    // testing hooks into database observation.
    internal func setOnboardingStoryViewedOnThisDevice(
        atTimestamp timestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) throws {
        let oldStatus = onboardingStoryViewStatus(transaction: transaction)
        guard oldStatus.status == .notViewed else {
            return
        }
        try kvStore.setData(
            JSONEncoder().encode(OnboardingStoryViewStatus(status: .viewedOnThisDevice, viewedTimestamp: timestamp)),
            key: Constants.kvStoreOnboardingStoryViewStatusKey,
            transaction: transaction
        )
        Self.storageServiceManager.recordPendingLocalAccountUpdates()
    }

    // MARK: Onboarding Story Download Status

    private struct OnboardingStoryDownloadStatus: Codable {
        var messageUniqueIds: [String]?

        var isDownloaded: Bool { return messageUniqueIds?.isEmpty == false }

        static var requiresDownload: Self { return .init(messageUniqueIds: nil) }
    }

    private func onboardingStoryDownloadStatus(transaction: SDSAnyReadTransaction) -> OnboardingStoryDownloadStatus {
        guard
            let rawStatus = kvStore.getData(Constants.kvStoreOnboardingStoryDownloadStatusKey, transaction: transaction),
            let status = try? JSONDecoder().decode(OnboardingStoryDownloadStatus.self, from: rawStatus)
        else {
            return .requiresDownload
        }
        return status
    }

    internal func markOnboardingStoryDownloaded(
        messageUniqueIds: [String],
        transaction: SDSAnyWriteTransaction
    ) throws {
        let status = OnboardingStoryDownloadStatus(messageUniqueIds: messageUniqueIds)
        try kvStore.setData(
            JSONEncoder().encode(status),
            key: Constants.kvStoreOnboardingStoryDownloadStatusKey,
            transaction: transaction
        )
        DispatchQueue.main.async {
            self.beginObservingOnboardingStoryEventsIfNeeded(downloadStatus: status)
        }
    }

    // MARK: System Story Hidden Status

    public func areSystemStoriesHidden(transaction: SDSAnyReadTransaction) -> Bool {
        // No need to make this serial with the other calls, db transactions cover us.
        kvStore.getBool(Constants.kvStoreHiddenStateKey, defaultValue: false, transaction: transaction)
    }

    private func setSystemStoryHidden(_ hidden: Bool, transaction: SDSAnyWriteTransaction) {
        kvStore.setBool(hidden, key: Constants.kvStoreHiddenStateKey, transaction: transaction)
    }

    internal enum Constants {
        static let kvStoreOnboardingStoryViewStatusKey = "OnboardingStoryViewStatus"
        static let kvStoreOnboardingStoryDownloadStatusKey = "OnboardingStoryStatus"
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
