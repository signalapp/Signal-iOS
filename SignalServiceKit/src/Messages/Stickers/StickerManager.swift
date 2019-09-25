//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import HKDFKit

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
    public static let stickersOrPacksDidChange = Notification.Name("stickersOrPacksDidChange")
    @objc
    public static let recentStickersDidChange = Notification.Name("recentStickersDidChange")
    @objc
    public static let isStickerSendEnabledDidChange = Notification.Name("isStickerSendEnabledDidChange")

    // MARK: - Dependencies

    @objc
    public class var shared: StickerManager {
        return SSKEnvironment.shared.stickerManager
    }

    private static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private static var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    private static var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    // MARK: - Properties

    private static let operationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "org.signal.StickerManager"
        operationQueue.maxConcurrentOperationCount = 4
        return operationQueue
    }()

    public static let store = SDSKeyValueStore(collection: "recentStickers")
    public static let emojiMapStore = SDSKeyValueStore(collection: "emojiMap")

    private static let serialQueue = DispatchQueue(label: "org.signal.stickers")

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
        AppReadiness.runNowOrWhenAppWillBecomeReady {
            // Warm the caches.
            StickerManager.shared.warmIsStickerSendEnabled()
            StickerManager.shared.warmTooltipState()
        }
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            StickerManager.cleanupOrphans()

            if TSAccountManager.sharedInstance().isRegisteredAndReady {
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
        tryToDownloadDefaultStickerPacks(shouldInstall: false)

        // Try to download the stickers for "installed" sticker packs.
        ensureAllStickerDownloadsAsync()
    }

    // MARK: - Paths

    @objc
    public class func cacheDirUrl() -> URL {
        var url = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
        url.appendPathComponent("StickerManager")
        OWSFileSystem.ensureDirectoryExists(url.path)
        return url
    }

    private class func stickerUrl(stickerInfo: StickerInfo) -> URL {

        let uniqueId = InstalledSticker.uniqueId(for: stickerInfo)

        var url = cacheDirUrl()
        // All stickers are .webp.
        url.appendPathComponent("\(uniqueId).webp")
        return url
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
                                           transaction: SDSAnyWriteTransaction) {
        uninstallStickerPack(stickerPackInfo: stickerPackInfo,
                             uninstallEverything: false,
                             transaction: transaction)
    }

    private class func uninstallStickerPack(stickerPackInfo: StickerPackInfo,
                                            uninstallEverything: Bool,
                                            transaction: SDSAnyWriteTransaction) {

        guard let stickerPack = fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction) else {
            Logger.info("Skipping uninstall; not saved or installed.")
            return
        }

        Logger.verbose("Uninstalling sticker pack: \(stickerPackInfo).")

        let isDefaultStickerPack = DefaultStickerPack.isDefaultStickerPack(stickerPackInfo: stickerPackInfo)
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

        enqueueStickerSyncMessage(operationType: .remove,
                                  packs: [stickerPackInfo],
                                  transaction: transaction)

        NotificationCenter.default.postNotificationNameAsync(stickersOrPacksDidChange, object: nil)
    }

    @objc
    public class func installStickerPack(stickerPack: StickerPack,
                                         transaction: SDSAnyWriteTransaction) {
        upsertStickerPack(stickerPack: stickerPack,
                          installMode: .install,
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
                                                       installMode: InstallMode) {
        return tryToDownloadStickerPack(stickerPackInfo: stickerPackInfo)
            .done(on: DispatchQueue.global()) { (stickerPack) in
                self.upsertStickerPack(stickerPack: stickerPack,
                                       installMode: installMode)
            }.retainUntilComplete()
    }

    // This method is public so that we can download "transient" (uninstalled) sticker packs.
    public class func tryToDownloadStickerPack(stickerPackInfo: StickerPackInfo) -> Promise<StickerPack> {
        let (promise, resolver) = Promise<StickerPack>.pending()
        let operation = DownloadStickerPackOperation(stickerPackInfo: stickerPackInfo,
                                                     success: resolver.fulfill,
                                                     failure: resolver.reject)
        operationQueue.addOperation(operation)
        return promise
    }

    private class func upsertStickerPack(stickerPack: StickerPack,
                                         installMode: InstallMode) {

        databaseStorage.write { (transaction) in
            upsertStickerPack(stickerPack: stickerPack,
                              installMode: installMode,
                              transaction: transaction)
        }
    }

    private class func upsertStickerPack(stickerPack: StickerPack,
                                         installMode: InstallMode,
                                         transaction: SDSAnyWriteTransaction) {

        let oldCopy = fetchStickerPack(stickerPackInfo: stickerPack.info, transaction: transaction)
        let wasSaved = oldCopy != nil

        // Preserve old mutable state.
        if let oldCopy = oldCopy {
            stickerPack.update(withIsInstalled: oldCopy.isInstalled, transaction: transaction)
        } else {
            stickerPack.anyInsert(transaction: transaction)
        }

        self.shared.stickerPackWasInstalled(transaction: transaction)

        if stickerPack.isInstalled {
            enqueueStickerSyncMessage(operationType: .install,
                                      packs: [stickerPack.info],
                                      transaction: transaction)
        }

        // If the pack is already installed, make sure all stickers are installed.
        if stickerPack.isInstalled {
            installStickerPackContents(stickerPack: stickerPack, transaction: transaction).retainUntilComplete()
        } else {
            switch installMode {
            case .doNotInstall:
                break
            case .install:
                self.markSavedStickerPackAsInstalled(stickerPack: stickerPack, transaction: transaction)
            case .installIfUnsaved:
                if !wasSaved {
                    self.markSavedStickerPackAsInstalled(stickerPack: stickerPack, transaction: transaction)
                }
            }
        }

        NotificationCenter.default.postNotificationNameAsync(stickersOrPacksDidChange, object: nil)
    }

    private class func markSavedStickerPackAsInstalled(stickerPack: StickerPack,
                                                       transaction: SDSAnyWriteTransaction) {

        if stickerPack.isInstalled {
            return
        }

        Logger.verbose("Installing sticker pack: \(stickerPack.info).")

        stickerPack.update(withIsInstalled: true, transaction: transaction)

        if !isDefaultStickerPack(stickerPack.info) {
            shared.setHasUsedStickers(transaction: transaction)
        }

        installStickerPackContents(stickerPack: stickerPack, transaction: transaction).retainUntilComplete()

        enqueueStickerSyncMessage(operationType: .install,
                                  packs: [stickerPack.info],
                                  transaction: transaction)
    }

    private class func installStickerPackContents(stickerPack: StickerPack,
                                                  transaction: SDSAnyReadTransaction,
                                                  onlyInstallCover: Bool = false) -> Promise<Void> {
        // Note: It's safe to kick off downloads of stickers that are already installed.

        var fetches = [Promise<Void>]()

        // The cover.
        fetches.append(tryToDownloadAndInstallSticker(stickerPack: stickerPack, item: stickerPack.cover, transaction: transaction))

        guard !onlyInstallCover else {
            return when(fulfilled: fetches)
        }

        // The stickers.
        for item in stickerPack.items {
            fetches.append(tryToDownloadAndInstallSticker(stickerPack: stickerPack, item: item, transaction: transaction))
        }
        return when(fulfilled: fetches)
    }

    private class func tryToDownloadDefaultStickerPacks(shouldInstall: Bool) {
        tryToDownloadStickerPacks(stickerPacks: DefaultStickerPack.packsToAutoInstall,
                                  installMode: .installIfUnsaved)
        tryToDownloadStickerPacks(stickerPacks: DefaultStickerPack.packsToNotAutoInstall,
                                  installMode: .doNotInstall)
    }

    @objc
    public class func installedStickers(forStickerPack stickerPack: StickerPack) -> [StickerInfo] {
        var result = [StickerInfo]()
        databaseStorage.read { (transaction) in
            result = self.installedStickers(forStickerPack: stickerPack,
                                            transaction: transaction)
        }
        return result
    }

    @objc
    public class func installedStickers(forStickerPack stickerPack: StickerPack,
                                        transaction: SDSAnyReadTransaction) -> [StickerInfo] {
        var result = [StickerInfo]()
        for stickerInfo in stickerPack.stickerInfos {
            if isStickerInstalled(stickerInfo: stickerInfo, transaction: transaction) {
                #if DEBUG
                if nil == self.filepathForInstalledSticker(stickerInfo: stickerInfo, transaction: transaction) {
                    owsFailDebug("Missing sticker data for installed sticker.")
                }
                #endif
                result.append(stickerInfo)
            }
        }
        return result
    }

    @objc
    public class func isDefaultStickerPack(_ packInfo: StickerPackInfo) -> Bool {
        return DefaultStickerPack.isDefaultStickerPack(stickerPackInfo: packInfo)
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
    public class func filepathForInstalledSticker(stickerInfo: StickerInfo) -> String? {
        var result: String?
        databaseStorage.read { (transaction) in
            result = filepathForInstalledSticker(stickerInfo: stickerInfo,
                                                 transaction: transaction)
        }
        return result
    }

    @objc
    public class func filepathForInstalledSticker(stickerInfo: StickerInfo,
                                                  transaction: SDSAnyReadTransaction) -> String? {

        if isStickerInstalled(stickerInfo: stickerInfo,
                              transaction: transaction) {
            return stickerUrl(stickerInfo: stickerInfo).path
        } else {
            return nil
        }
    }

    @objc
    public class func filepathsForAllInstalledStickers(transaction: SDSAnyReadTransaction) -> [String] {

        var filePaths = [String]()
        let installedStickers = InstalledSticker.anyFetchAll(transaction: transaction)
        for installedSticker in installedStickers {
            let filePath = stickerUrl(stickerInfo: installedSticker.info).path
            filePaths.append(filePath)
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
        return nil != fetchInstalledSticker(stickerInfo: stickerInfo, transaction: transaction)
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

        // Cleans up the sticker data on disk. We want to do these deletions
        // after the transaction is complete so that other transactions aren't
        // blocked.
        DispatchQueue.global(qos: .background).async {
            let url = stickerUrl(stickerInfo: stickerInfo)
            OWSFileSystem.deleteFileIfExists(url.path)
        }

        // No need to post stickersOrPacksDidChange; caller will do that.
    }

    @objc
    public class func fetchInstalledSticker(stickerInfo: StickerInfo,
                                            transaction: SDSAnyReadTransaction) -> InstalledSticker? {

        let uniqueId = InstalledSticker.uniqueId(for: stickerInfo)

        return InstalledSticker.anyFetch(uniqueId: uniqueId, transaction: transaction)
    }

    @objc
    public class func installSticker(stickerInfo: StickerInfo,
                                     stickerData: Data,
                                     emojiString: String?,
                                     completion: (() -> Void)? = nil) {
        assert(stickerData.count > 0)

        var hasInstalledSticker = false
        databaseStorage.read { (transaction) in
            hasInstalledSticker = nil != fetchInstalledSticker(stickerInfo: stickerInfo, transaction: transaction)
        }
        if hasInstalledSticker {
            // Sticker already installed, skip.
            return
        }

        Logger.verbose("Installing sticker: \(stickerInfo).")

        DispatchQueue.global().async {
            let url = stickerUrl(stickerInfo: stickerInfo)
            do {
                try stickerData.write(to: url, options: .atomic)
            } catch let error as NSError {
                owsFailDebug("File write failed: \(error)")
                return
            }

            let installedSticker = InstalledSticker(info: stickerInfo, emojiString: emojiString)
            databaseStorage.write { (transaction) in
                installedSticker.anyInsert(transaction: transaction)

                #if DEBUG
                guard self.isStickerInstalled(stickerInfo: stickerInfo, transaction: transaction) else {
                    owsFailDebug("Skipping redundant sticker install.")
                    return
                }
                if nil == self.filepathForInstalledSticker(stickerInfo: stickerInfo, transaction: transaction) {
                    owsFailDebug("Missing sticker data for installed sticker.")
                }
                #endif

                self.addStickerToEmojiMap(installedSticker, transaction: transaction)
            }

            if let completion = completion {
                completion()
            }
        }

        NotificationCenter.default.postNotificationNameAsync(stickersOrPacksDidChange, object: nil)
    }

    private class func tryToDownloadAndInstallSticker(stickerPack: StickerPack,
                                                      item: StickerPackItem,
                                                      transaction: SDSAnyReadTransaction) -> Promise<Void> {
        let stickerInfo: StickerInfo = item.stickerInfo(with: stickerPack)
        let emojiString = item.emojiString

        guard !self.isStickerInstalled(stickerInfo: stickerInfo, transaction: transaction) else {
            Logger.verbose("Skipping redundant sticker install \(stickerInfo).")
            return Promise.value(())
        }

        return tryToDownloadSticker(stickerPack: stickerPack, stickerInfo: stickerInfo)
            .done(on: DispatchQueue.global()) { (stickerData) in
                self.installSticker(stickerInfo: stickerInfo, stickerData: stickerData, emojiString: emojiString)
            }
    }

    // This method is public so that we can download "transient" (uninstalled) stickers.
    public class func tryToDownloadSticker(stickerPack: StickerPack,
                                           stickerInfo: StickerInfo) -> Promise<Data> {
        let (promise, resolver) = Promise<Data>.pending()
        let operation = DownloadStickerOperation(stickerInfo: stickerInfo,
                                                 success: resolver.fulfill,
                                                 failure: resolver.reject)
        operationQueue.addOperation(operation)
        return promise
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
    // This cache shoud only be accessed on cacheQueue.
    private var suggestedStickersCache = NSCache<NSString, NSArray>()

    // We clear the cache every time we install or uninstall a sticker.
    private func clearSuggestedStickersCache() {
        StickerManager.cacheQueue.sync {
            self.suggestedStickersCache.removeAllObjects()
        }
    }

    @objc
    public func suggestedStickers(forTextInput textInput: String) -> [InstalledSticker] {
        return StickerManager.cacheQueue.sync {
            if let suggestions = suggestedStickersCache.object(forKey: textInput as NSString) as? [InstalledSticker] {
                return suggestions
            }

            let suggestions = StickerManager.suggestedStickers(forTextInput: textInput)
            suggestedStickersCache.setObject(suggestions as NSArray, forKey: textInput as NSString)
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
                                                           installMode: installMode)
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

    private static let kRecentStickersKey = "recentStickers"
    private static let kRecentStickersMaxCount: Int = 25

    @objc
    public class func stickerWasSent(_ stickerInfo: StickerInfo,
                                     transaction: SDSAnyWriteTransaction) {
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
            guard let sticker = InstalledSticker.anyFetch(uniqueId: key, transaction: transaction) else {
                owsFailDebug("Couldn't fetch sticker")
                continue
            }
            #if DEBUG
            if nil == self.filepathForInstalledSticker(stickerInfo: sticker.info, transaction: transaction) {
                owsFailDebug("Missing sticker data for installed sticker.")
            }
            #endif
            result.append(sticker.info)
        }
        return result
    }

    // MARK: - Auto-Enable

    private let kHasReceivedStickersKey = "hasReceivedStickersKey"
    // This property should only be accessed on serialQueue.
    private var isStickerSendEnabledCached = false

    @objc
    public func setHasUsedStickers(transaction: SDSAnyWriteTransaction) {
        var shouldSet = false
        StickerManager.serialQueue.sync {
            guard !self.isStickerSendEnabledCached else {
                return
            }
            self.isStickerSendEnabledCached = true
            shouldSet = true
        }
        guard shouldSet else {
            return
        }

        StickerManager.store.setBool(true, key: kHasReceivedStickersKey, transaction: transaction)

        NotificationCenter.default.postNotificationNameAsync(StickerManager.isStickerSendEnabledDidChange, object: nil)
    }

    @objc
    public var isStickerSendEnabled: Bool {
        if FeatureFlags.stickerSend {
            return true
        }
        guard FeatureFlags.stickerAutoEnable else {
            return false
        }
        return StickerManager.serialQueue.sync {
            return isStickerSendEnabledCached
        }
    }

    private func warmIsStickerSendEnabled() {
        let value = databaseStorage.readReturningResult { transaction in
            return StickerManager.store.getBool(self.kHasReceivedStickersKey, defaultValue: false, transaction: transaction)
        }

        StickerManager.serialQueue.sync {
            isStickerSendEnabledCached = value
        }
    }

    // MARK: - Tooltips

    @objc
    public enum TooltipState: UInt {
        case unknown = 1
        case shouldShowTooltip = 2
        case hasShownTooltip = 3
    }

    private let kShouldShowTooltipKey = "shouldShowTooltip"
    // This property should only be accessed on serialQueue.
    private var tooltipState = TooltipState.unknown

    private func stickerPackWasInstalled(transaction: SDSAnyWriteTransaction) {
        setTooltipState(.shouldShowTooltip, transaction: transaction)
    }

    @objc
    public func stickerTooltipWasShown(transaction: SDSAnyWriteTransaction) {
        setTooltipState(.hasShownTooltip, transaction: transaction)
    }

    @objc
    public func setTooltipState(_ value: TooltipState, transaction: SDSAnyWriteTransaction) {
        var shouldSet = false
        StickerManager.serialQueue.sync {
            // Don't "downgrade" this state; only raise to higher values.
            guard self.tooltipState.rawValue < value.rawValue else {
                return
            }
            self.tooltipState = value
            shouldSet = true
        }
        guard shouldSet else {
            return
        }

        StickerManager.store.setUInt(value.rawValue, key: kShouldShowTooltipKey, transaction: transaction)
    }

    @objc
    public var shouldShowStickerTooltip: Bool {
        guard isStickerSendEnabled else {
            return false
        }
        return StickerManager.serialQueue.sync {
            return self.tooltipState == .shouldShowTooltip
        }
    }

    private func warmTooltipState() {
        let value = databaseStorage.readReturningResult { transaction in
            return StickerManager.store.getUInt(self.kShouldShowTooltipKey, defaultValue: TooltipState.unknown.rawValue, transaction: transaction)
        }

        StickerManager.serialQueue.sync {
            if let tooltipState = TooltipState(rawValue: value) {
                self.tooltipState = tooltipState
            }
        }
    }

    // MARK: - Misc.

    // Data might be a sticker or a sticker pack manifest.
    public class func decrypt(ciphertext: Data,
                              packKey: Data) throws -> Data {
        guard packKey.count == packKeyLength else {
            owsFailDebug("Invalid pack key length: \(packKey.count).")
            throw StickerError.invalidInput
        }
        guard let stickerKeyInfo: Data = "Sticker Pack".data(using: .utf8) else {
            owsFailDebug("Couldn't convert info data.")
            throw StickerError.assertionFailure
        }
        let stickerSalt = Data(repeating: 0, count: 32)
        let stickerKeyLength: Int32 = 64
        let stickerKey =
            try HKDFKit.deriveKey(packKey, info: stickerKeyInfo, salt: stickerSalt, outputSize: stickerKeyLength)
        return try Cryptography.decryptStickerData(ciphertext, withKey: stickerKey)
    }

    private class func ensureAllStickerDownloadsAsync() {
        DispatchQueue.global().async {
            databaseStorage.read { (transaction) in
                for stickerPack in self.allStickerPacks(transaction: transaction) {
                    ensureDownloads(forStickerPack: stickerPack, transaction: transaction).retainUntilComplete()
                }
            }
        }
    }

    public class func ensureDownloadsAsync(forStickerPack stickerPack: StickerPack) -> Promise<Void> {
        let (promise, resolver) = Promise<Void>.pending()
        DispatchQueue.global().async {
            databaseStorage.read { (transaction) in
                ensureDownloads(forStickerPack: stickerPack, transaction: transaction)
                .done {
                    resolver.fulfill(())
                }.catch { (error) in
                    resolver.reject(error)
            }.retainUntilComplete()
            }
        }
        return promise
    }

    private class func ensureDownloads(forStickerPack stickerPack: StickerPack, transaction: SDSAnyReadTransaction) -> Promise<Void> {
        // TODO: As an optimization, we could flag packs as "complete" if we know all
        // of their stickers are installed.

        // Install the covers for available sticker packs.
        let onlyInstallCover = !stickerPack.isInstalled
        return installStickerPackContents(stickerPack: stickerPack, transaction: transaction, onlyInstallCover: onlyInstallCover)
    }

    private class func cleanupOrphans() {
        DispatchQueue.global().async {
            databaseStorage.write { (transaction) in
                var stickerPackMap = [String: StickerPack]()
                for stickerPack in StickerPack.anyFetchAll(transaction: transaction) {
                    stickerPackMap[stickerPack.info.asKey()] = stickerPack
                }

                // Cull any orphan packs.
                let savedStickerPacks = Array(stickerPackMap.values)
                for stickerPack in savedStickerPacks {
                    let isDefaultStickerPack = self.isDefaultStickerPack(stickerPack.info)
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
                    owsFailDebug("Removing \(stickersToUninstall.count) orphan stickers.")
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

        let message = OWSStickerPackSyncMessage(thread: thread, packs: packs, operationType: operationType)
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
                                            installMode: .install)
        case .remove:
            uninstallStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction)
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
                                     transaction: transaction)
                stickerPack.anyRemove(transaction: transaction)
            }
        }
    }

    @objc
    public class func tryToInstallAllAvailableStickerPacks() {
        databaseStorage.write { (transaction) in
            for stickerPack in self.availableStickerPacks(transaction: transaction) {
                self.installStickerPack(stickerPack: stickerPack, transaction: transaction)
            }
        }

        tryToDownloadDefaultStickerPacks(shouldInstall: true)
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
        if let storedValue = getObject(key, transaction: transaction) as? [String] {
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
        if let storedValue = getObject(key, transaction: transaction) as? [String] {
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
        guard let object = self.getObject(key, transaction: transaction) else {
            return []
        }
        guard let stringSet = object as? [String] else {
            owsFailDebug("Value has unexpected type \(type(of: object)).")
            return []
        }
        return stringSet
    }
}
