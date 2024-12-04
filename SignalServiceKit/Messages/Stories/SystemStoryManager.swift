//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
        return Data.ows_isValidImage(at: url, mimeType: mimeType)
    }
}

// TODO: Support stubbing out StoryMessage init more generally.
@objc
public class OnboardingStoryManagerStoryMessageFactory: NSObject {

    public class func createFromSystemAuthor(
        attachmentSource: AttachmentDataSource,
        timestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) throws -> StoryMessage {
        return try StoryMessage.createFromSystemAuthor(
            attachmentSource: attachmentSource,
            timestamp: timestamp,
            transaction: transaction
        )
    }

    public class func validateAttachmentContents(
        dataSource: DataSource,
        mimeType: String
    ) throws -> AttachmentDataSource {
        return try DependenciesBridge.shared.attachmentContentValidator.validateContents(
            dataSource: dataSource,
            shouldConsume: true,
            mimeType: mimeType,
            renderingFlag: .default,
            sourceFilename: nil
        )
    }
}

@objc
public class SystemStoryManager: NSObject, SystemStoryManagerProtocol {

    private let fileSystem: OnboardingStoryManagerFilesystem.Type
    private let messageProcessor: any Shims.MessageProcessor
    private let schedulers: Schedulers
    private let storyMessageFactory: OnboardingStoryManagerStoryMessageFactory.Type

    private let kvStore = KeyValueStore(collection: "OnboardingStory")
    private let overlayKvStore = KeyValueStore(collection: "StoryViewerOnboardingOverlay")
    private let groupStoryEducationStore = KeyValueStore(collection: "GroupStoryEducation")

    private let queue: Scheduler
    internal let chainedPromise: ChainedPromise<Void>

    public convenience init(appReadiness: AppReadiness, messageProcessor: MessageProcessor) {
        self.init(
            appReadiness: appReadiness,
            fileSystem: OnboardingStoryManagerFilesystem.self,
            messageProcessor: Wrappers.MessageProcessor(messageProcessor),
            schedulers: DispatchQueueSchedulers(),
            storyMessageFactory: OnboardingStoryManagerStoryMessageFactory.self
        )
    }

