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
@objc
public class StickerManager: NSObject {

    // MARK: - Constants

    @objc
    public static let packKeyLength: UInt = 32

    // MARK: - Notifications

    public static let packsDidChange = Notification.Name("packsDidChange")
    public static let stickersOrPacksDidChange = Notification.Name("stickersOrPacksDidChange")
    public static let recentStickersDidChange = Notification.Name("recentStickersDidChange")

    private static let packsDidChangeEvent: DebouncedEvent = DebouncedEvents.build(
        mode: .firstLast,
        maxFrequencySeconds: 0.5,
        onQueue: .asyncOnQueue(queue: .global()),
        notifyBlock: {
            NotificationCenter.default.postNotificationNameAsync(packsDidChange, object: nil)
            NotificationCenter.default.postNotificationNameAsync(stickersOrPacksDidChange, object: nil)
        }
    )

    private static let stickersDidChangeEvent: DebouncedEvent = DebouncedEvents.build(
        mode: .firstLast,
        maxFrequencySeconds: 0.5,
        onQueue: .asyncOnQueue(queue: .global()),
        notifyBlock: {
            NotificationCenter.default.postNotificationNameAsync(stickersOrPacksDidChange, object: nil)
        }
    )

    // MARK: - Properties

    public static let store = KeyValueStore(collection: "recentStickers")
    public static let emojiMapStore = KeyValueStore(collection: "emojiMap")

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

    // MARK: - Initializers

