//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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

    @objc
    public static let packsDidChange = Notification.Name("packsDidChange")
    @objc
    public static let stickersOrPacksDidChange = Notification.Name("stickersOrPacksDidChange")
    @objc
    public static let recentStickersDidChange = Notification.Name("recentStickersDidChange")

    private static var packsDidChangeEvent: DebouncedEvent {
        DebouncedEvents.build(mode: .firstLast,
                              maxFrequencySeconds: 0.5,
                              onQueue: .asyncOnQueue(queue: .global())) {
            NotificationCenter.default.postNotificationNameAsync(packsDidChange, object: nil)
            NotificationCenter.default.postNotificationNameAsync(stickersOrPacksDidChange, object: nil)
        }
    }

    private static var stickersDidChangeEvent: DebouncedEvent {
        DebouncedEvents.build(mode: .firstLast,
                              maxFrequencySeconds: 0.5,
                              onQueue: .asyncOnQueue(queue: .global())) {
            NotificationCenter.default.postNotificationNameAsync(stickersOrPacksDidChange, object: nil)
        }
    }

    // MARK: - Properties

    public static let store = SDSKeyValueStore(collection: "recentStickers")
    public static let emojiMapStore = SDSKeyValueStore(collection: "emojiMap")

    @objc
    public enum InstallMode: Int {
        case doNotInstall
        case install
        // For default packs that should be auto-installed,
        // we only want to install the first time we save them.
        // If a user subsequently uninstalls the pack, we want
        // to honor that.
        case installIfUnsaved
    }

    // MARK: - Initializers

    @objc
    public override init() {
        super.init()

        // Resume sticker and sticker pack downloads when app is ready.
        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            guard CurrentAppContext().isMainApp,
                  !CurrentAppContext().isRunningTests else {
                      return
                  }

            StickerManager.cleanupOrphans()

            if TSAccountManager.shared.isRegisteredAndReady {
                StickerManager.refreshContents()
            }
        }
    }

    // The sticker manager is responsible for downloading more than one kind
    // of content; those downloads can fail.  Therefore the sticker manager
    // retries those downloads, sometimes in response to user activity.
    @objc
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
    @objc
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

    @objc
    public class func allStickerPacks() -> [StickerPack] {
        var result = [StickerPack]()
        databaseStorage.read { (transaction) in
            result += allStickerPacks(transaction: transaction)
        }
        return result
    }

    @objc
    public class func allStickerPacks(transaction: SDSAnyReadTransaction) -> [StickerPack] {
        return StickerPack.anyFetchAll(transaction: transaction)
    }

    @objc
    public class func installedStickerPacks(transaction: SDSAnyReadTransaction) -> [StickerPack] {
        return allStickerPacks(transaction: transaction).filter {
            $0.isInstalled
        }
    }

    @objc
    public class func availableStickerPacks(transaction: SDSAnyReadTransaction) -> [StickerPack] {
        return allStickerPacks(transaction: transaction).filter {
            !$0.isInstalled
        }
    }

    @objc
    public class func isStickerPackSaved(stickerPackInfo: StickerPackInfo) -> Bool {
        var result = false
        databaseStorage.read { (transaction) in
            result = isStickerPackSaved(stickerPackInfo: stickerPackInfo,
                                        transaction: transaction)
        }
        return result
    }

    @objc
    public class func isStickerPackSaved(stickerPackInfo: StickerPackInfo,
                                         transaction: SDSAnyReadTransaction) -> Bool {
        return nil != fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction)
    }

    @objc
    public class func uninstallStickerPack(stickerPackInfo: StickerPackInfo,
                                           wasLocallyInitiated: Bool,
                                           transaction: SDSAnyWriteTransaction) {
        uninstallStickerPack(stickerPackInfo: stickerPackInfo,
                             uninstallEverything: false,
                             wasLocallyInitiated: wasLocallyInitiated,
                             transaction: transaction)
    }

    private class func uninstallStickerPack(stickerPackInfo: StickerPackInfo,
                                            uninstallEverything: Bool,
                                            wasLocallyInitiated: Bool,
                                            transaction: SDSAnyWriteTransaction) {

        guard let stickerPack = fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction) else {
            Logger.info("Skipping uninstall; not saved or installed.")
            return
        }

        Logger.verbose("Uninstalling sticker pack: \(stickerPackInfo).")

        let isDefaultStickerPack = DefaultStickerPack.isDefaultStickerPack(packId: stickerPackInfo.packId)
        let shouldRemove = uninstallEverything || !isDefaultStickerPack

        if shouldRemove {
            uninstallSticker(stickerInfo: stickerPack.coverInfo,
                             transaction: transaction)

            for stickerInfo in stickerPack.stickerInfos {
                if stickerInfo == stickerPack.coverInfo {
                    // Don't uninstall the cover for saved packs.
                    continue
                }
                uninstallSticker(stickerInfo: stickerInfo,
                                 transaction: transaction)
            }

            stickerPack.anyRemove(transaction: transaction)
        } else {
            stickerPack.update(withIsInstalled: false, transaction: transaction)
        }

        if wasLocallyInitiated {
            enqueueStickerSyncMessage(operationType: .remove,
                                      packs: [stickerPackInfo],
                                      transaction: transaction)
        }

        transaction.addAsyncCompletionOffMain {
            packsDidChangeEvent.requestNotify()
        }
    }

    @objc
    public class func installStickerPack(stickerPack: StickerPack,
                                         wasLocallyInitiated: Bool,
                                         transaction: SDSAnyWriteTransaction) {
        upsertStickerPack(stickerPack: stickerPack,
                          installMode: .install,
                          wasLocallyInitiated: wasLocallyInitiated,
                          transaction: transaction)
    }

    @objc
    public class func fetchStickerPack(stickerPackInfo: StickerPackInfo) -> StickerPack? {
        var result: StickerPack?
        databaseStorage.read { (transaction) in
            result = fetchStickerPack(stickerPackInfo: stickerPackInfo,
                                      transaction: transaction)
        }
        return result
    }

    @objc
    public class func fetchStickerPack(stickerPackInfo: StickerPackInfo,
                                       transaction: SDSAnyReadTransaction) -> StickerPack? {
        let uniqueId = StickerPack.uniqueId(for: stickerPackInfo)
        return StickerPack.anyFetch(uniqueId: uniqueId, transaction: transaction)
    }

    private class func tryToDownloadAndSaveStickerPack(stickerPackInfo: StickerPackInfo,
                                                       installMode: InstallMode,
                                                       wasLocallyInitiated: Bool) {
        tryToDownloadStickerPack(stickerPackInfo: stickerPackInfo)
            .done(on: DispatchQueue.global()) { (stickerPack) in
                self.upsertStickerPack(stickerPack: stickerPack,
                                       installMode: installMode,
                                       wasLocallyInitiated: wasLocallyInitiated)
        }.catch { error in
            Logger.verbose("Error: \(error)")
        }
    }

    private let packOperationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "org.signal.StickerManager.packs"
        operationQueue.maxConcurrentOperationCount = 3
        return operationQueue
    }()

    private func tryToDownloadStickerPack(stickerPackInfo: StickerPackInfo) -> Promise<StickerPack> {
        let (promise, future) = Promise<StickerPack>.pending()
        let operation = DownloadStickerPackOperation(stickerPackInfo: stickerPackInfo,
                                                     success: future.resolve,
                                                     failure: future.reject)
        packOperationQueue.addOperation(operation)
        return promise
    }

    // This method is public so that we can download "transient" (uninstalled) sticker packs.
    public class func tryToDownloadStickerPack(stickerPackInfo: StickerPackInfo) -> Promise<StickerPack> {
        return shared.tryToDownloadStickerPack(stickerPackInfo: stickerPackInfo)
    }

    private class func upsertStickerPack(stickerPack: StickerPack,
                                         installMode: InstallMode,
                                         wasLocallyInitiated: Bool) {

        databaseStorage.write { (transaction) in
            upsertStickerPack(stickerPack: stickerPack,
                              installMode: installMode,
                              wasLocallyInitiated: wasLocallyInitiated,
                              transaction: transaction)
        }
    }

    private class func upsertStickerPack(stickerPack stickerPackParam: StickerPack,
                                         installMode: InstallMode,
                                         wasLocallyInitiated: Bool,
                                         transaction: SDSAnyWriteTransaction) {

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
            enqueueStickerSyncMessage(operationType: .install,
                                      packs: [stickerPack.info],
                                      transaction: transaction)
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
                promise = self.markSavedStickerPackAsInstalled(stickerPack: stickerPack,
                                                               wasLocallyInitiated: wasLocallyInitiated,
                                                               transaction: transaction)
            case .installIfUnsaved:
                if !wasSaved {
                    promise = self.markSavedStickerPackAsInstalled(stickerPack: stickerPack,
                                                                   wasLocallyInitiated: wasLocallyInitiated,
                                                                   transaction: transaction)
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

    private class func markSavedStickerPackAsInstalled(stickerPack: StickerPack,
                                                       wasLocallyInitiated: Bool,
                                                       transaction: SDSAnyWriteTransaction) -> Promise<Void> {

        if stickerPack.isInstalled {
            return .value(())
        }

        Logger.verbose("Installing sticker pack: \(stickerPack.info).")

        stickerPack.update(withIsInstalled: true, transaction: transaction)

        let promise = installStickerPackContents(stickerPack: stickerPack, transaction: transaction)

        if wasLocallyInitiated {
            enqueueStickerSyncMessage(operationType: .install,
                                      packs: [stickerPack.info],
                                      transaction: transaction)
        }
        return promise
    }

    private class func installStickerPackContents(stickerPack: StickerPack,
                                                  transaction: SDSAnyReadTransaction,
                                                  onlyInstallCover: Bool = false) -> Promise<Void> {
        // Note: It's safe to kick off downloads of stickers that are already installed.
        var fetches = [Promise<Void>]()
        var needsNotify = false

        // The cover.
        let coverFetch = firstly {
            tryToDownloadAndInstallSticker(
                stickerPack: stickerPack,
                item: stickerPack.cover,
                transaction: transaction)
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
                        transaction: transaction)
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
            self.tryToDownloadStickerPacks(stickerPacks: DefaultStickerPack.packsToAutoInstall,
                                           installMode: .installIfUnsaved)
            self.tryToDownloadStickerPacks(stickerPacks: DefaultStickerPack.packsToNotAutoInstall,
                                           installMode: .doNotInstall)
        }
    }

    @objc
    public class func installedStickers(forStickerPack stickerPack: StickerPack,
                                        verifyExists: Bool) -> [StickerInfo] {
        var result = [StickerInfo]()
        databaseStorage.read { (transaction) in
            result = self.installedStickers(forStickerPack: stickerPack,
                                            verifyExists: verifyExists,
                                            transaction: transaction)
        }
        return result
    }

    @objc
    public class func installedStickers(forStickerPack stickerPack: StickerPack,
                                        verifyExists: Bool,
                                        transaction: SDSAnyReadTransaction) -> [StickerInfo] {

        var result = [StickerInfo]()
        for stickerInfo in stickerPack.stickerInfos {
            let uniqueId = InstalledSticker.uniqueId(for: stickerInfo)
            guard let installedSticker = InstalledSticker.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
                    continue
            }
            if verifyExists,
                nil == self.stickerDataUrl(forInstalledSticker: installedSticker, verifyExists: verifyExists) {
                continue
            }
            result.append(stickerInfo)
        }
        return result
    }

    @objc
    public class func isDefaultStickerPack(packId: Data) -> Bool {
        return DefaultStickerPack.isDefaultStickerPack(packId: packId)
    }

    @objc
    public class func isStickerPackInstalled(stickerPackInfo: StickerPackInfo) -> Bool {
        var result = false
        databaseStorage.read { (transaction) in
            result = isStickerPackInstalled(stickerPackInfo: stickerPackInfo,
                                            transaction: transaction)
        }
        return result
    }

    @objc
    public class func isStickerPackInstalled(stickerPackInfo: StickerPackInfo,
                                             transaction: SDSAnyReadTransaction) -> Bool {
        guard let pack = fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction) else {
            return false
        }
        return pack.isInstalled
    }

    // MARK: - Stickers

    @objc
    public static func stickerType(forContentType contentType: String?) -> StickerType {
        StickerType.stickerType(forContentType: contentType)
    }

    @objc(installedStickerMetadataWithSneakyTransaction:)
    public class func installedStickerMetadataWithSneakyTransaction(stickerInfo: StickerInfo) -> StickerMetadata? {
        databaseStorage.read { transaction in
            self.installedStickerMetadata(stickerInfo: stickerInfo,
                                          transaction: transaction)
        }
    }

    @objc
    public class func installedStickerMetadata(stickerInfo: StickerInfo,
                                               transaction: SDSAnyReadTransaction) -> StickerMetadata? {

        let uniqueId = InstalledSticker.uniqueId(for: stickerInfo)
        guard let installedSticker = InstalledSticker.anyFetch(uniqueId: uniqueId,
                                                               transaction: transaction) else {
                                                                return nil
        }

        return installedStickerMetadata(installedSticker: installedSticker,
                                        transaction: transaction)
    }

    @objc
    public class func installedStickerMetadata(installedSticker: InstalledSticker,
                                               transaction: SDSAnyReadTransaction) -> StickerMetadata? {

        let stickerInfo = installedSticker.info
        let stickerType = StickerType.stickerType(forContentType: installedSticker.contentType)
        guard let stickerDataUrl = self.stickerDataUrl(stickerInfo: stickerInfo, stickerType: stickerType, verifyExists: true) else {
            return nil
        }
        return StickerMetadata(stickerInfo: stickerInfo,
                               stickerType: stickerType,
                               stickerDataUrl: stickerDataUrl,
                               emojiString: installedSticker.emojiString)
    }

    @objc
    public class func stickerDataUrlWithSneakyTransaction(stickerInfo: StickerInfo, verifyExists: Bool) -> URL? {
        guard let installedSticker = fetchInstalledStickerWithSneakyTransaction(stickerInfo: stickerInfo) else {
            return nil
        }
        return self.stickerDataUrl(forInstalledSticker: installedSticker, verifyExists: verifyExists)
    }

    private class func stickerDataUrl(stickerInfo: StickerInfo,
                                      contentType: String?,
                                      verifyExists: Bool) -> URL? {
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

    @objc
    public class func filepathsForAllInstalledStickers(transaction: SDSAnyReadTransaction) -> [String] {

        var filePaths = [String]()
        InstalledSticker.anyEnumerate(transaction: transaction) { (installedSticker, _) in
            if let stickerDataUrl = stickerDataUrl(forInstalledSticker: installedSticker, verifyExists: true) {
                filePaths.append(stickerDataUrl.path)
            }
        }
        return filePaths
    }

    @objc
    public class func isStickerInstalled(stickerInfo: StickerInfo) -> Bool {
        var result = false
        databaseStorage.read { (transaction) in
            result = isStickerInstalled(stickerInfo: stickerInfo,
                                        transaction: transaction)
        }
        return result
    }

    @objc
    public class func isStickerInstalled(stickerInfo: StickerInfo,
                                         transaction: SDSAnyReadTransaction) -> Bool {
        let uniqueId = InstalledSticker.uniqueId(for: stickerInfo)
        // We use anyFetch(...) instead of anyExists(...) to
        // leverage the model cache.
        return InstalledSticker.anyFetch(uniqueId: uniqueId, transaction: transaction) != nil
    }

    internal typealias CleanupCompletion = () -> Void

    internal class func uninstallSticker(stickerInfo: StickerInfo,
                                         transaction: SDSAnyWriteTransaction) {

        guard let installedSticker = fetchInstalledSticker(stickerInfo: stickerInfo, transaction: transaction) else {
            Logger.info("Skipping uninstall; not installed.")
            return
        }

        Logger.verbose("Uninstalling sticker: \(stickerInfo).")

        installedSticker.anyRemove(transaction: transaction)

        removeFromRecentStickers(stickerInfo, transaction: transaction)

        removeStickerFromEmojiMap(installedSticker, transaction: transaction)

        guard let stickerDataUrl = self.stickerDataUrl(forInstalledSticker: installedSticker, verifyExists: false) else {
            owsFailDebug("Could not generate sticker data URL.")
            return
        }

        // Cleans up the sticker data on disk. We want to do these deletions
        // after the transaction is complete so that other transactions aren't
        // blocked.
        transaction.addSyncCompletion {
            DispatchQueue.global(qos: .background).async {
                do {
                    try OWSFileSystem.deleteFileIfExists(url: stickerDataUrl)
                } catch {
                    owsFailDebug("Error: \(error)")
                }
            }
        }

        // No need to post stickersOrPacksDidChange; caller will do that.
    }

    @objc
    public class func fetchInstalledStickerWithSneakyTransaction(stickerInfo: StickerInfo) -> InstalledSticker? {
        databaseStorage.read { transaction in
            self.fetchInstalledSticker(stickerInfo: stickerInfo, transaction: transaction)
        }
    }

    @objc
    public class func fetchInstalledSticker(stickerInfo: StickerInfo,
                                            transaction: SDSAnyReadTransaction) -> InstalledSticker? {

        let uniqueId = InstalledSticker.uniqueId(for: stickerInfo)

        return InstalledSticker.anyFetch(uniqueId: uniqueId, transaction: transaction)
    }

    @objc
    public class func installSticker(stickerInfo: StickerInfo,
                                     stickerUrl stickerTemporaryUrl: URL,
                                     contentType: String?,
                                     emojiString: String?) -> Bool {
        guard nil == fetchInstalledStickerWithSneakyTransaction(stickerInfo: stickerInfo) else {
            // Sticker already installed, skip.
            return false
        }

        guard OWSFileSystem.fileOrFolderExists(url: stickerTemporaryUrl) else {
            owsFailDebug("Missing sticker file.")
            return false
        }

        Logger.verbose("Installing sticker: \(stickerInfo).")

        let installedSticker = InstalledSticker(info: stickerInfo,
                                                contentType: contentType,
                                                emojiString: emojiString)

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
        } catch let error as NSError {
            if OWSFileSystem.fileOrFolderExists(url: stickerDataUrl) {
                // Races can occur; ignore and proceed.
                Logger.warn("File already exists: \(error)")
            } else {
                owsFailDebug("File write failed: \(error)")
                return false
            }
        }

        return databaseStorage.write { (transaction) -> Bool in
            guard nil == fetchInstalledSticker(stickerInfo: stickerInfo, transaction: transaction) else {
                // RACE: sticker has already been installed between now and when we last checked.
                //
                // Initially we check for a stickers presence with a read transaction, to avoid opening
                // an unnecessary write transaction. However, it's possible a race has occurred and the
                // sticker has since been installed, in which case there's nothing more for us to do.
                return false
            }

            installedSticker.anyInsert(transaction: transaction)

            #if DEBUG
            guard self.isStickerInstalled(stickerInfo: stickerInfo, transaction: transaction) else {
                owsFailDebug("Skipping redundant sticker install.")
                return false
            }
            if !OWSFileSystem.fileOrFolderExists(url: stickerDataUrl) {
                owsFailDebug("Missing sticker data for installed sticker.")
                return false
            }
            #endif

            self.addStickerToEmojiMap(installedSticker, transaction: transaction)
            return true
        }
    }

    private class func tryToDownloadAndInstallSticker(stickerPack: StickerPack,
                                                      item: StickerPackItem,
                                                      transaction: SDSAnyReadTransaction) -> Promise<Bool> {
        let stickerInfo: StickerInfo = item.stickerInfo(with: stickerPack)
        let emojiString = item.emojiString

        guard !self.isStickerInstalled(stickerInfo: stickerInfo, transaction: transaction) else {
            // Skipping redundant sticker install.
            return .value(false)
        }

        return firstly {
            tryToDownloadSticker(stickerPack: stickerPack, stickerInfo: stickerInfo)
        }.map(on: .global()) { stickerUrl in
            self.installSticker(stickerInfo: stickerInfo,
                                stickerUrl: stickerUrl,
                                contentType: item.contentType,
                                emojiString: emojiString)
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
    private let stickerDownloadQueue = DispatchQueue(label: "stickerManager.stickerDownloadQueue")
    // This property should only be accessed on stickerDownloadQueue.
    private var stickerDownloadMap = [String: StickerDownload]()
    private let stickerOperationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "org.signal.StickerManager.stickers"
        operationQueue.maxConcurrentOperationCount = 4
        return operationQueue
    }()

    private func tryToDownloadSticker(stickerPack: StickerPack,
                                      stickerInfo: StickerInfo) -> Promise<URL> {
        if let stickerUrl = DownloadStickerOperation.cachedUrl(for: stickerInfo) {
            return Promise.value(stickerUrl)
        }
        return stickerDownloadQueue.sync { () -> Promise<URL> in
            if let stickerDownload = stickerDownloadMap[stickerInfo.asKey()] {
                return stickerDownload.promise
            }

            let stickerDownload = StickerDownload()
            stickerDownloadMap[stickerInfo.asKey()] = stickerDownload

            let operation = DownloadStickerOperation(stickerInfo: stickerInfo,
                                                     success: { [weak self] data in
                                                        guard let self = self else {
                                                            return
                                                        }
                                                        _ = self.stickerDownloadQueue.sync {
                                                            self.stickerDownloadMap.removeValue(forKey: stickerInfo.asKey())
                                                        }
                                                        stickerDownload.future.resolve(data)
                },
                                                     failure: { [weak self] error in
                                                        guard let self = self else {
                                                            return
                                                        }
                                                        _ = self.stickerDownloadQueue.sync {
                                                            self.stickerDownloadMap.removeValue(forKey: stickerInfo.asKey())
                                                        }
                                                        stickerDownload.future.reject(error)
            })
            self.stickerOperationQueue.addOperation(operation)
            return stickerDownload.promise
        }
    }

    // This method is public so that we can download "transient" (uninstalled) stickers.
    public class func tryToDownloadSticker(stickerPack: StickerPack,
                                           stickerInfo: StickerInfo) -> Promise<URL> {
        shared.tryToDownloadSticker(stickerPack: stickerPack, stickerInfo: stickerInfo)
    }

    // MARK: - Emoji

    @objc
    public class func allEmoji(inEmojiString emojiString: String?) -> [String] {
        guard let emojiString = emojiString else {
            return []
        }

        return emojiString.map(String.init).filter {
            $0.containsOnlyEmoji
        }
    }

    @objc
    public class func firstEmoji(inEmojiString emojiString: String?) -> String? {
        return allEmoji(inEmojiString: emojiString).first
    }

    private class func addStickerToEmojiMap(_ installedSticker: InstalledSticker,
                                            transaction: SDSAnyWriteTransaction) {

        guard let emojiString = installedSticker.emojiString else {
            return
        }
        let stickerId = installedSticker.uniqueId
        for emoji in allEmoji(inEmojiString: emojiString) {
            emojiMapStore.appendToStringSet(key: emoji,
                                            value: stickerId,
                                            transaction: transaction)
        }

        shared.clearSuggestedStickersCache()
    }

    private class func removeStickerFromEmojiMap(_ installedSticker: InstalledSticker,
                                                 transaction: SDSAnyWriteTransaction) {
        guard let emojiString = installedSticker.emojiString else {
            return
        }
        let stickerId = installedSticker.uniqueId
        for emoji in allEmoji(inEmojiString: emojiString) {
            emojiMapStore.removeFromStringSet(key: emoji,
                                              value: stickerId,
                                              transaction: transaction)
        }

        shared.clearSuggestedStickersCache()
    }

    private static let cacheQueue = DispatchQueue(label: "stickerManager.cacheQueue")
    // This cache should only be accessed on cacheQueue.
    private var suggestedStickersCache = LRUCache<String, [InstalledSticker]>(maxSize: 5)

    // We clear the cache every time we install or uninstall a sticker.
    private func clearSuggestedStickersCache() {
        StickerManager.cacheQueue.sync {
            self.suggestedStickersCache.removeAllObjects()
        }
    }

    @objc
    public func suggestedStickers(forTextInput textInput: String) -> [InstalledSticker] {
        return StickerManager.cacheQueue.sync {
            if let suggestions = suggestedStickersCache.object(forKey: textInput) {
                return suggestions
            }

            let suggestions = StickerManager.suggestedStickers(forTextInput: textInput)
            suggestedStickersCache.setObject(suggestions, forKey: textInput)
            return suggestions
        }
    }

    internal class func suggestedStickers(forTextInput textInput: String) -> [InstalledSticker] {
        var result = [InstalledSticker]()
        databaseStorage.read { (transaction) in
            result = self.suggestedStickers(forTextInput: textInput, transaction: transaction)
        }
        return result
    }

    internal class func suggestedStickers(forTextInput textInput: String,
                                          transaction: SDSAnyReadTransaction) -> [InstalledSticker] {
        guard let emoji = firstEmoji(inEmojiString: textInput) else {
            // Text input contains no emoji.
            return []
        }
        guard emoji == textInput else {
            // Text input contains more than just a single emoji.
            return []
        }
        let stickerIds = emojiMapStore.stringSet(forKey: emoji, transaction: transaction)
        return stickerIds.compactMap { (stickerId) in
            guard let installedSticker = InstalledSticker.anyFetch(uniqueId: stickerId, transaction: transaction) else {
                owsFailDebug("Missing installed sticker.")
                return nil
            }
            return installedSticker
        }
    }

    // MARK: - Known Sticker Packs

    @objc
    public class func addKnownStickerInfo(_ stickerInfo: StickerInfo,
                                          transaction: SDSAnyWriteTransaction) {
        let packInfo = stickerInfo.packInfo
        let uniqueId = KnownStickerPack.uniqueId(for: packInfo)
        if let existing = KnownStickerPack.anyFetch(uniqueId: uniqueId, transaction: transaction) {
            let pack = existing
            pack.anyUpdate(transaction: transaction) { pack in
                pack.referenceCount += 1
            }
        } else {
            let pack = KnownStickerPack(info: packInfo)
            pack.referenceCount += 1
            pack.anyInsert(transaction: transaction)
        }
    }

    @objc
    public class func removeKnownStickerInfo(_ stickerInfo: StickerInfo,
                                             transaction: SDSAnyWriteTransaction) {
        let packInfo = stickerInfo.packInfo
        let uniqueId = KnownStickerPack.uniqueId(for: packInfo)
        guard let pack = KnownStickerPack.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
            owsFailDebug("Missing known sticker pack.")
            return
        }
        if pack.referenceCount <= 1 {
            pack.anyRemove(transaction: transaction)
        } else {
            pack.anyUpdate(transaction: transaction) { (pack) in
                pack.referenceCount -= 1
            }
        }
    }

    @objc
    public class func allKnownStickerPackInfos(transaction: SDSAnyReadTransaction) -> [StickerPackInfo] {
        return allKnownStickerPacks(transaction: transaction).map { $0.info }
    }

    @objc
    public class func allKnownStickerPacks(transaction: SDSAnyReadTransaction) -> [KnownStickerPack] {
        var result = [KnownStickerPack]()
        KnownStickerPack.anyEnumerate(transaction: transaction) { (knownStickerPack, _) in
            result.append(knownStickerPack)
        }
        return result
    }

    private class func tryToDownloadStickerPacks(stickerPacks: [StickerPackInfo],
                                                 installMode: InstallMode) {

        var stickerPacksToDownload = [StickerPackInfo]()
        StickerManager.databaseStorage.read { (transaction) in
            for stickerPackInfo in stickerPacks {
                if !StickerManager.isStickerPackSaved(stickerPackInfo: stickerPackInfo, transaction: transaction) {
                    stickerPacksToDownload.append(stickerPackInfo)
                }
            }
        }

        for stickerPackInfo in stickerPacksToDownload {
            StickerManager.tryToDownloadAndSaveStickerPack(stickerPackInfo: stickerPackInfo,
                                                           installMode: installMode,
                                                           wasLocallyInitiated: true)
        }
    }

    // MARK: - Missing Packs

    // Track which sticker packs downloads have failed permanently.
    private static var missingStickerPacks = Set<String>()

    @objc
    public class func markStickerPackAsMissing(stickerPackInfo: StickerPackInfo) {
        DispatchQueue.main.async {
            self.missingStickerPacks.insert(stickerPackInfo.asKey())
        }
    }

    @objc
    public class func isStickerPackMissing(stickerPackInfo: StickerPackInfo) -> Bool {
        AssertIsOnMainThread()

        return missingStickerPacks.contains(stickerPackInfo.asKey())
    }

    // MARK: - Recents

    private static var kRecentStickersKey: String { "recentStickers" }
    private static let kRecentStickersMaxCount: Int = 25

    @objc
    public class func stickerWasSent(_ stickerInfo: StickerInfo,
                                     transaction: SDSAnyWriteTransaction) {
        guard isStickerInstalled(stickerInfo: stickerInfo) else {
            return
        }
        store.appendToStringSet(key: kRecentStickersKey,
                                value: stickerInfo.asKey(),
                                transaction: transaction,
                                maxCount: kRecentStickersMaxCount)
        NotificationCenter.default.postNotificationNameAsync(recentStickersDidChange, object: nil)
    }

    private class func removeFromRecentStickers(_ stickerInfo: StickerInfo,
                                                transaction: SDSAnyWriteTransaction) {
        store.removeFromStringSet(key: kRecentStickersKey,
                                  value: stickerInfo.asKey(),
                                  transaction: transaction)
        NotificationCenter.default.postNotificationNameAsync(recentStickersDidChange, object: nil)
    }

    // Returned in descending order of recency.
    //
    // Only returns installed stickers.
    @objc
    public class func recentStickers() -> [StickerInfo] {
        var result = [StickerInfo]()
        databaseStorage.read { (transaction) in
            result = self.recentStickers(transaction: transaction)
        }
        return result
    }

    // Returned in descending order of recency.
    //
    // Only returns installed stickers.
    private class func recentStickers(transaction: SDSAnyReadTransaction) -> [StickerInfo] {
        let keys = store.stringSet(forKey: kRecentStickersKey, transaction: transaction)
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
            databaseStorage.read { (transaction) in
                for stickerPack in self.allStickerPacks(transaction: transaction) {
                    ensureDownloads(forStickerPack: stickerPack, transaction: transaction)
                }
            }
        }
    }

    public class func ensureDownloadsAsync(forStickerPack stickerPack: StickerPack) -> Promise<Void> {
        let (promise, future) = Promise<Void>.pending()
        DispatchQueue.global().async {
            databaseStorage.read { (transaction) in
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

    private class func cleanupOrphans() {
        guard !DebugFlags.suppressBackgroundActivity else {
            // Don't clean up.
            return
        }
        DispatchQueue.global().async {
            databaseStorage.write { (transaction) in
                var stickerPackMap = [String: StickerPack]()
                for stickerPack in StickerPack.anyFetchAll(transaction: transaction) {
                    stickerPackMap[stickerPack.info.asKey()] = stickerPack
                }

                // Cull any orphan packs.
                let savedStickerPacks = Array(stickerPackMap.values)
                for stickerPack in savedStickerPacks {
                    let isDefaultStickerPack = self.isDefaultStickerPack(packId: stickerPack.info.packId)
                    let isInstalled = stickerPack.isInstalled
                    if !isDefaultStickerPack && !isInstalled {
                        owsFailDebug("Removing orphan pack")
                        stickerPack.anyRemove(transaction: transaction)
                        stickerPackMap.removeValue(forKey: stickerPack.info.asKey())
                    }
                }

                var stickersToUninstall = [InstalledSticker]()
                InstalledSticker.anyEnumerate(transaction: transaction) { (sticker, _) in
                    guard let pack = stickerPackMap[sticker.info.packInfo.asKey()] else {
                        stickersToUninstall.append(sticker)
                        return
                    }
                    if pack.isInstalled {
                        return
                    }
                    if pack.coverInfo == sticker.info {
                        return
                    }
                    stickersToUninstall.append(sticker)
                    return
                }
                if stickersToUninstall.count > 0 {
                    Logger.warn("Removing \(stickersToUninstall.count) orphan stickers.")
                }
                for sticker in stickersToUninstall {
                    self.uninstallSticker(stickerInfo: sticker.info, transaction: transaction)
                }
            }
        }
    }

    // MARK: - Sync Messages

    private class func enqueueStickerSyncMessage(operationType: StickerPackOperationType,
                                                 packs: [StickerPackInfo],
                                                 transaction: SDSAnyWriteTransaction) {
        guard tsAccountManager.isRegisteredAndReady else {
            return
        }
        guard let thread = TSAccountManager.getOrCreateLocalThread(transaction: transaction) else {
            owsFailDebug("Missing thread.")
            return
        }

        let message = OWSStickerPackSyncMessage(thread: thread, packs: packs, operationType: operationType, transaction: transaction)
        self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
    }

    @objc
    public class func syncAllInstalledPacks(transaction: SDSAnyWriteTransaction) {
        guard tsAccountManager.isRegisteredAndReady else {
            return
        }

        let stickerPackInfos = installedStickerPacks(transaction: transaction).map { $0.info }
        guard stickerPackInfos.count > 0 else {
            return
        }

        enqueueStickerSyncMessage(operationType: .install,
                                  packs: stickerPackInfos,
                                  transaction: transaction)
    }

    @objc
    public class func processIncomingStickerPackOperation(_ proto: SSKProtoSyncMessageStickerPackOperation,
                                                          transaction: SDSAnyWriteTransaction) {
        guard tsAccountManager.isRegisteredAndReady else {
            return
        }

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
            tryToDownloadAndSaveStickerPack(stickerPackInfo: stickerPackInfo,
                                            installMode: .install,
                                            wasLocallyInitiated: false)
        case .remove:
            uninstallStickerPack(stickerPackInfo: stickerPackInfo, wasLocallyInitiated: false, transaction: transaction)
        @unknown default:
            owsFailDebug("Unknown type.")
            return
        }
    }

    // MARK: - Debug

    // This is only intended for use while debugging.
    #if DEBUG
    @objc
    public class func uninstallAllStickerPacks() {
        databaseStorage.write { (transaction) in
            let stickerPacks = installedStickerPacks(transaction: transaction)
            for stickerPack in stickerPacks {
                uninstallStickerPack(stickerPackInfo: stickerPack.info,
                                     wasLocallyInitiated: true,
                                     transaction: transaction)
            }
        }
    }

    @objc
    public class func removeAllStickerPacks() {
        databaseStorage.write { (transaction) in
            let stickerPacks = allStickerPacks(transaction: transaction)
            for stickerPack in stickerPacks {
                uninstallStickerPack(stickerPackInfo: stickerPack.info,
                                     uninstallEverything: true,
                                     wasLocallyInitiated: true,
                                     transaction: transaction)
                stickerPack.anyRemove(transaction: transaction)
            }
        }
    }

    @objc
    public class func tryToInstallAllAvailableStickerPacks() {
        databaseStorage.write { (transaction) in
            for stickerPack in self.availableStickerPacks(transaction: transaction) {
                self.installStickerPack(stickerPack: stickerPack, wasLocallyInitiated: true, transaction: transaction)
            }
        }

        tryToDownloadDefaultStickerPacks()
    }
    #endif
}

// MARK: -

// These methods are used to maintain a "string set":
// A set (no duplicates) of strings stored as a list.
// As a bonus, the set is stored in order of descending recency.
extension SDSKeyValueStore {
    func appendToStringSet(key: String,
                           value: String,
                           transaction: SDSAnyWriteTransaction,
                           maxCount: Int? = nil) {
        // Prepend value to ensure descending order of recency.
        var stringSet = [value]
        if let storedValue = getObject(forKey: key, transaction: transaction) as? [String] {
            stringSet += storedValue.filter {
                $0 != value
            }
        }
        if let maxCount = maxCount {
            stringSet = Array(stringSet.prefix(maxCount))
        }
        setObject(stringSet, key: key, transaction: transaction)
    }

    func removeFromStringSet(key: String,
                             value: String,
                             transaction: SDSAnyWriteTransaction) {
        var stringSet = [String]()
        if let storedValue = getObject(forKey: key, transaction: transaction) as? [String] {
            guard storedValue.contains(value) else {
                // No work to do.
                return
            }
            stringSet += storedValue.filter {
                $0 != value
            }
        }
        setObject(stringSet, key: key, transaction: transaction)
    }

    func stringSet(forKey key: String,
                   transaction: SDSAnyReadTransaction) -> [String] {
        guard let object = self.getObject(forKey: key, transaction: transaction) else {
            return []
        }
        guard let stringSet = object as? [String] else {
            owsFailDebug("Value has unexpected type \(type(of: object)).")
            return []
        }
        return stringSet
    }
}