    init(
        appReadiness: AppReadiness,
        fileSystem: OnboardingStoryManagerFilesystem.Type,
        messageProcessor: any Shims.MessageProcessor,
        schedulers: Schedulers,
        storyMessageFactory: OnboardingStoryManagerStoryMessageFactory.Type
    ) {
        self.fileSystem = fileSystem
        self.messageProcessor = messageProcessor
        self.schedulers = schedulers
        self.storyMessageFactory = storyMessageFactory
        self.queue = schedulers.queue(label: "org.signal.story.onboarding", qos: .utility)
        self.chainedPromise = ChainedPromise<Void>(scheduler: self.queue)
        super.init()

        if CurrentAppContext().isMainApp {
            appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
                guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
                    // Observe when the account is ready before we try and download.
                    self?.observeRegistrationChanges()
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
        return chainedPromise.enqueue { [weak self] in
            return (self?.downloadOnboardingStoryIfNeeded() ?? .init(error: OWSAssertionError("SystemStoryManager unretained"))).catch(on: DispatchQueue.global()) { error in
                Logger.warn("\(error)")
            }
        }
    }

    @discardableResult
    public func cleanUpOnboardingStoryIfNeeded() -> Promise<Void> {
        return chainedPromise.enqueue { [weak self] () -> Promise<OnboardingStoryDownloadStatus> in
            return self?.checkOnboardingStoryDownloadStatus() ?? .init(error: OWSAssertionError("SystemStoryManager unretained"))
        }.asVoid()
    }

    public func isOnboardingStoryRead(transaction: SDSAnyReadTransaction) -> Bool {
        if onboardingStoryReadStatus(transaction: transaction) {
            return true
        }
        // If its viewed, that also counts as being read.
        return isOnboardingStoryViewed(transaction: transaction)
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

    public func setHasReadOnboardingStory(transaction: SDSAnyWriteTransaction, updateStorageService: Bool) {
        try? setOnboardingStoryRead(transaction: transaction, updateStorageService: updateStorageService)
    }

    public func setHasViewedOnboardingStory(
        source: OnboardingStoryViewSource,
        transaction: SDSAnyWriteTransaction
    ) throws {
        switch source {
        case .local(let timestamp, let updateStorageService):
            try setOnboardingStoryViewedOnThisDevice(
                atTimestamp: timestamp,
                shouldUpdateStorageService: updateStorageService,
                transaction: transaction
            )
        case .otherDevice:
            setHasViewedOnboardingStoryOnAnotherDevice(transaction: transaction)
        }
    }

    private func setHasViewedOnboardingStoryOnAnotherDevice(transaction: SDSAnyWriteTransaction) {
        try? setOnboardingStoryViewedOnAnotherDevice(transaction: transaction)
        self.cleanUpOnboardingStoryIfNeeded()
    }

    // MARK: Group story education

    public func isGroupStoryEducationSheetViewed(tx: SDSAnyReadTransaction) -> Bool {
        return groupStoryEducationStore.hasValue(
            Constants.kvStoreGroupStoryEducationSheetViewedKey,
            transaction: tx.asV2Read
        )
    }

    public func setGroupStoryEducationSheetViewed(tx: SDSAnyWriteTransaction) {
        groupStoryEducationStore.setBool(
            true,
            key: Constants.kvStoreGroupStoryEducationSheetViewedKey,
            transaction: tx.asV2Write
        )
    }

    // MARK: OnboardingOverlay state

    public func isOnboardingOverlayViewed(transaction: SDSAnyReadTransaction) -> Bool {
        if overlayKvStore.getBool(Constants.kvStoreOnboardingOverlayViewedKey, defaultValue: false, transaction: transaction.asV2Read) {
            return true
        }

        if isOnboardingStoryViewed(transaction: transaction) {
            // We don't sync view state for the onboarding overlay. But we can use
            // viewing of the onboarding story as an imperfect proxy; if they viewed it
            // that means they also definitely saw the viewer overlay.
            return true
        }
        return false
    }

    public func setOnboardingOverlayViewed(value: Bool, transaction: SDSAnyWriteTransaction) {
        overlayKvStore.setBool(value, key: Constants.kvStoreOnboardingOverlayViewedKey, transaction: transaction.asV2Write)
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
            schedulers.main.async {
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

    private func observeRegistrationChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registrationStateDidChange),
            name: .registrationStateDidChange,
            object: nil
        )
    }

    @objc
    private func registrationStateDidChange() {
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }
        NotificationCenter.default.removeObserver(self, name: .registrationStateDidChange, object: nil)
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

        let viewStatus = SSKEnvironment.shared.databaseStorageRef.read {
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
            in: SSKEnvironment.shared.databaseStorageRef.grdbStorage.pool,
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
                    try SSKEnvironment.shared.databaseStorageRef.write {
                        try self?.setOnboardingStoryViewedOnThisDevice(
                            atTimestamp: viewedTimstamp,
                            shouldUpdateStorageService: true,
                            transaction: $0
                        )
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
        let knownViewStatus = SSKEnvironment.shared.databaseStorageRef.read {
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
        messageProcessor.waitForFetchingAndProcessing()
            .then(on: queue) { SSKEnvironment.shared.storageServiceManagerRef.waitForPendingRestores() }
            .then(on: queue) { [weak self] _ -> Promise<OnboardingStoryViewStatus> in
                guard let strongSelf = self else {
                    return .init(error: OWSAssertionError("SystemStoryManager unretained"))
                }
                // At this point, we will have synced the AccountRecord, which would call
                // `SystemStoryManager.setHasViewedOnboardingStoryOnAnotherDevice()` and write
                // to the database. Read from the database to get whatever the latest value is.
                return .value(SSKEnvironment.shared.databaseStorageRef.read { transaction in
                    return strongSelf.onboardingStoryViewStatus(transaction: transaction)
                })
            }
    }

    private func downloadOnboardingStoryIfUndownloaded() -> Promise<Void> {
        let queue = self.queue
        return checkOnboardingStoryDownloadStatus()
            .then(on: queue) { [weak self] (downloadStatus: OnboardingStoryDownloadStatus) -> Promise<Void> in
                guard !downloadStatus.isDownloaded else {
                    // Already done.
                    return .value(())
                }
                guard let strongSelf = self else {
                    return .init(error: OWSAssertionError("SystemStoryManager unretained"))
                }
                let urlSession = SSKEnvironment.shared.signalServiceRef.urlSessionForUpdates2()
                return strongSelf.fetchFilenames(urlSession: urlSession)
                    .then(on: queue) { [weak self] (fileNames: [String]) -> Promise<[AttachmentDataSource]> in
                        let promises = fileNames.compactMap {
                            self?.downloadOnboardingAsset(urlSession: urlSession, url: $0)
                        }
                        return Promise.when(on: SyncScheduler(), fulfilled: promises)
                    }
                    .then(on: queue) { [weak self] (attachmentSources: [AttachmentDataSource]) -> Promise<Void> in
                        guard let strongSelf = self else {
                            return .init(error: OWSAssertionError("SystemStoryManager unretained"))
                        }
                        do {
                            return .value(try SSKEnvironment.shared.databaseStorageRef.write { transaction in
                                let uniqueIds = try strongSelf.createStoryMessages(
                                    attachmentSources: attachmentSources,
                                    transaction: transaction
                                )
                                try strongSelf.markOnboardingStoryDownloaded(
                                    messageUniqueIds: uniqueIds,
                                    transaction: transaction
                                )
                            })
                        } catch {
                            return .init(error: error)
                        }
                    }
                }
    }

    private func checkOnboardingStoryDownloadStatus(forceDeletingIfDownloaded: Bool = false) -> Promise<OnboardingStoryDownloadStatus> {
        let status = SSKEnvironment.shared.databaseStorageRef.write { transaction -> OnboardingStoryDownloadStatus in
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
        }

        schedulers.main.async {
            self.beginObservingOnboardingStoryEventsIfNeeded(downloadStatus: status)
        }
        return .value(status)
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
                    atTimestamp: 0,
                    shouldUpdateStorageService: true,
                    transaction: transaction
                )
            }
            return
        }

        guard isExpired || forceDelete else {
            return
        }

        stories.forEach {
            $0.anyRemove(transaction: transaction)
        }
    }

