//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

// Stickers
//
// * Stickers are either "installed" or not.
// * We can only send installed stickers.
// * When we receive a sticker, we download it like any other attachment...
//   ...unless we have it installed in which case we skip the download as
//   an optimization.
//
// Sticker Packs
//
// * Some "default" sticker packs ship in the app. See DefaultStickerPack.
//   Some "default" packs auto-install, others don't.
// * Other packs can be installed from "sticker pack shares" and "sticker pack URLs".
// * There are also "known" packs, e.g. packs the client knows about because
//   we received a sticker from that pack.
// * All of the above (default packs, packs installed from shares, known packs)
//   show up in the sticker management view.  Those that are installed are
//   shown as such; the others are shown as "available".
// * We download pack manifests & covers for "default" but not "known" packs.
//   Once we've download the manifest the pack is "saved" but not "installed".
// * We discard sticker and pack info once it is no longer in use.

public class StickerManager {

    // MARK: - Constants

    public static let packKeyLength: UInt = 32

    // MARK: - Notifications

    public static let packsDidChange = Notification.Name("packsDidChange")
    public static let stickersOrPacksDidChange = Notification.Name("stickersOrPacksDidChange")
    public static let recentStickersDidChange = Notification.Name("recentStickersDidChange")

    private let packsDidChangeEvent: DebouncedEvent = DebouncedEvents.build(
        mode: .firstLast,
        maxFrequencySeconds: 0.5,
        onQueue: .global(),
        notifyBlock: {
            NotificationCenter.default.postOnMainThread(name: packsDidChange, object: nil)
            NotificationCenter.default.postOnMainThread(name: stickersOrPacksDidChange, object: nil)
        },
    )

    private let stickersDidChangeEvent: DebouncedEvent = DebouncedEvents.build(
        mode: .firstLast,
        maxFrequencySeconds: 0.5,
        onQueue: .global(),
        notifyBlock: {
            NotificationCenter.default.postOnMainThread(name: stickersOrPacksDidChange, object: nil)
        },
    )

    // MARK: - Properties

    private let store = KeyValueStore(collection: "recentStickers")
    private let emojiMapStore = KeyValueStore(collection: "emojiMap")

    public enum InstallMode: Int {
        case doNotInstall
        case install
        // For default packs that should be auto-installed,
        // we only want to install the first time we save them.
        // If a user subsequently uninstalls the pack, we want
        // to honor that.
        case installIfUnsaved
    }

    private let queueLoader: TaskQueueLoader<StickerPackDownloadTaskRunner>

    private let interactionStore: InteractionStore
    private let db: DB
    private let attachmentStore: AttachmentStore
    private let attachmentDownloadStore: AttachmentDownloadStore
    private let tsAccountManager: TSAccountManager
    private let messageSenderJobQueue: MessageSenderJobQueue
    private let _cacheDirUrl: URL?

    private let stickerInstallQueue = KeyedConcurrentTaskQueue<String>(concurrentLimitPerKey: 1)

    // MARK: - Initializers

    init(
        appReadiness: AppReadiness,
        dateProvider: @escaping DateProvider,
        attachmentStore: AttachmentStore,
        attachmentDownloadStore: AttachmentDownloadStore,
        tsAccountManager: TSAccountManager,
        messageSenderJobQueue: MessageSenderJobQueue,
        interactionStore: InteractionStore,
        cacheDirUrl: URL? = nil,
        db: DB,
    ) {
        let runner = StickerPackDownloadTaskRunner(
            store: StickerPackDownloadTaskRecordStore(
                store: BackupStickerPackDownloadStore(),
            ),
            db: db,
        )
        self.queueLoader = TaskQueueLoader(
            maxConcurrentTasks: 4,
            dateProvider: dateProvider,
            db: db,
            runner: runner,
        )

        self.attachmentStore = attachmentStore
        self.attachmentDownloadStore = attachmentDownloadStore
        self.tsAccountManager = tsAccountManager
        self.messageSenderJobQueue = messageSenderJobQueue
        self.interactionStore = interactionStore
        self._cacheDirUrl = cacheDirUrl
        self.db = db

        runner.stickerManager = self

        // Resume sticker and sticker pack downloads when app is ready.
        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [self] in
            downloadPendingStickerPacks()
        }