    init(
        appReadiness: AppReadiness,
        dateProvider: @escaping DateProvider
    ) {

        // Task queue to install any sticker packs restored from a backup
        self.queueLoader = TaskQueueLoader(
            maxConcurrentTasks: 4,
            dateProvider: dateProvider,
            db: DependenciesBridge.shared.db,
            runner: StickerPackDownloadTaskRunner(
                store: StickerPackDownloadTaskRecordStore(
                    store: BackupStickerPackDownloadStoreImpl()
                )
            )
        )

        super.init()

        // Resume sticker and sticker pack downloads when app is ready.
        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            if DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered {
                Task {
                    // This will return once all restored sticker packs have been downloaded
                    try await self.queueLoader.loadAndRunTasks()

                    // Refresh contents after pending downloads complete
                    StickerManager.refreshContents()
                }
            }
        }
    }

    // Attempt to download any sticker packs restored via backup.
    public static func downloadPendingSickerPacks() async throws {
        try await SSKEnvironment.shared.stickerManagerRef.queueLoader.loadAndRunTasks()
    }

    // The sticker manager is responsible for downloading more than one kind
    // of content; those downloads can fail.  Therefore the sticker manager
    // retries those downloads, sometimes in response to user activity.
    public class func refreshContents() {
        // Try to download the manifests for "default" sticker packs.
        tryToDownloadDefaultStickerPacks()

        // Try to download the stickers for "installed" sticker packs.
        ensureAllStickerDownloadsAsync()
    }

    // MARK: - Paths

    private class func ensureCacheDirUrl() -> URL {
        var url = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
        url.appendPathComponent("StickerManager")
        OWSFileSystem.ensureDirectoryExists(url.path)
        return url
    }
    private static let _cacheDirUrl = {
        return ensureCacheDirUrl()
    }()
    public class func cacheDirUrl() -> URL {
        // In test we need to compute the sticker cache dir every time we use it,
        // since it will change from test to test.
        //
        // In production, we should only ensure it once because ensuring:
        //
        // * Makes sure it exists on disk which is expensive.
        // * Makes sure it is protected on disk which is expensive.
        // * Does some logging which really clutters up the logs once you have
        //   a bunch of stickers installed.
        if CurrentAppContext().isRunningTests {
            return ensureCacheDirUrl()
        } else {
            return _cacheDirUrl
        }
    }

    // MARK: - Sticker Packs

    public class func allStickerPacks() -> [StickerPack] {
        var result = [StickerPack]()
        SSKEnvironment.shared.databaseStorageRef.read { (transaction) in
            result += allStickerPacks(transaction: transaction)
        }
        return result
    }

    public class func allStickerPacks(transaction: SDSAnyReadTransaction) -> [StickerPack] {
        return StickerPack.anyFetchAll(transaction: transaction)
    }

    public class func installedStickerPacks(transaction: SDSAnyReadTransaction) -> [StickerPack] {
        return allStickerPacks(transaction: transaction).filter {
            $0.isInstalled
        }
    }

    public class func availableStickerPacks(transaction: SDSAnyReadTransaction) -> [StickerPack] {
        return allStickerPacks(transaction: transaction).filter {
            !$0.isInstalled
        }
    }

    public class func isStickerPackSaved(stickerPackInfo: StickerPackInfo) -> Bool {
        return SSKEnvironment.shared.databaseStorageRef.read { (transaction) in
            return isStickerPackSaved(stickerPackInfo: stickerPackInfo, transaction: transaction)
        }
    }

    public class func isStickerPackSaved(stickerPackInfo: StickerPackInfo, transaction: SDSAnyReadTransaction) -> Bool {
        return nil != fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction)
    }

    public class func uninstallStickerPack(
        stickerPackInfo: StickerPackInfo,
        wasLocallyInitiated: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        uninstallStickerPack(
            stickerPackInfo: stickerPackInfo,
            uninstallEverything: false,
            wasLocallyInitiated: wasLocallyInitiated,
            transaction: transaction
        )
    }

    private class func uninstallStickerPack(
        stickerPackInfo: StickerPackInfo,
        uninstallEverything: Bool,
        wasLocallyInitiated: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        guard let stickerPack = fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction) else {
            Logger.info("Skipping uninstall; not saved or installed.")
            return
        }

        let isDefaultStickerPack = DefaultStickerPack.isDefaultStickerPack(packId: stickerPackInfo.packId)
        let shouldRemove = uninstallEverything || !isDefaultStickerPack

        if shouldRemove {
            uninstallSticker(stickerInfo: stickerPack.coverInfo, transaction: transaction)

            for stickerInfo in stickerPack.stickerInfos {
                if stickerInfo == stickerPack.coverInfo {
                    // Don't uninstall the cover for saved packs.
                    continue
                }
                uninstallSticker(stickerInfo: stickerInfo, transaction: transaction)
            }

            stickerPack.anyRemove(transaction: transaction)
        } else {
            stickerPack.update(withIsInstalled: false, transaction: transaction)
        }

        if wasLocallyInitiated {
            enqueueStickerSyncMessage(
                operationType: .remove,
                packs: [stickerPackInfo],
                transaction: transaction
            )
        }

        transaction.addAsyncCompletionOffMain {
            packsDidChangeEvent.requestNotify()
        }
    }

    public class func installStickerPack(
        stickerPack: StickerPack,
        wasLocallyInitiated: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        upsertStickerPack(
            stickerPack: stickerPack,
            installMode: .install,
            wasLocallyInitiated: wasLocallyInitiated,
            transaction: transaction
        )
    }

    public class func fetchStickerPack(stickerPackInfo: StickerPackInfo) -> StickerPack? {
        return SSKEnvironment.shared.databaseStorageRef.read { (transaction) in
            return fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction)
        }
    }

    public class func fetchStickerPack(stickerPackInfo: StickerPackInfo, transaction: SDSAnyReadTransaction) -> StickerPack? {
        let uniqueId = StickerPack.uniqueId(for: stickerPackInfo)
        return StickerPack.anyFetch(uniqueId: uniqueId, transaction: transaction)
    }

    private class func tryToDownloadAndSaveStickerPack(
        stickerPackInfo: StickerPackInfo,
        installMode: InstallMode,
        wasLocallyInitiated: Bool
    ) {
        tryToDownloadStickerPack(stickerPackInfo: stickerPackInfo).done(on: DispatchQueue.global()) { (stickerPack) in
            self.upsertStickerPack(
                stickerPack: stickerPack,
                installMode: installMode,
                wasLocallyInitiated: wasLocallyInitiated
            )
        }.cauterize()
    }

    private let packOperationQueue = ConcurrentTaskQueue(concurrentLimit: 3)

    private func tryToDownloadStickerPack(stickerPackInfo: StickerPackInfo) -> Promise<StickerPack> {
        return Promise.wrapAsync { [packOperationQueue] in
            return try await packOperationQueue.run {
                return try await DownloadStickerPackOperation.run(stickerPackInfo: stickerPackInfo)
            }
        }
    }

    // This method is public so that we can download "transient" (uninstalled) sticker packs.
    public class func tryToDownloadStickerPack(stickerPackInfo: StickerPackInfo) -> Promise<StickerPack> {
        return SSKEnvironment.shared.stickerManagerRef.tryToDownloadStickerPack(stickerPackInfo: stickerPackInfo)
    }

    private class func upsertStickerPack(
        stickerPack: StickerPack,
        installMode: InstallMode,
        wasLocallyInitiated: Bool
    ) {
        SSKEnvironment.shared.databaseStorageRef.write { (transaction) in
            upsertStickerPack(
                stickerPack: stickerPack,
                installMode: installMode,
                wasLocallyInitiated: wasLocallyInitiated,
                transaction: transaction
            )
        }
    }

    private class func upsertStickerPack(
        stickerPack stickerPackParam: StickerPack,
        installMode: InstallMode,
        wasLocallyInitiated: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        // If we re-insert a sticker pack, make sure that it
        // has a new row id.
        let stickerPack = stickerPackParam.copy() as! StickerPack
        stickerPack.clearRowId()

        let oldCopy = fetchStickerPack(stickerPackInfo: stickerPack.info, transaction: transaction)
        let wasSaved = oldCopy != nil

        // Preserve old mutable state.
        if let oldCopy = oldCopy {
            stickerPack.update(withIsInstalled: oldCopy.isInstalled, transaction: transaction)
        } else {
            stickerPack.anyInsert(transaction: transaction)
        }

        if stickerPack.isInstalled, wasLocallyInitiated {
            enqueueStickerSyncMessage(
                operationType: .install,
                packs: [stickerPack.info],
                transaction: transaction
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
                    transaction: transaction
                )
            case .installIfUnsaved:
                if !wasSaved {
                    promise = self.markSavedStickerPackAsInstalled(
                        stickerPack: stickerPack,
                        wasLocallyInitiated: wasLocallyInitiated,
                        transaction: transaction
                    )
                } else {
                    promise = .value(())
                }
            }
        }

        transaction.addAsyncCompletionOffMain {
            _ = promise.ensure {
                packsDidChangeEvent.requestNotify()
            }
        }
    }

    private class func markSavedStickerPackAsInstalled(
        stickerPack: StickerPack,
        wasLocallyInitiated: Bool,
        transaction: SDSAnyWriteTransaction
    ) -> Promise<Void> {
        if stickerPack.isInstalled {
            return .value(())
        }

        stickerPack.update(withIsInstalled: true, transaction: transaction)

        let promise = installStickerPackContents(stickerPack: stickerPack, transaction: transaction)

        if wasLocallyInitiated {
            enqueueStickerSyncMessage(
                operationType: .install,
                packs: [stickerPack.info],
                transaction: transaction
            )
        }
        return promise
    }

    private class func installStickerPackContents(
        stickerPack: StickerPack,
        transaction: SDSAnyReadTransaction,
        onlyInstallCover: Bool = false
    ) -> Promise<Void> {
        // Note: It's safe to kick off downloads of stickers that are already installed.
        var fetches = [Promise<Void>]()
        var needsNotify = false

        // The cover.
        let coverFetch = firstly {
            tryToDownloadAndInstallSticker(
                stickerPack: stickerPack,
                item: stickerPack.cover,
                transaction: transaction
            )
        }.done { (shouldNotify: Bool) in
            if shouldNotify {
                stickersDidChangeEvent.requestNotify()
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
                        transaction: transaction
                    )
                }.done { shouldNotify in
                    if shouldNotify, coverFetch.isSealed {
                        // We should only notify for changes once we've fetched the cover
                        // Some views will assume that an installed pack always has a cover
                        // and faildebug otherwise
                        stickersDidChangeEvent.requestNotify()
                        needsNotify = false
                    } else if shouldNotify {
                        needsNotify = true
                    }
                }
            )
        }
        return Promise.when(fulfilled: fetches).ensure {
            if needsNotify {
                stickersDidChangeEvent.requestNotify()
            }
        }
    }

    private class func tryToDownloadDefaultStickerPacks() {
        DispatchQueue.global().async {
            self.tryToDownloadStickerPacks(
                stickerPacks: DefaultStickerPack.packsToAutoInstall,
                installMode: .installIfUnsaved
            )
            self.tryToDownloadStickerPacks(
                stickerPacks: DefaultStickerPack.packsToNotAutoInstall,
                installMode: .doNotInstall
            )
        }
    }

    public class func installedStickers(
        forStickerPack stickerPack: StickerPack,
        verifyExists: Bool
    ) -> [StickerInfo] {
        return SSKEnvironment.shared.databaseStorageRef.read { (transaction) in
            return self.installedStickers(
                forStickerPack: stickerPack,
                verifyExists: verifyExists,
                transaction: transaction
            )
        }
    }

    public class func installedStickers(
        forStickerPack stickerPack: StickerPack,
        verifyExists: Bool,
        transaction: SDSAnyReadTransaction
    ) -> [StickerInfo] {
        var result = [StickerInfo]()
        for stickerInfo in stickerPack.stickerInfos {
            let uniqueId = InstalledSticker.uniqueId(for: stickerInfo)
            guard let installedSticker = InstalledSticker.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
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

    public class func isStickerPackInstalled(stickerPackInfo: StickerPackInfo) -> Bool {
        return SSKEnvironment.shared.databaseStorageRef.read { (transaction) in
            return isStickerPackInstalled(stickerPackInfo: stickerPackInfo, transaction: transaction)
        }
    }

    public class func isStickerPackInstalled(stickerPackInfo: StickerPackInfo, transaction: SDSAnyReadTransaction) -> Bool {
        guard let pack = fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction) else {
            return false
        }
        return pack.isInstalled
    }

    // MARK: - Stickers

    public static func stickerType(forContentType contentType: String?) -> StickerType {
        return StickerType.stickerType(forContentType: contentType)
    }

    public class func installedStickerMetadataWithSneakyTransaction(stickerInfo: StickerInfo) -> (any StickerMetadata)? {
        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return self.installedStickerMetadata(stickerInfo: stickerInfo, transaction: transaction)
        }
    }

    public class func installedStickerMetadata(
        stickerInfo: StickerInfo,
        transaction: SDSAnyReadTransaction
    ) -> (any StickerMetadata)? {
        let uniqueId = InstalledSticker.uniqueId(for: stickerInfo)
        guard let installedSticker = InstalledSticker.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
            return nil
        }
        return installedStickerMetadata(installedSticker: installedSticker, transaction: transaction)
    }

    public class func installedStickerMetadata(
        installedSticker: InstalledSticker,
        transaction: SDSAnyReadTransaction
    ) -> (any StickerMetadata)? {
        let stickerInfo = installedSticker.info
        let stickerType = StickerType.stickerType(forContentType: installedSticker.contentType)
        guard let stickerDataUrl = self.stickerDataUrl(stickerInfo: stickerInfo, stickerType: stickerType, verifyExists: true) else {
            return nil
        }
        return DecryptedStickerMetadata(
            stickerInfo: stickerInfo,
            stickerType: stickerType,
            stickerDataUrl: stickerDataUrl,
            emojiString: installedSticker.emojiString
        )
    }

    public class func stickerDataUrlWithSneakyTransaction(stickerInfo: StickerInfo, verifyExists: Bool) -> URL? {
        guard let installedSticker = fetchInstalledStickerWithSneakyTransaction(stickerInfo: stickerInfo) else {
            return nil
        }
        return self.stickerDataUrl(forInstalledSticker: installedSticker, verifyExists: verifyExists)
    }

    private class func stickerDataUrl(stickerInfo: StickerInfo, contentType: String?, verifyExists: Bool) -> URL? {
        let stickerType = StickerType.stickerType(forContentType: contentType)
        return stickerDataUrl(stickerInfo: stickerInfo, stickerType: stickerType, verifyExists: verifyExists)
    }

    public class func stickerDataUrl(forInstalledSticker installedSticker: InstalledSticker, verifyExists: Bool) -> URL? {
        let stickerInfo = installedSticker.info
        let stickerType = StickerType.stickerType(forContentType: installedSticker.contentType)
        return stickerDataUrl(stickerInfo: stickerInfo, stickerType: stickerType, verifyExists: verifyExists)
    }

    private class func stickerDataUrl(stickerInfo: StickerInfo, stickerType: StickerType, verifyExists: Bool) -> URL? {
        let uniqueId = InstalledSticker.uniqueId(for: stickerInfo)
        var url = cacheDirUrl()
        // Not all stickers are .webp.
        url.appendPathComponent("\(uniqueId).\(stickerType.fileExtension)")
        if verifyExists && !OWSFileSystem.fileOrFolderExists(url: url) {
            return nil
        }
        return url
    }

    public class func filePathsForAllInstalledStickers(transaction: SDSAnyReadTransaction) -> [String] {
        var filePaths = [String]()
        InstalledSticker.anyEnumerate(transaction: transaction) { (installedSticker, _) in
            if let stickerDataUrl = stickerDataUrl(forInstalledSticker: installedSticker, verifyExists: false) {
                filePaths.append(stickerDataUrl.path)
            }
        }
        return filePaths
    }

    public class func isStickerInstalled(stickerInfo: StickerInfo) -> Bool {
        return SSKEnvironment.shared.databaseStorageRef.read { (transaction) in
            return isStickerInstalled(stickerInfo: stickerInfo, transaction: transaction)
        }
    }

    public class func isStickerInstalled(stickerInfo: StickerInfo, transaction: SDSAnyReadTransaction) -> Bool {
        let uniqueId = InstalledSticker.uniqueId(for: stickerInfo)
        // We use anyFetch(...) instead of anyExists(...) to
        // leverage the model cache.
        return InstalledSticker.anyFetch(uniqueId: uniqueId, transaction: transaction) != nil
    }

    internal typealias CleanupCompletion = () -> Void

    internal class func uninstallSticker(stickerInfo: StickerInfo, transaction: SDSAnyWriteTransaction) {
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
        transaction.addAsyncCompletion(on: DispatchQueue.sharedUtility) {
            do {
                try OWSFileSystem.deleteFileIfExists(url: stickerDataUrl)
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }

        // No need to post stickersOrPacksDidChange; caller will do that.
    }

    public class func fetchInstalledStickerWithSneakyTransaction(stickerInfo: StickerInfo) -> InstalledSticker? {
        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return self.fetchInstalledSticker(stickerInfo: stickerInfo, transaction: transaction)
        }
    }

    public class func fetchInstalledSticker(stickerInfo: StickerInfo, transaction: SDSAnyReadTransaction) -> InstalledSticker? {
        let uniqueId = InstalledSticker.uniqueId(for: stickerInfo)
        return InstalledSticker.anyFetch(uniqueId: uniqueId, transaction: transaction)
    }

    public class func fetchInstalledSticker(
        packId: Data,
        stickerId: UInt32,
        transaction: SDSAnyReadTransaction
    ) -> InstalledSticker? {
        let uniqueId = StickerInfo.key(withPackId: packId, stickerId: stickerId)
        return InstalledSticker.anyFetch(uniqueId: uniqueId, transaction: transaction)
    }

    public class func installSticker(
        stickerInfo: StickerInfo,
        stickerUrl stickerTemporaryUrl: URL,
        contentType: String?,
        emojiString: String?
    ) -> Bool {
        guard nil == fetchInstalledStickerWithSneakyTransaction(stickerInfo: stickerInfo) else {
            // Sticker already installed, skip.
            return false
        }

        let installedSticker = InstalledSticker(
            info: stickerInfo,
            contentType: contentType,
            emojiString: emojiString
        )

        guard let stickerDataUrl = self.stickerDataUrl(forInstalledSticker: installedSticker, verifyExists: false) else {
            owsFailDebug("Could not generate sticker data URL.")
            return false
        }

        do {
            // We copy the file rather than move it as some transient data sources
            // could be trying to access the temp file at this point. Stickers are
            // generally very small so this shouldn't be a big perf hit.
            try OWSFileSystem.deleteFileIfExists(url: stickerDataUrl)
            try FileManager.default.copyItem(at: stickerTemporaryUrl, to: stickerDataUrl)
        } catch CocoaError.fileWriteFileExists {
            // We hit a race condition and somebody else put the file here after we
            // deleted it. It's fine to continue...
        } catch let error {
            owsFailDebug("File write failed: \(error)")
            return false
        }

        return SSKEnvironment.shared.databaseStorageRef.write { (transaction) -> Bool in
            guard nil == fetchInstalledSticker(stickerInfo: stickerInfo, transaction: transaction) else {
                // RACE: sticker has already been installed between now and when we last checked.
                //
                // Initially we check for a stickers presence with a read transaction, to avoid opening
                // an unnecessary write transaction. However, it's possible a race has occurred and the
                // sticker has since been installed, in which case there's nothing more for us to do.
                return false
            }

            installedSticker.anyInsert(transaction: transaction)

            self.addStickerToEmojiMap(installedSticker, tx: transaction)
            return true
        }
    }

    private class func tryToDownloadAndInstallSticker(
        stickerPack: StickerPack,
        item: StickerPackItem,
        transaction: SDSAnyReadTransaction
    ) -> Promise<Bool> {
        let stickerInfo: StickerInfo = item.stickerInfo(with: stickerPack)
        let emojiString = item.emojiString

        guard !self.isStickerInstalled(stickerInfo: stickerInfo, transaction: transaction) else {
            // Skipping redundant sticker install.
            return .value(false)
        }

        return firstly {
            tryToDownloadSticker(stickerPack: stickerPack, stickerInfo: stickerInfo)
        }.map(on: DispatchQueue.global()) { stickerUrl in
            self.installSticker(
                stickerInfo: stickerInfo,
                stickerUrl: stickerUrl,
                contentType: item.contentType,
                emojiString: emojiString
            )
        }
    }

    private struct StickerDownload {
        let promise: Promise<URL>
        let future: Future<URL>

        init() {
            let (promise, future) = Promise<URL>.pending()
            self.promise = promise
            self.future = future
        }
    }
    private let stickerDownloads = AtomicValue<[String: StickerDownload]>([:], lock: .init())
    private let stickerOperationQueue = ConcurrentTaskQueue(concurrentLimit: 4)

    private func tryToDownloadSticker(stickerPack: StickerPack, stickerInfo: StickerInfo) -> Promise<URL> {
        if let stickerUrl = DownloadStickerOperation.cachedUrl(for: stickerInfo) {
            return Promise.value(stickerUrl)
        }
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
                case .success(let url):
                    stickerDownload.future.resolve(url)
                case .failure(let error):
                    stickerDownload.future.reject(error)
                }
            }
        }
        return stickerDownload.promise
    }

    // This method is public so that we can download "transient" (uninstalled) stickers.
    public class func tryToDownloadSticker(stickerPack: StickerPack, stickerInfo: StickerInfo) -> Promise<URL> {
        SSKEnvironment.shared.stickerManagerRef.tryToDownloadSticker(stickerPack: stickerPack, stickerInfo: stickerInfo)
    }

    // MARK: - Emoji

    static func allEmoji(in emojiString: String) -> LazyFilterSequence<LazySequence<String>.Elements> {
        return emojiString.lazy.filter { $0.unicodeScalars.containsOnlyEmoji() }
    }

    static func firstEmoji(in emojiString: String) -> String? {
        return allEmoji(in: emojiString).first.map(String.init)
    }

    private class func addStickerToEmojiMap(_ installedSticker: InstalledSticker, tx: SDSAnyWriteTransaction) {
        guard let emojiString = installedSticker.emojiString else {
            return
        }
        let stickerId = installedSticker.uniqueId
        for emoji in allEmoji(in: emojiString) {
            emojiMapStore.prependToOrderedUniqueArray(key: String(emoji), value: stickerId, tx: tx)
        }
    }

    private class func removeStickerFromEmojiMap(_ installedSticker: InstalledSticker, tx: SDSAnyWriteTransaction) {
        guard let emojiString = installedSticker.emojiString else {
            return
        }
        let stickerId = installedSticker.uniqueId
        for emoji in allEmoji(in: emojiString) {
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

    public class func suggestedStickers(for emoji: Character, tx: SDSAnyReadTransaction) -> [InstalledSticker] {
        let stickerIds = emojiMapStore.orderedUniqueArray(forKey: String(emoji), tx: tx)
        return stickerIds.compactMap { (stickerId) in
            guard let installedSticker = InstalledSticker.anyFetch(uniqueId: stickerId, transaction: tx) else {
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

    public class func knownStickerPacksFromMessages(transaction: SDSAnyReadTransaction) -> [DatedStickerPackInfo] {
        do {
            return try DependenciesBridge.shared.attachmentStore
                .oldestStickerPackReferences(tx: transaction.asV2Read)
                .compactMap { stickerReferenceMetadata in
                    // Join to the message so we can get the sticker pack key.
                    guard
                        let interaction = DependenciesBridge.shared.interactionStore
                            .fetchInteraction(
                                rowId: stickerReferenceMetadata.messageRowId,
                                tx: transaction.asV2Read
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
                            packKey: messageSticker.packKey
                        )
                    )
                }
        } catch {
            owsFailDebug("Failed fetching sticker attachments \(error)")
            return []
        }
    }

    private class func tryToDownloadStickerPacks(stickerPacks: [StickerPackInfo], installMode: InstallMode) {
        var stickerPacksToDownload = [StickerPackInfo]()
        SSKEnvironment.shared.databaseStorageRef.read { (transaction) in
            for stickerPackInfo in stickerPacks {
                if !StickerManager.isStickerPackSaved(stickerPackInfo: stickerPackInfo, transaction: transaction) {
                    stickerPacksToDownload.append(stickerPackInfo)
                }
            }
        }

        for stickerPackInfo in stickerPacksToDownload {
            StickerManager.tryToDownloadAndSaveStickerPack(
                stickerPackInfo: stickerPackInfo,
                installMode: installMode,
                wasLocallyInitiated: true
            )
        }
    }

    // MARK: - Missing Packs

    // Track which sticker packs downloads have failed permanently.
    private static var missingStickerPacks = Set<String>()

    public class func markStickerPackAsMissing(stickerPackInfo: StickerPackInfo) {
        DispatchQueue.main.async {
            self.missingStickerPacks.insert(stickerPackInfo.asKey)
        }
    }

    public class func isStickerPackMissing(stickerPackInfo: StickerPackInfo) -> Bool {
        AssertIsOnMainThread()

        return missingStickerPacks.contains(stickerPackInfo.asKey)
    }

    // MARK: - Recents

    private static var kRecentStickersKey: String { "recentStickers" }
    private static let kRecentStickersMaxCount: Int = 25

    public class func stickerWasSent(_ stickerInfo: StickerInfo, transaction: SDSAnyWriteTransaction) {
        guard isStickerInstalled(stickerInfo: stickerInfo, transaction: transaction) else {
            return
        }
        store.prependToOrderedUniqueArray(
            key: kRecentStickersKey,
            value: stickerInfo.asKey(),
            maxCount: kRecentStickersMaxCount,
            tx: transaction
        )
        NotificationCenter.default.postNotificationNameAsync(recentStickersDidChange, object: nil)
    }

    private class func removeFromRecentStickers(
        _ stickerInfo: StickerInfo,
        transaction: SDSAnyWriteTransaction
    ) {
        store.removeFromOrderedUniqueArray(key: kRecentStickersKey, value: stickerInfo.asKey(), tx: transaction)
        NotificationCenter.default.postNotificationNameAsync(recentStickersDidChange, object: nil)
    }

    // Returned in descending order of recency.
    //
    // Only returns installed stickers.
    public class func recentStickers() -> [StickerInfo] {
        var result = [StickerInfo]()
        SSKEnvironment.shared.databaseStorageRef.read { (transaction) in
            result = self.recentStickers(transaction: transaction)
        }
        return result
    }

    // Returned in descending order of recency.
    //
    // Only returns installed stickers.
    private class func recentStickers(transaction: SDSAnyReadTransaction) -> [StickerInfo] {
        let keys = store.orderedUniqueArray(forKey: kRecentStickersKey, tx: transaction)
        var result = [StickerInfo]()
        for key in keys {
            guard let installedSticker = InstalledSticker.anyFetch(uniqueId: key, transaction: transaction) else {
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
    public class func decrypt(at url: URL, packKey: Data) throws -> URL {
        guard packKey.count == packKeyLength else {
            owsFailDebug("Invalid pack key length: \(packKey.count).")
            throw StickerError.invalidInput
        }
        let stickerKeyInfo = "Sticker Pack"
        let stickerKeyLength = 64
        let stickerKey = try stickerKeyInfo.utf8.withContiguousStorageIfAvailable {
            try hkdf(outputLength: stickerKeyLength, inputKeyMaterial: packKey, salt: [], info: $0)
        }!

        let temporaryDecryptedFile = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
        try Cryptography.decryptFile(at: url, metadata: .init(key: Data(stickerKey)), output: temporaryDecryptedFile)
        return temporaryDecryptedFile
    }

    private class func ensureAllStickerDownloadsAsync() {
        DispatchQueue.global().async {
            SSKEnvironment.shared.databaseStorageRef.read { (transaction) in
                for stickerPack in self.allStickerPacks(transaction: transaction) {
                    ensureDownloads(forStickerPack: stickerPack, transaction: transaction)
                }
            }
        }
    }

    public class func ensureDownloadsAsync(forStickerPack stickerPack: StickerPack) -> Promise<Void> {
        let (promise, future) = Promise<Void>.pending()
        DispatchQueue.global().async {
            SSKEnvironment.shared.databaseStorageRef.read { (transaction) in
                firstly {
                    ensureDownloads(forStickerPack: stickerPack, transaction: transaction)
                }.done {
                    future.resolve()
                }.catch { (error) in
                    future.reject(error)
                }
            }
        }
        return promise
    }

    @discardableResult
    private class func ensureDownloads(forStickerPack stickerPack: StickerPack, transaction: SDSAnyReadTransaction) -> Promise<Void> {
        // TODO: As an optimization, we could flag packs as "complete" if we know all
        // of their stickers are installed.

        // Install the covers for available sticker packs.
        let onlyInstallCover = !stickerPack.isInstalled
        return installStickerPackContents(stickerPack: stickerPack, transaction: transaction, onlyInstallCover: onlyInstallCover)
    }

    public static func hasOrphanedData(tx: SDSAnyReadTransaction) -> Bool {
        let (packsToRemove, stickersToRemove) = fetchOrphanedPacksAndStickers(tx: tx)
        return !packsToRemove.isEmpty || !stickersToRemove.isEmpty
    }

    public static func cleanUpOrphanedData(tx: SDSAnyWriteTransaction) {
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
            self.uninstallSticker(stickerInfo: sticker.info, transaction: tx)
        }
    }

    private static func fetchOrphanedPacksAndStickers(tx: SDSAnyReadTransaction) -> ([StickerPack], [InstalledSticker]) {
        var stickerPacks = [String: StickerPack]()
        var packsToRemove = [StickerPack]()

        for stickerPack in StickerPack.anyFetchAll(transaction: tx) {
            if stickerPack.isInstalled || self.isDefaultStickerPack(packId: stickerPack.info.packId) {
                stickerPacks[stickerPack.info.asKey] = stickerPack
            } else {
                packsToRemove.append(stickerPack)
            }
        }

        var stickersToRemove = [InstalledSticker]()
        InstalledSticker.anyEnumerate(transaction: tx) { (sticker, _) in
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

    private class func enqueueStickerSyncMessage(
        operationType: StickerPackOperationType,
        packs: [StickerPackInfo],
        transaction: SDSAnyWriteTransaction
    ) {
        guard DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction.asV2Read).isRegistered else {
            return
        }
        guard let thread = TSContactThread.getOrCreateLocalThread(transaction: transaction) else {
            owsFailDebug("Missing thread.")
            return
        }
        let message = OWSStickerPackSyncMessage(
            thread: thread,
            packs: packs,
            operationType: operationType,
            transaction: transaction
        )
        // The sync message doesn't include the actual stickers on it as attachments.
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: message
        )
        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)
    }

    public class func syncAllInstalledPacks(transaction: SDSAnyWriteTransaction) {
        guard DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction.asV2Read).isRegistered else {
            return
        }

        let stickerPackInfos = installedStickerPacks(transaction: transaction).map { $0.info }
        guard stickerPackInfos.count > 0 else {
            return
        }

        enqueueStickerSyncMessage(
            operationType: .install,
            packs: stickerPackInfos,
            transaction: transaction
        )
    }

    public class func processIncomingStickerPackOperation(
        _ proto: SSKProtoSyncMessageStickerPackOperation,
        transaction: SDSAnyWriteTransaction
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
            tryToDownloadAndSaveStickerPack(
                stickerPackInfo: stickerPackInfo,
                installMode: .install,
                wasLocallyInitiated: false
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
        let id: Int64
        let record: QueuedBackupStickerPackDownload
    }

    private class StickerPackDownloadTaskRecordStore: TaskRecordStore {
        typealias Record = StickerPackDownloadTaskRecord

        private let store: BackupStickerPackDownloadStore
        init(store: BackupStickerPackDownloadStore) {
            self.store = store
        }

        func peek(count: UInt, tx: DBReadTransaction) throws -> [StickerPackDownloadTaskRecord] {
            return try store.peek(count: count, tx: tx).map {
                return .init(id: $0.id!, record: $0)
            }
        }

        func removeRecord(_ record: StickerPackDownloadTaskRecord, tx: any DBWriteTransaction) throws {
            try store.removeRecordFromQueue(record: record.record, tx: tx)
        }
    }

    private final class StickerPackDownloadTaskRunner: TaskRecordRunner {
        typealias Record = StickerPackDownloadTaskRecord
        typealias Store = StickerPackDownloadTaskRecordStore

        let store: StickerPackDownloadTaskRecordStore
        init(store: StickerPackDownloadTaskRecordStore) {
            self.store = store
        }

        func runTask(record: Record, loader: TaskQueueLoader<StickerPackDownloadTaskRunner>) async -> TaskRecordResult {
            let stickerPackInfo = StickerPackInfo(packId: record.record.packId, packKey: record.record.packKey)
            do {
                guard !StickerManager.isStickerPackInstalled(stickerPackInfo: stickerPackInfo) else {
                    return .success
                }
                try await StickerManager.tryToDownloadStickerPack(
                    stickerPackInfo: stickerPackInfo
                ).done(on: DispatchQueue.global()) { stickerPack in
                    StickerManager.upsertStickerPack(
                        stickerPack: stickerPack,
                        installMode: .installIfUnsaved,
                        wasLocallyInitiated: true
                    )
                }.awaitable()
                return .success
            } catch {
                Logger.error("Failed to download sticker: \(error)")
                return .unretryableError(error)
            }
        }

        func didSucceed(record: Record, tx: any DBWriteTransaction) throws { }

        func didFail(record: Record, error: any Error, isRetryable: Bool, tx: any DBWriteTransaction) throws { }

        func didCancel(record: Record, tx: any DBWriteTransaction) throws { }
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
        tx: SDSAnyWriteTransaction
    ) {
        // Prepend value to ensure descending order of recency.
        var orderedArray = [value]
        if let storedValue = getStringArray(key, transaction: tx.asV2Read) {
            orderedArray += storedValue.filter { $0 != value }
        }
        if let maxCount {
            orderedArray = Array(orderedArray.prefix(maxCount))
        }
        setObject(orderedArray, key: key, transaction: tx.asV2Write)
    }

    func removeFromOrderedUniqueArray(key: String, value: String, tx: SDSAnyWriteTransaction) {
        var orderedArray = [String]()
        if let storedValue = getStringArray(key, transaction: tx.asV2Read) {
            guard storedValue.contains(value) else {
                // No work to do.
                return
            }
            orderedArray += storedValue.filter { $0 != value }
        }
        setObject(orderedArray, key: key, transaction: tx.asV2Write)
    }

    func orderedUniqueArray(forKey key: String, tx: SDSAnyReadTransaction) -> [String] {
        return getStringArray(key, transaction: tx.asV2Read) ?? []
    }
}