    // MARK: Downloading

    private func fetchFilenames(
        urlSession: OWSURLSessionProtocol
    ) -> Promise<[String]> {
        return Promise.wrapAsync {
            return try await urlSession.performRequest(Constants.manifestPath, method: .get)
        }.map(on: queue) { (response: HTTPResponse) throws -> [String] in
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
    ) -> Promise<AttachmentDataSource> {
        return Promise.wrapAsync {
            return try await urlSession.performDownload(url, method: .get)
        }.map(on: self.queue) { [fileSystem, storyMessageFactory] result in
            let resultUrl = result.downloadUrl

            guard fileSystem.fileOrFolderExists(url: resultUrl) else {
                throw OWSAssertionError("Onboarding story url missing")
            }
            guard
                fileSystem.isValidImage(at: resultUrl, mimeType: Constants.imageExtension)
            else {
                throw OWSAssertionError("Invalid onboarding asset")
            }
            let dataSource = try DataSourcePath(
                fileUrl: resultUrl,
                shouldDeleteOnDeallocation: CurrentAppContext().isRunningTests.negated
            )
            return try storyMessageFactory.validateAttachmentContents(
                dataSource: dataSource,
                mimeType: Constants.imageMimeType
            )
        }
    }

    /// Returns unique Ids for the created messages. Fails if any one message creation fails.
    private func createStoryMessages(
        attachmentSources: [AttachmentDataSource],
        transaction: SDSAnyWriteTransaction
    ) throws -> [String] {
        let baseTimestamp = Date().ows_millisecondsSince1970
        let ids = try attachmentSources.lazy.enumerated().map { (i, attachmentSource) throws -> String in
            let message = try storyMessageFactory.createFromSystemAuthor(
                attachmentSource: attachmentSource,
                // Ensure timestamps are unique since they are sometimes used for uniquing.
                timestamp: baseTimestamp + UInt64(i),
                transaction: transaction
            )
            return message.uniqueId
        }
        return ids
    }

    // MARK: - KV Store

    // MARK: Onboarding Story Read Status

    private func onboardingStoryReadStatus(transaction: SDSAnyReadTransaction) -> Bool {
        return kvStore.getBool(Constants.kvStoreOnboardingStoryIsReadKey, defaultValue: false, transaction: transaction.asV2Read)
    }

    private func setOnboardingStoryRead(transaction: SDSAnyWriteTransaction, updateStorageService: Bool) throws {
        guard !onboardingStoryReadStatus(transaction: transaction) else {
            return
        }
        kvStore.setBool(true, key: Constants.kvStoreOnboardingStoryIsReadKey, transaction: transaction.asV2Write)
        if updateStorageService {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
        }
        NotificationCenter.default.postNotificationNameAsync(.onboardingStoryStateDidChange, object: nil)
    }

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
            let rawStatus = kvStore.getData(Constants.kvStoreOnboardingStoryViewStatusKey, transaction: transaction.asV2Read),
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
            transaction: transaction.asV2Write
        )
        NotificationCenter.default.postNotificationNameAsync(.onboardingStoryStateDidChange, object: nil)
    }

    private func setOnboardingStoryViewedOnThisDevice(
        atTimestamp timestamp: UInt64,
        shouldUpdateStorageService: Bool,
        transaction: SDSAnyWriteTransaction
    ) throws {
        let oldStatus = onboardingStoryViewStatus(transaction: transaction)
        guard oldStatus.status == .notViewed else {
            return
        }
        try kvStore.setData(
            JSONEncoder().encode(OnboardingStoryViewStatus(status: .viewedOnThisDevice, viewedTimestamp: timestamp)),
            key: Constants.kvStoreOnboardingStoryViewStatusKey,
            transaction: transaction.asV2Write
        )
        if shouldUpdateStorageService {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
        }
        NotificationCenter.default.postNotificationNameAsync(.onboardingStoryStateDidChange, object: nil)
    }

    // MARK: Onboarding Story Download Status

    private struct OnboardingStoryDownloadStatus: Codable {
        var messageUniqueIds: [String]?

        var isDownloaded: Bool { return messageUniqueIds?.isEmpty == false }

        static var requiresDownload: Self { return .init(messageUniqueIds: nil) }
    }

    private func onboardingStoryDownloadStatus(transaction: SDSAnyReadTransaction) -> OnboardingStoryDownloadStatus {
        guard
            let rawStatus = kvStore.getData(Constants.kvStoreOnboardingStoryDownloadStatusKey, transaction: transaction.asV2Read),
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
            transaction: transaction.asV2Write
        )
        DispatchQueue.main.async {
            self.beginObservingOnboardingStoryEventsIfNeeded(downloadStatus: status)
            NotificationCenter.default.post(name: .onboardingStoryStateDidChange, object: nil)
        }
    }

    // MARK: System Story Hidden Status

    public func areSystemStoriesHidden(transaction: SDSAnyReadTransaction) -> Bool {
        // No need to make this serial with the other calls, db transactions cover us.
        kvStore.getBool(Constants.kvStoreHiddenStateKey, defaultValue: false, transaction: transaction.asV2Read)
    }

    private func setSystemStoryHidden(_ hidden: Bool, transaction: SDSAnyWriteTransaction) {
        kvStore.setBool(hidden, key: Constants.kvStoreHiddenStateKey, transaction: transaction.asV2Write)
        NotificationCenter.default.postNotificationNameAsync(.onboardingStoryStateDidChange, object: nil)
    }

    internal enum Constants {
        static let kvStoreOnboardingStoryIsReadKey = "OnboardingStoryIsRead"
        static let kvStoreOnboardingStoryViewStatusKey = "OnboardingStoryViewStatus"
        static let kvStoreOnboardingStoryDownloadStatusKey = "OnboardingStoryStatus"
        static let kvStoreHiddenStateKey = "SystemStoriesAreHidden"
        static let kvStoreOnboardingOverlayViewedKey = "hasSeenStoryViewerOnboardingOverlay" // leading 'h' lowercase for legacy reasons
        static let kvStoreGroupStoryEducationSheetViewedKey = "GroupStoryEducationSheetViewed"

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
        static let imageMimeType = MimeType.imageJpeg.rawValue
        static let imageWidth = 1125
        static let imageHeight = 1998

        static let postViewingTimeout: TimeInterval = 24 /* hrs */ * 60 * 60
    }
}

// MARK: - Shims

extension SystemStoryManager {
    public enum Shims {
        public typealias MessageProcessor = _SystemStoryManager_MessageProcessorShim
    }

    public enum Wrappers {
        public typealias MessageProcessor = _SystemStoryManager_MessageProcessorWrapper
    }
}

// MARK: MessageProcessor

public protocol _SystemStoryManager_MessageProcessorShim {
    func waitForFetchingAndProcessing() -> Guarantee<Void>
}

public class _SystemStoryManager_MessageProcessorWrapper: _SystemStoryManager_MessageProcessorShim {

    private let messageProcessor: MessageProcessor

    public init(_ messageProcessor: MessageProcessor) {
        self.messageProcessor = messageProcessor
    }

    public func waitForFetchingAndProcessing() -> Guarantee<Void> {
        return self.messageProcessor.waitForFetchingAndProcessing()
    }
}