        _ = NotificationCenter.default.addObserver(
            name: .registrationStateDidChange,
            block: { [weak self] _ in
                guard let self else { return }
                downloadPendingStickerPacks()
            },
        )
    }

    // MARK: -

    private let downloadPendingStickerPacksTaskQueue = SerialTaskQueue()

    // The sticker manager is responsible for downloading more than one kind
    // of content; those downloads can fail.  Therefore the sticker manager
    // retries those downloads, sometimes in response to user activity.
    public func downloadPendingStickerPacks() {
        downloadPendingStickerPacksTaskQueue.enqueue { [self] in
            guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
                return
            }

            try? await queueLoader.loadAndRunTasks()

            // Try to download the manifests for "default" sticker packs.
            let manifestDownloadPromises = tryToDownloadDefaultStickerPacks()
            for promise in manifestDownloadPromises {
                try? await promise.awaitable()
            }

            // Try to download the stickers for "installed" sticker packs.
            let stickerDownloadPromises = db.read { tx in
                ensureAllStickerDownloadsAsync(tx: tx)
            }
            for promise in stickerDownloadPromises {
                try? await promise.awaitable()
            }
        }
    }

    // MARK: - Paths

    private class func ensureCacheDirUrl() -> URL {
        var url = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
        url.appendPathComponent("StickerManager")
        OWSFileSystem.ensureDirectoryExists(url.path)
        return url
    }

    private static let defaultCacheDirUrl = {
        return ensureCacheDirUrl()
    }()

    public func cacheDirUrl() -> URL {
        if let cacheDirUrl = self._cacheDirUrl {
            return cacheDirUrl
        } else {
            return Self.defaultCacheDirUrl
        }
    }

    // MARK: - Sticker Packs

    public func allStickerPacks(transaction: DBReadTransaction) -> [StickerPackRecord] {
        return StickerPackRecord.anyFetchAll(transaction: transaction)
    }

    public func installedStickerPacks(transaction: DBReadTransaction) -> [StickerPackRecord] {
        return allStickerPacks(transaction: transaction).filter {
            $0.isInstalled
        }
    }

    public func isStickerPackSaved(stickerPackInfo: StickerPackInfo, transaction: DBReadTransaction) -> Bool {
        return nil != fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction)
    }

    public func uninstallStickerPack(
        stickerPackInfo: StickerPackInfo,
        wasLocallyInitiated: Bool,
        transaction: DBWriteTransaction,
    ) {
        guard let stickerPack = fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction) else {
            Logger.info("Skipping uninstall; not saved or installed.")
            return
        }

        let isDefaultStickerPack = DefaultStickerPack.isDefaultStickerPack(packId: stickerPackInfo.packId)
        let shouldRemove = !isDefaultStickerPack

        if shouldRemove {
            uninstallSticker(stickerInfo: stickerPack.coverInfo, transaction: transaction)

            for stickerInfo in stickerPack.stickerInfos() {
                if stickerInfo == stickerPack.coverInfo {
                    // Don't uninstall the cover for saved packs.
                    continue
                }
                uninstallSticker(stickerInfo: stickerInfo, transaction: transaction)
            }

            stickerPack.anyRemove(transaction: transaction)
        } else {
            stickerPack.updateWith(isInstalled: false, tx: transaction)
        }

        if wasLocallyInitiated {
            enqueueStickerSyncMessage(
                operationType: .remove,
                packs: [stickerPackInfo],
                transaction: transaction,
            )
        }

        transaction.addSyncCompletion {
            self.packsDidChangeEvent.requestNotify()
        }
    }

    public func installStickerPack(
        stickerPack: StickerPackRecord,
        wasLocallyInitiated: Bool,
        transaction: DBWriteTransaction,
    ) {
        upsertStickerPack(
            stickerPack: stickerPack,
            installMode: .install,
            wasLocallyInitiated: wasLocallyInitiated,
            transaction: transaction,
        )
    }

    public func fetchStickerPack(stickerPackInfo: StickerPackInfo, transaction: DBReadTransaction) -> StickerPackRecord? {
        let uniqueId = StickerPackRecord.uniqueId(forStickerPackInfo: stickerPackInfo)
        return StickerPackRecord.anyFetch(uniqueId: uniqueId, transaction: transaction)
    }

    private func tryToDownloadAndSaveStickerPack(
        stickerPackInfo: StickerPackInfo,
        installMode: InstallMode,
        wasLocallyInitiated: Bool,
    ) -> Promise<Void> {
        return Promise.wrapAsync { [self] in
            let stickerPack = try await tryToDownloadStickerPack(stickerPackInfo: stickerPackInfo).awaitable()
            await db.awaitableWrite { tx in
                upsertStickerPack(
                    stickerPack: stickerPack,
                    installMode: installMode,
                    wasLocallyInitiated: wasLocallyInitiated,
                    transaction: tx,
                )
            }
        }
    }

    private let packOperationQueue = ConcurrentTaskQueue(concurrentLimit: 3)

    public func tryToDownloadStickerPack(stickerPackInfo: StickerPackInfo) -> Promise<StickerPackRecord> {
        return Promise.wrapAsync { [packOperationQueue] in
            return try await packOperationQueue.runWithThrowingTask {
                return try await DownloadStickerPackOperation.run(stickerPackInfo: stickerPackInfo)
            }
        }
    }

    private func upsertStickerPack(
        stickerPack stickerPackParam: StickerPackRecord,
        installMode: InstallMode,
        wasLocallyInitiated: Bool,
        transaction: DBWriteTransaction,
    ) {
        // If we re-insert a sticker pack, make sure that it
        // has a new row id.
        _ = stickerPackParam as NSCopying
        let stickerPack = stickerPackParam.copy() as! StickerPackRecord
        stickerPack.id = nil

        let oldCopy = fetchStickerPack(stickerPackInfo: stickerPack.info, transaction: transaction)
        let wasSaved = oldCopy != nil

        // Preserve old mutable state.
        if let oldCopy {
            stickerPack.updateWith(isInstalled: oldCopy.isInstalled, tx: transaction)
        } else {
            stickerPack.anyInsert(transaction: transaction)
        }

        if stickerPack.isInstalled, wasLocallyInitiated {
            enqueueStickerSyncMessage(
                operationType: .install,
                packs: [stickerPack.info],
                transaction: transaction,
            )
        }

        // If the pack is already installed, make sure all stickers are installed.
        let promise: Promise<Void>
        if stickerPack.isInstalled {
            promise = installStickerPackContents(stickerPack: stickerPack, transaction: transaction)
        } else {
            switch installMode {
            case .doNotInstall:
                promise = .value(())
            case .install:
                promise = self.markSavedStickerPackAsInstalled(
                    stickerPack: stickerPack,
                    wasLocallyInitiated: wasLocallyInitiated,
                    transaction: transaction,
                )
            case .installIfUnsaved:
                if !wasSaved {
                    promise = self.markSavedStickerPackAsInstalled(
                        stickerPack: stickerPack,
                        wasLocallyInitiated: wasLocallyInitiated,
                        transaction: transaction,
                    )
                } else {
                    promise = .value(())
                }
            }
        }

        transaction.addSyncCompletion {
            _ = promise.ensure {
                self.packsDidChangeEvent.requestNotify()
            }
        }
    }

    private func markSavedStickerPackAsInstalled(
        stickerPack: StickerPackRecord,
        wasLocallyInitiated: Bool,
        transaction: DBWriteTransaction,
    ) -> Promise<Void> {
        if stickerPack.isInstalled {
            return .value(())
        }

        stickerPack.updateWith(isInstalled: true, tx: transaction)

        let promise = installStickerPackContents(stickerPack: stickerPack, transaction: transaction)

        if wasLocallyInitiated {
            enqueueStickerSyncMessage(
                operationType: .install,
                packs: [stickerPack.info],
                transaction: transaction,
            )
        }
        return promise
    }

    private func installStickerPackContents(
        stickerPack: StickerPackRecord,
        transaction: DBReadTransaction,
        onlyInstallCover: Bool = false,
    ) -> Promise<Void> {
        // Note: It's safe to kick off downloads of stickers that are already installed.
        var fetches = [Promise<Void>]()
        var needsNotify = false

        // The cover.
        let coverFetch = firstly {
            tryToDownloadAndInstallSticker(
                stickerPack: stickerPack,
                item: stickerPack.cover,
                transaction: transaction,
            )
        }.done { (shouldNotify: Bool) in
            if shouldNotify {
                self.stickersDidChangeEvent.requestNotify()
                needsNotify = false
            }
        }
        fetches.append(coverFetch)

        guard !onlyInstallCover else {
            return Promise.when(fulfilled: fetches)
        }

        // The stickers.
        for item in stickerPack.items {
            fetches.append(
                firstly {
                    tryToDownloadAndInstallSticker(
                        stickerPack: stickerPack,
                        item: item,
                        transaction: transaction,
                    )
                }.done { shouldNotify in
                    if shouldNotify, coverFetch.isSealed {
                        // We should only notify for changes once we've fetched the cover
                        // Some views will assume that an installed pack always has a cover
                        // and faildebug otherwise
                        self.stickersDidChangeEvent.requestNotify()
                        needsNotify = false
                    } else if shouldNotify {
                        needsNotify = true
                    }
                },
            )
        }
        return Promise.when(fulfilled: fetches).ensure {
            if needsNotify {
                self.stickersDidChangeEvent.requestNotify()
            }
        }
    }

    private func tryToDownloadDefaultStickerPacks() -> [Promise<Void>] {
        let autoInstallPromises = tryToDownloadStickerPacks(
            stickerPacks: DefaultStickerPack.packsToAutoInstall,
            installMode: .installIfUnsaved,
        )
        let notAutoInstallPromises = tryToDownloadStickerPacks(
            stickerPacks: DefaultStickerPack.packsToNotAutoInstall,
            installMode: .doNotInstall,
        )

        return autoInstallPromises + notAutoInstallPromises
    }

    public func installedStickers(
        forStickerPack stickerPack: StickerPackRecord,
        verifyExists: Bool,
        transaction: DBReadTransaction,
    ) -> [StickerInfo] {
        var result = [StickerInfo]()
        for stickerInfo in stickerPack.stickerInfos() {
            let uniqueId = InstalledStickerRecord.uniqueId(for: stickerInfo)
            guard let installedSticker = InstalledStickerRecord.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
                continue
            }
            if verifyExists, self.stickerDataUrl(forInstalledSticker: installedSticker, verifyExists: verifyExists) == nil {
                continue
            }
            result.append(stickerInfo)
        }
        return result
    }

    public class func isDefaultStickerPack(packId: Data) -> Bool {
        return DefaultStickerPack.isDefaultStickerPack(packId: packId)
    }

    public func isStickerPackInstalled(stickerPackInfo: StickerPackInfo, transaction: DBReadTransaction) -> Bool {
        guard let pack = fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction) else {
            return false
        }
        return pack.isInstalled
    }

    // MARK: - Stickers

    public static func stickerType(forContentType contentType: String?) -> StickerType {
        return StickerType.stickerType(forContentType: contentType)
    }

    public func installedStickerMetadata(
        stickerInfo: StickerInfo,
        transaction: DBReadTransaction,
    ) -> (any StickerMetadata)? {
        let uniqueId = InstalledStickerRecord.uniqueId(for: stickerInfo)
        guard let installedSticker = InstalledStickerRecord.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
            return nil
        }
        return installedStickerMetadata(installedSticker: installedSticker)
    }

    public func installedStickerMetadata(
        installedSticker: InstalledStickerRecord,
    ) -> (any StickerMetadata)? {
        let stickerInfo = installedSticker.info
        let stickerType = StickerType.stickerType(forContentType: installedSticker.contentType)
        guard let stickerDataUrl = stickerDataUrl(stickerInfo: stickerInfo, stickerType: stickerType, verifyExists: true) else {
            return nil
        }

        guard let localKey = installedSticker.localKey, let plaintextLength = installedSticker.plaintextLength else {
            // If an installed sticker has no local key & plaintext length,
            // assume it hasn't been migrated yet and can be accessed as decrypted metadata.
            return DecryptedStickerMetadata(
                stickerInfo: stickerInfo,
                stickerType: stickerType,
                stickerDataUrl: stickerDataUrl,
                emojiString: installedSticker.emojiString,
            )
        }

        return EncryptedStickerMetadata(
            stickerInfo: stickerInfo,
            stickerType: stickerType,
            emojiString: installedSticker.emojiString,
            encryptedStickerDataUrl: stickerDataUrl,
            encryptionKey: localKey,
            plaintextLength: plaintextLength,
        )
    }

    private func stickerDataUrl(stickerInfo: StickerInfo, contentType: String?, verifyExists: Bool) -> URL? {
        let stickerType = StickerType.stickerType(forContentType: contentType)
        return stickerDataUrl(stickerInfo: stickerInfo, stickerType: stickerType, verifyExists: verifyExists)
    }

    public func stickerDataUrl(forInstalledSticker installedSticker: InstalledStickerRecord, verifyExists: Bool) -> URL? {
        let stickerInfo = installedSticker.info
        let stickerType = StickerType.stickerType(forContentType: installedSticker.contentType)
        return stickerDataUrl(stickerInfo: stickerInfo, stickerType: stickerType, verifyExists: verifyExists)
    }

    private func stickerDataUrl(stickerInfo: StickerInfo, stickerType: StickerType, verifyExists: Bool) -> URL? {
        let uniqueId = InstalledStickerRecord.uniqueId(for: stickerInfo)
        var url = cacheDirUrl()
        // Not all stickers are .webp.
        url.appendPathComponent("\(uniqueId).\(stickerType.fileExtension)")
        if verifyExists, !OWSFileSystem.fileOrFolderExists(url: url) {
            return nil
        }
        return url
    }

    public func filePathsForAllInstalledStickers(transaction: DBReadTransaction) -> [String] {
        var filePaths = [String]()
        InstalledStickerRecord.anyEnumerate(transaction: transaction) { installedSticker, _ in
            if let stickerDataUrl = stickerDataUrl(forInstalledSticker: installedSticker, verifyExists: false) {
                filePaths.append(stickerDataUrl.path)
            }
        }
        return filePaths
    }

    public func isStickerInstalled(stickerInfo: StickerInfo, transaction: DBReadTransaction) -> Bool {
        let installedSticker = fetchInstalledSticker(stickerInfo: stickerInfo, transaction: transaction)
        guard let installedSticker else {
            return false
        }

        return stickerDataUrl(forInstalledSticker: installedSticker, verifyExists: true) != nil
    }

    typealias CleanupCompletion = () -> Void

    func uninstallSticker(stickerInfo: StickerInfo, transaction: DBWriteTransaction) {
        guard let installedSticker = fetchInstalledSticker(stickerInfo: stickerInfo, transaction: transaction) else {
            Logger.info("Skipping uninstall; not installed.")
            return
        }

        installedSticker.anyRemove(transaction: transaction)

        removeFromRecentStickers(stickerInfo, transaction: transaction)

        removeStickerFromEmojiMap(installedSticker, tx: transaction)

        guard let stickerDataUrl = self.stickerDataUrl(forInstalledSticker: installedSticker, verifyExists: false) else {
            owsFailDebug("Could not generate sticker data URL.")
            return
        }

        // Cleans up the sticker data on disk. We want to do these deletions
        // after the transaction is complete so that other transactions aren't
        // blocked.
        transaction.addSyncCompletion {
            Task {
                do {
                    try OWSFileSystem.deleteFileIfExists(url: stickerDataUrl)
                } catch {
                    owsFailDebug("Error: \(error)")
                }
            }
        }

        // No need to post stickersOrPacksDidChange; caller will do that.
    }

    public func fetchInstalledSticker(stickerInfo: StickerInfo, transaction: DBReadTransaction) -> InstalledStickerRecord? {
        let uniqueId = InstalledStickerRecord.uniqueId(for: stickerInfo)
        return InstalledStickerRecord.anyFetch(uniqueId: uniqueId, transaction: transaction)
    }

    public func fetchInstalledSticker(
        packId: Data,
        stickerId: UInt32,
        transaction: DBReadTransaction,
    ) -> InstalledStickerRecord? {
        let uniqueId = StickerInfo.key(packId: packId, stickerId: stickerId)
        return InstalledStickerRecord.anyFetch(uniqueId: uniqueId, transaction: transaction)
    }

    public func installSticker(
        stickerInfo: StickerInfo,
        stickerData: Data,
        contentType: String?,
        emojiString: String?,
    ) async -> Bool {
        return await stickerInstallQueue.runWithoutTaskCancellationHandler(forKey: stickerInfo.asKey()) {
            let alreadyInstalled = db.read { tx in
                isStickerInstalled(stickerInfo: stickerInfo, transaction: tx)
            }

            guard !alreadyInstalled else {
                return false
            }

            let stickerLocalKey = AttachmentKey.generate()
            guard let stickerDataUrl = stickerDataUrl(stickerInfo: stickerInfo, contentType: contentType, verifyExists: false) else {
                owsFailDebug("Could not generate sticker data URL.")
                return false
            }

            let encryptionMetadata: EncryptionMetadata
            do {

                let (encryptedStickerData, metadata) = try Cryptography.encrypt(
                    stickerData,
                    attachmentKey: stickerLocalKey,
                    applyExtraPadding: false,
                )
                encryptionMetadata = metadata

                try encryptedStickerData.write(to: stickerDataUrl)
            } catch {
                owsFailDebug("Sticker file write failed: \(error)")
                return false
            }

            guard let plaintextLength = UInt32(exactly: encryptionMetadata.plaintextLength) else {
                owsFailDebug("Sticker plaintext data too large")
                return false
            }

            let installedSticker = InstalledStickerRecord(
                info: stickerInfo,
                contentType: contentType,
                emojiString: emojiString,
                localKey: stickerLocalKey.combinedKey,
                plaintextLength: plaintextLength,
            )

            return await db.awaitableWrite { transaction -> Bool in
                installedSticker.anyUpsert(transaction: transaction)

                // For every attachment referencing this sticker, we can now enqueue a "download"
                // that's really just a local file clone, from the newly installed sticker.
                let attachmentIds = attachmentStore.allAttachmentIdsForSticker(
                    stickerInfo,
                    tx: transaction,
                )
                attachmentIds.forEach { attachmentId in
                    attachmentDownloadStore.enqueueDownloadOfAttachment(
                        withId: attachmentId,
                        // source is irrelevant with localClone priority
                        source: .transitTier,
                        priority: .localClone,
                        tx: transaction,
                    )
                }
                addStickerToEmojiMap(installedSticker, tx: transaction)
                return true
            }
        }
    }

    private func tryToDownloadAndInstallSticker(
        stickerPack: StickerPackRecord,
        item: StickerPackItem,
        transaction: DBReadTransaction,
    ) -> Promise<Bool> {
        let stickerInfo: StickerInfo = item.stickerInfoWith(stickerPack: stickerPack)
        let emojiString = item.emojiString

        guard !self.isStickerInstalled(stickerInfo: stickerInfo, transaction: transaction) else {
            // Skipping redundant sticker install.
            return .value(false)
        }

        return firstly {
            tryToDownloadSticker(stickerInfo: stickerInfo)
        }.then(on: DispatchQueue.global()) { stickerData in
            Promise.wrapAsync {
                await self.installSticker(
                    stickerInfo: stickerInfo,
                    stickerData: stickerData,
                    contentType: item.contentType,
                    emojiString: emojiString,
                )
            }
        }
    }

    private struct StickerDownload {
        let promise: Promise<Data>
        let future: Future<Data>

        init() {
            let (promise, future) = Promise<Data>.pending()
            self.promise = promise
            self.future = future
        }
    }

    private let stickerDownloads = AtomicValue<[String: StickerDownload]>([:], lock: .init())
    private let stickerOperationQueue = ConcurrentTaskQueue(concurrentLimit: 4)

    public func tryToDownloadSticker(stickerInfo: StickerInfo) -> Promise<Data> {
        let (stickerDownload, shouldStartTask) = stickerDownloads.update {
            if let stickerDownload = $0[stickerInfo.asKey()] {
                return (stickerDownload, false)
            }
            let stickerDownload = StickerDownload()
            $0[stickerInfo.asKey()] = stickerDownload
            return (stickerDownload, true)
        }
        if shouldStartTask {
            Task { [stickerDownloads] in
                let result = await Result {
                    try await DownloadStickerOperation.run(stickerInfo: stickerInfo)
                }
                stickerDownloads.update { $0.removeValue(forKey: stickerInfo.asKey()) }
                switch result {
                case .success(let stickerMetadata):
                    stickerDownload.future.resolve(stickerMetadata)
                case .failure(let error):
                    stickerDownload.future.reject(error)
                }
            }
        }
        return stickerDownload.promise
    }

    // MARK: - Emoji

    static func allEmoji(in emojiString: String) -> LazyFilterSequence<LazySequence<String>.Elements> {
        return emojiString.lazy.filter { $0.unicodeScalars.containsOnlyEmoji() }
    }

    static func firstEmoji(in emojiString: String) -> String? {
        return allEmoji(in: emojiString).first.map(String.init)
    }

    private func addStickerToEmojiMap(_ installedSticker: InstalledStickerRecord, tx: DBWriteTransaction) {
        guard let emojiString = installedSticker.emojiString else {
            return
        }
        let stickerId = installedSticker.uniqueId
        for emoji in Self.allEmoji(in: emojiString) {
            emojiMapStore.prependToOrderedUniqueArray(key: String(emoji), value: stickerId, tx: tx)
        }
    }

    private func removeStickerFromEmojiMap(_ installedSticker: InstalledStickerRecord, tx: DBWriteTransaction) {
        guard let emojiString = installedSticker.emojiString else {
            return
        }
        let stickerId = installedSticker.uniqueId
        for emoji in Self.allEmoji(in: emojiString) {
            emojiMapStore.removeFromOrderedUniqueArray(key: String(emoji), value: stickerId, tx: tx)
        }
    }

    public static func suggestedStickerEmoji(chatBoxText: String) -> Character? {
        // We must have a Character, we must have no other Characters, and it must
        // contain only emoji.
        guard
            let firstCharacter = chatBoxText.first,
            chatBoxText.dropFirst().isEmpty,
            firstCharacter.unicodeScalars.containsOnlyEmoji()
        else {
            return nil
        }
        return firstCharacter
    }

    public func suggestedStickers(for emoji: Character, tx: DBReadTransaction) -> [InstalledStickerRecord] {
        let stickerIds = emojiMapStore.orderedUniqueArray(forKey: String(emoji), tx: tx)
        return stickerIds.compactMap { stickerId in
            guard let installedSticker = InstalledStickerRecord.anyFetch(uniqueId: stickerId, transaction: tx) else {
                owsFailDebug("Missing installed sticker.")
                return nil
            }
            return installedSticker
        }
    }

    // MARK: - Known Sticker Packs

    public struct DatedStickerPackInfo {
        public let timestamp: UInt64
        public let info: StickerPackInfo
    }

    public func knownStickerPacksFromMessages(transaction: DBReadTransaction) -> [DatedStickerPackInfo] {
        do {
            return attachmentStore
                .oldestStickerPackReferences(tx: transaction)
                .compactMap { stickerReferenceMetadata in
                    // Join to the message so we can get the sticker pack key.
                    guard
                        let interaction = interactionStore
                            .fetchInteraction(
                                rowId: stickerReferenceMetadata.messageRowId,
                                tx: transaction,
                            ),
                        let messageSticker = (interaction as? TSMessage)?.messageSticker
                    else {
                        owsFailDebug("Missing message for sticker")
                        return nil
                    }
                    return DatedStickerPackInfo(
                        timestamp: stickerReferenceMetadata.receivedAtTimestamp,
                        info: StickerPackInfo(
                            packId: messageSticker.packId,
                            packKey: messageSticker.packKey,
                        ),
                    )
                }
        }
    }

    public func mapDatedStickerPacks(stickerPacks: [StickerPackRecord]) -> [DatedStickerPackInfo] {
        return stickerPacks.map {
            DatedStickerPackInfo(timestamp: $0.dateCreated.ows_millisecondsSince1970, info: $0.info)
        }
    }

    private func tryToDownloadStickerPacks(
        stickerPacks: [StickerPackInfo],
        installMode: InstallMode,
    ) -> [Promise<Void>] {
        var stickerPacksToDownload = [StickerPackInfo]()
        db.read { transaction in
            for stickerPackInfo in stickerPacks {
                if !isStickerPackSaved(stickerPackInfo: stickerPackInfo, transaction: transaction) {
                    stickerPacksToDownload.append(stickerPackInfo)
                }
            }
        }

        return stickerPacksToDownload.map { stickerPackInfo -> Promise<Void> in
            tryToDownloadAndSaveStickerPack(
                stickerPackInfo: stickerPackInfo,
                installMode: installMode,
                wasLocallyInitiated: true,
            )
        }
    }

    // MARK: - Missing Packs

    // Track which sticker packs downloads have failed permanently.
    private var missingStickerPacks = Set<String>()

    public func markStickerPackAsMissing(stickerPackInfo: StickerPackInfo) {
        DispatchQueue.main.async {
            self.missingStickerPacks.insert(stickerPackInfo.asKey)
        }
    }

    public func isStickerPackMissing(stickerPackInfo: StickerPackInfo) -> Bool {
        AssertIsOnMainThread()

        return missingStickerPacks.contains(stickerPackInfo.asKey)
    }

    // MARK: - Recents

    private static var kRecentStickersKey: String { "recentStickers" }
    private static let kRecentStickersMaxCount: Int = 25

    public func stickerWasSent(_ stickerInfo: StickerInfo, transaction: DBWriteTransaction) {
        guard isStickerInstalled(stickerInfo: stickerInfo, transaction: transaction) else {
            return
        }
        store.prependToOrderedUniqueArray(
            key: Self.kRecentStickersKey,
            value: stickerInfo.asKey(),
            maxCount: Self.kRecentStickersMaxCount,
            tx: transaction,
        )
        NotificationCenter.default.postOnMainThread(name: Self.recentStickersDidChange, object: nil)
    }

    private func removeFromRecentStickers(
        _ stickerInfo: StickerInfo,
        transaction: DBWriteTransaction,
    ) {
        store.removeFromOrderedUniqueArray(key: Self.kRecentStickersKey, value: stickerInfo.asKey(), tx: transaction)
        NotificationCenter.default.postOnMainThread(name: Self.recentStickersDidChange, object: nil)
    }

    // Returned in descending order of recency.
    //
    // Only returns installed stickers.
    public func recentStickers(transaction: DBReadTransaction) -> [StickerInfo] {
        let keys = store.orderedUniqueArray(forKey: Self.kRecentStickersKey, tx: transaction)
        var result = [StickerInfo]()
        for key in keys {
            guard let installedSticker = InstalledStickerRecord.anyFetch(uniqueId: key, transaction: transaction) else {
                owsFailDebug("Couldn't fetch sticker")
                continue
            }
            guard nil != self.stickerDataUrl(forInstalledSticker: installedSticker, verifyExists: true) else {
                owsFailDebug("Missing sticker data for installed sticker.")
                continue
            }
            result.append(installedSticker.info)
        }
        return result
    }

    // MARK: - Misc.

    // URL might be a sticker or a sticker pack manifest.
    public class func decrypt(at url: URL, packKey: Data) throws -> Data {
        guard packKey.count == packKeyLength else {
            owsFailDebug("Invalid pack key length: \(packKey.count).")
            throw StickerError.invalidInput
        }
        let attachmentKey = failIfThrows {
            let stickerKeyLength = 64
            let stickerKey = try hkdf(outputLength: stickerKeyLength, inputKeyMaterial: packKey, salt: [], info: Data("Sticker Pack".utf8))
            return try AttachmentKey(combinedKey: stickerKey)
        }

        let plaintext = try Cryptography.decryptFile(
            at: url,
            metadata: DecryptionMetadata(key: attachmentKey),
        )
        return plaintext
    }

    private func ensureAllStickerDownloadsAsync(tx: DBReadTransaction) -> [Promise<Void>] {
        return allStickerPacks(transaction: tx).map { stickerPack -> Promise<Void> in
            ensureDownloads(forStickerPack: stickerPack, transaction: tx)
        }
    }

    public func ensureDownloadsAsync(forStickerPack stickerPack: StickerPackRecord) -> Promise<Void> {
        let (promise, future) = Promise<Void>.pending()
        DispatchQueue.global().async {
            self.db.read { transaction in
                _ = firstly {
                    self.ensureDownloads(forStickerPack: stickerPack, transaction: transaction)
                }.done {
                    future.resolve()
                }.catch { error in
                    future.reject(error)
                }
            }
        }
        return promise
    }

    @discardableResult
    private func ensureDownloads(forStickerPack stickerPack: StickerPackRecord, transaction: DBReadTransaction) -> Promise<Void> {
        // TODO: As an optimization, we could flag packs as "complete" if we know all
        // of their stickers are installed.

        // Install the covers for available sticker packs.
        let onlyInstallCover = !stickerPack.isInstalled
        return installStickerPackContents(stickerPack: stickerPack, transaction: transaction, onlyInstallCover: onlyInstallCover)
    }

    public func hasOrphanedData(tx: DBReadTransaction) -> Bool {
        let (packsToRemove, stickersToRemove) = fetchOrphanedPacksAndStickers(tx: tx)
        return !packsToRemove.isEmpty || !stickersToRemove.isEmpty
    }

    public func cleanUpOrphanedData(tx: DBWriteTransaction) {
        // We re-compute the orphaned packs within the write transaction. It's
        // possible that a new pack was being saved during the read transaction,
        // and it's possible that an orphaned pack is no longer orphaned. Most of
        // the time we don't expect to have any orphans, so the 2x performance
        // overhead shouldn't matter. If we don't have any orphans by the time we
        // reach this point, the code will do the correct thing (which is nothing).
        let (packsToRemove, stickersToRemove) = fetchOrphanedPacksAndStickers(tx: tx)

        for stickerPack in packsToRemove {
            owsFailDebug("Removing orphan pack")
            stickerPack.anyRemove(transaction: tx)
        }

        if !stickersToRemove.isEmpty {
            Logger.warn("Removing \(stickersToRemove.count) orphan stickers.")
        }
        for sticker in stickersToRemove {
            uninstallSticker(stickerInfo: sticker.info, transaction: tx)
        }
    }

    private func fetchOrphanedPacksAndStickers(tx: DBReadTransaction) -> ([StickerPackRecord], [InstalledStickerRecord]) {
        var stickerPacks = [String: StickerPackRecord]()
        var packsToRemove = [StickerPackRecord]()

        for stickerPack in StickerPackRecord.anyFetchAll(transaction: tx) {
            if stickerPack.isInstalled || Self.isDefaultStickerPack(packId: stickerPack.info.packId) {
                stickerPacks[stickerPack.info.asKey] = stickerPack
            } else {
                packsToRemove.append(stickerPack)
            }
        }

        var stickersToRemove = [InstalledStickerRecord]()
        InstalledStickerRecord.anyEnumerate(transaction: tx) { sticker, _ in
            let shouldKeepSticker: Bool = {
                guard let stickerPack = stickerPacks[sticker.info.packInfo.asKey] else {
                    return false
                }
                return stickerPack.isInstalled || stickerPack.coverInfo == sticker.info
            }()
            if !shouldKeepSticker {
                stickersToRemove.append(sticker)
            }
        }

        return (packsToRemove, stickersToRemove)
    }

    // MARK: - Sync Messages

    private func enqueueStickerSyncMessage(
        operationType: StickerPackOperationType,
        packs: [StickerPackInfo],
        transaction: DBWriteTransaction,
    ) {
        guard let registeredState = try? tsAccountManager.registeredState(tx: transaction) else {
            return
        }
        let thread = TSContactThread.getOrCreateThread(
            withContactAddress: registeredState.localIdentifiers.aciAddress,
            transaction: transaction,
        )
        let message = StickerPackSyncMessage(
            localThread: thread,
            packs: packs,
            operationType: operationType,
            tx: transaction,
        )
        // The sync message doesn't include the actual stickers on it as attachments.
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: message,
        )
        messageSenderJobQueue.add(message: preparedMessage, transaction: transaction)
    }

    public func syncAllInstalledPacks(transaction: DBWriteTransaction) {
        guard tsAccountManager.registrationState(tx: transaction).isRegistered else {
            return
        }

        let stickerPackInfos = installedStickerPacks(transaction: transaction).map { $0.info }
        guard stickerPackInfos.count > 0 else {
            return
        }

        enqueueStickerSyncMessage(
            operationType: .install,
            packs: stickerPackInfos,
            transaction: transaction,
        )
    }

    public func processIncomingStickerPackOperation(
        _ proto: SSKProtoSyncMessageStickerPackOperation,
        transaction: DBWriteTransaction,
    ) {
        let packID: Data = proto.packID
        let packKey: Data = proto.packKey
        guard let stickerPackInfo = StickerPackInfo.parse(packId: packID, packKey: packKey) else {
            owsFailDebug("Invalid pack info.")
            return
        }

        guard let type = proto.type else {
            owsFailDebug("Pack operation missing type.")
            return
        }
        switch type {
        case .install:
            _ = tryToDownloadAndSaveStickerPack(
                stickerPackInfo: stickerPackInfo,
                installMode: .install,
                wasLocallyInitiated: false,
            )
        case .remove:
            uninstallStickerPack(stickerPackInfo: stickerPackInfo, wasLocallyInitiated: false, transaction: transaction)
        @unknown default:
            owsFailDebug("Unknown type.")
            return
        }
    }

    // MARK: - StickerPack Download Task Queue

    private struct StickerPackDownloadTaskRecord: TaskRecord {
        struct ID: Hashable {
            let rowId: QueuedBackupStickerPackDownload.IDType
            let packId: Data
            let packKey: Data
        }

        let id: ID
    }

    private class StickerPackDownloadTaskRecordStore: TaskRecordStore {
        typealias Record = StickerPackDownloadTaskRecord

        private let store: BackupStickerPackDownloadStore
        init(store: BackupStickerPackDownloadStore) {
            self.store = store
        }

        func peek(count: UInt, tx: DBReadTransaction) -> [StickerPackDownloadTaskRecord] {
            return store.peek(count: count, tx: tx).map {
                return StickerPackDownloadTaskRecord(id: StickerPackDownloadTaskRecord.ID(
                    rowId: $0.id!,
                    packId: $0.packId,
                    packKey: $0.packKey,
                ))
            }
        }

        func removeRecord(recordId: StickerPackDownloadTaskRecord.ID, tx: DBWriteTransaction) {
            store.removeRecordFromQueue(recordId: recordId.rowId, tx: tx)
        }
    }

    private final class StickerPackDownloadTaskRunner: TaskRecordRunner {
        typealias Record = StickerPackDownloadTaskRecord
        typealias Store = StickerPackDownloadTaskRecordStore

        weak var stickerManager: StickerManager?
        let store: StickerPackDownloadTaskRecordStore
        let db: DB
        init(store: StickerPackDownloadTaskRecordStore, db: DB) {
            self.store = store
            self.db = db
        }

        func runTask(
            recordId: Record.ID,
            loader: TaskQueueLoader<StickerPackDownloadTaskRunner>,
        ) async -> TaskRecordResult {
            guard let stickerManager else {
                return .unretryableError(OWSGenericError("Missing sticker manager in StickerPackDownloadTaskRunner"))
            }
            let stickerPackInfo = StickerPackInfo(
                packId: recordId.packId,
                packKey: recordId.packKey,
            )
            do {
                let alreadyInstalled = db.read { tx in
                    stickerManager.isStickerPackInstalled(stickerPackInfo: stickerPackInfo, transaction: tx)
                }
                guard !alreadyInstalled else {
                    return .success
                }

                let stickerPack = try await stickerManager.tryToDownloadStickerPack(
                    stickerPackInfo: stickerPackInfo,
                ).awaitable()

                await db.awaitableWrite { tx in
                    stickerManager.upsertStickerPack(
                        stickerPack: stickerPack,
                        installMode: .installIfUnsaved,
                        wasLocallyInitiated: true,
                        transaction: tx,
                    )
                }
                return .success
            } catch {
                Logger.error("Failed to download sticker: \(error)")
                return .unretryableError(error)
            }
        }

        func didSucceed(recordId: Record.ID, tx: DBWriteTransaction) { }

        func didFail(
            recordId: Record.ID,
            error: any Error,
            isRetryable: Bool,
            tx: DBWriteTransaction,
        ) { }

        func didObsolete(recordId: Record.ID, tx: DBWriteTransaction) { }
    }
}

// MARK: -

// These methods are used to maintain a "string set":
// A set (no duplicates) of strings stored as a list.
// As a bonus, the set is stored in order of descending recency.
private extension KeyValueStore {
    func prependToOrderedUniqueArray(
        key: String,
        value: String,
        maxCount: Int? = nil,
        tx: DBWriteTransaction,
    ) {
        // Prepend value to ensure descending order of recency.
        var orderedArray = [value]
        if let storedValue = getStringArray(key, transaction: tx) {
            orderedArray += storedValue.filter { $0 != value }
        }
        if let maxCount {
            orderedArray = Array(orderedArray.prefix(maxCount))
        }
        setStringArray(orderedArray, key: key, transaction: tx)
    }

    func removeFromOrderedUniqueArray(key: String, value: String, tx: DBWriteTransaction) {
        var orderedArray = [String]()
        if let storedValue = getStringArray(key, transaction: tx) {
            guard storedValue.contains(value) else {
                // No work to do.
                return
            }
            orderedArray += storedValue.filter { $0 != value }
        }
        setStringArray(orderedArray, key: key, transaction: tx)
    }

    func orderedUniqueArray(forKey key: String, tx: DBReadTransaction) -> [String] {
        return getStringArray(key, transaction: tx) ?? []
    }
}
