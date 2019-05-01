//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import HKDFKit

// TODO: Determine how views can be notified of sticker downloads.
@objc
public class StickerManager: NSObject {

    // MARK: - Constants

    @objc
    public static let packIdLength: UInt = 16

    @objc
    public static let packKeyLength: UInt = 32

    // MARK: - Notifications

    @objc
    public static let StickersOrPacksDidChange = Notification.Name("StickersOrPacksDidChange")
    public static let RecentStickersDidChange = Notification.Name("RecentStickersDidChange")

    // MARK: - Dependencies

    private class var shared: StickerManager {
        return SSKEnvironment.shared.stickerManager
    }

    private static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private static var primaryStorage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }

    private static var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    // MARK: - Properties

    private static let operationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "org.signal.StickerManager"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    private static let store = SDSKeyValueStore(collection: "StickerManager")

    // MARK: - Initializers

    @objc
    public override init() {
        super.init()

        // Resume sticker and sticker pack downloads when app is ready.
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            StickerManager.refreshContents()
        }
    }

    // The sticker manager is responsible for downloading more than one kind
    // of content; those downloads can fail.  Therefore the sticker manager
    // retries those downloads, sometimes in response to user activity.
    @objc
    public class func refreshContents() {
        // Try to download the manifests for "default" sticker packs.
        shared.tryToDownloadDefaultStickerPacks(shouldInstall: false)

        // Try to download the manifests for "known" sticker packs.
        tryToDownloadKnownStickerPacks()

        // Try to download the stickers for "installed" sticker packs.
        ensureAllStickerDownloadsAsync()
    }

    // MARK: - Paths

    // TODO: Clean up sticker data on orphan data cleaner.
    // TODO: Clean up sticker data if user deletes all user data.
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
        databaseStorage.readSwallowingErrors { (transaction) in
            result += allStickerPacks(transaction: transaction)
        }
        return result
    }

    // TODO: Handle sorting.
    @objc
    public class func allStickerPacks(transaction: SDSAnyReadTransaction) -> [StickerPack] {
        return StickerPack.anyFetchAll(transaction: transaction)
    }

    // TODO: Handle sorting.
    @objc
    public class func installedStickerPacks() -> [StickerPack] {
        return allStickerPacks().filter {
            $0.isInstalled
        }
    }

    // TODO: Handle sorting.
    @objc
    public class func availableStickerPacks() -> [StickerPack] {
        return allStickerPacks().filter {
            !$0.isInstalled
        }
    }

    // TODO: Handle sorting.
    private class func availableStickerPacks(transaction: SDSAnyReadTransaction) -> [StickerPack] {
        return allStickerPacks(transaction: transaction).filter {
            !$0.isInstalled
        }
    }

    @objc
    public class func isStickerPackSaved(stickerPackInfo: StickerPackInfo) -> Bool {
        var result = false
        databaseStorage.readSwallowingErrors { (transaction) in
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
    public class func uninstallStickerPack(stickerPackInfo: StickerPackInfo) {

        var completions = [CleanupCompletion]()
        databaseStorage.writeSwallowingErrors { (transaction) in
            guard let stickerPack = fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction) else {
                Logger.info("Skipping uninstall; not installed.")
                return
            }
            stickerPack.update(withIsInstalled: false, transaction: transaction)

            // Uninstall the cover and stickers - but retain the cover
            // if this is a default sticker pack.
            if !shared.isDefaultStickerPack(stickerPackInfo: stickerPack.info) {
                if let completion = uninstallSticker(stickerInfo: stickerPack.coverInfo,
                                                     transaction: transaction) {
                    completions.append(completion)
                }
            }

            for stickerInfo in stickerPack.stickerInfos {
                if let completion = uninstallSticker(stickerInfo: stickerInfo,
                                                     transaction: transaction) {
                    completions.append(completion)
                }
            }

            enqueueStickerSyncMessage(operationType: .remove,
                                   packs: [stickerPackInfo],
                                   transaction: transaction)
        }

        for completion in completions {
            completion()
        }

        NotificationCenter.default.postNotificationNameAsync(StickersOrPacksDidChange, object: nil)
    }

    @objc
    public class func installStickerPack(stickerPack: StickerPack) {
        databaseStorage.writeSwallowingErrors { (transaction) in
            self.installStickerPack(stickerPack: stickerPack,
                                    transaction: transaction)
        }
    }

    private class func installStickerPack(stickerPack: StickerPack,
                                          transaction: SDSAnyWriteTransaction) {

        if stickerPack.isInstalled {
            return
        }

        stickerPack.update(withIsInstalled: true, transaction: transaction)

        installStickerPackContents(stickerPack: stickerPack, transaction: transaction)

        enqueueStickerSyncMessage(operationType: .remove,
                               packs: [stickerPack.info],
                               transaction: transaction)

        NotificationCenter.default.postNotificationNameAsync(StickersOrPacksDidChange, object: nil)
    }

    @objc
    public class func fetchStickerPack(stickerPackInfo: StickerPackInfo) -> StickerPack? {
        var result: StickerPack?
        databaseStorage.readSwallowingErrors { (transaction) in
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
                                                       shouldInstall: Bool = false) {
        return tryToDownloadStickerPack(stickerPackInfo: stickerPackInfo)
            .done(on: DispatchQueue.global()) { (stickerPack) in
                self.saveStickerPack(stickerPack: stickerPack,
                                     shouldInstall: shouldInstall)
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

    public class func saveStickerPack(stickerPack: StickerPack,
                                      shouldInstall: Bool = false) {

        databaseStorage.writeSwallowingErrors { (transaction) in
            let oldCopy = fetchStickerPack(stickerPackInfo: stickerPack.info, transaction: transaction)

            // Preserve old mutable state.
            if let oldCopy = oldCopy {
                stickerPack.update(withIsInstalled: oldCopy.isInstalled, transaction: transaction)
            } else {
                stickerPack.anySave(transaction: transaction)
            }

            enqueueStickerSyncMessage(operationType: .install,
                                   packs: [stickerPack.info],
                                   transaction: transaction)

            // If the pack is already installed, make sure all stickers are installed.
            if stickerPack.isInstalled {
                installStickerPackContents(stickerPack: stickerPack, transaction: transaction)
            } else if shouldInstall {
                self.installStickerPack(stickerPack: stickerPack, transaction: transaction)
            }
        }

        NotificationCenter.default.postNotificationNameAsync(StickersOrPacksDidChange, object: nil)
    }

    private class func installStickerPackContents(stickerPack: StickerPack,
                                                  transaction: SDSAnyReadTransaction,
                                                  onlyInstallCover: Bool = false) {
        // Note: It's safe to kick off downloads of stickers that are already installed.

        // The cover.
        tryToDownloadAndInstallSticker(stickerPack: stickerPack, item: stickerPack.cover, transaction: transaction)

        guard !onlyInstallCover else {
            return
        }

        // The stickers.
        for item in stickerPack.items {
            tryToDownloadAndInstallSticker(stickerPack: stickerPack, item: item, transaction: transaction)
        }
    }

    // A mapping of sticker pack keys to sticker pack info.
    private var defaultStickerPackMap: [String: StickerPackInfo] = StickerManager.parseDefaultStickerPacks()

    private class func parseDefaultStickerPacks() -> [String: StickerPackInfo] {
        guard let packId = Data.data(fromHex: "0123456789abcdef0123456789abcdef") else {
            owsFailDebug("Invalid packId")
            return [:]
        }
        assert(packId.count == StickerManager.packIdLength)
        guard let packKey = Data.data(fromHex: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789") else {
            owsFailDebug("Invalid packKey")
            return [:]
        }
        assert(packKey.count == StickerManager.packKeyLength)

        let samplePack = StickerPackInfo(packId: packId, packKey: packKey)
        return [samplePack.asKey(): samplePack]
    }

    private func isDefaultStickerPack(stickerPackInfo: StickerPackInfo) -> Bool {
        return nil != defaultStickerPackMap[stickerPackInfo.asKey()]
    }

    private func tryToDownloadDefaultStickerPacks(shouldInstall: Bool) {
        let stickerPacks = Array(defaultStickerPackMap.values)
        StickerManager.tryToDownloadStickerPacks(stickerPacks: stickerPacks,
                                                 shouldInstall: shouldInstall)
    }

    @objc
    public class func installedStickers(forStickerPack stickerPack: StickerPack) -> [StickerInfo] {
        var result = [StickerInfo]()
        databaseStorage.readSwallowingErrors { (transaction) in
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

    // MARK: - Stickers

    @objc
    public class func filepathForInstalledSticker(stickerInfo: StickerInfo) -> String? {
        var result: String?
        databaseStorage.readSwallowingErrors { (transaction) in
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
    public class func isStickerInstalled(stickerInfo: StickerInfo) -> Bool {
        var result = false
        databaseStorage.readSwallowingErrors { (transaction) in
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

    private typealias CleanupCompletion = () -> Void

    // Returns a completion handler that cleans up the sticker data on disk.
    // We want to do these deletions after the transaction is complete
    // so that: a) other transactions aren't blocked. b) we only delete these
    // files if the transaction is committed, ensuring the invariant that
    // all installed stickers have a corresponding sticker data file.
    private class func uninstallSticker(stickerInfo: StickerInfo,
                                        transaction: SDSAnyWriteTransaction) -> CleanupCompletion? {

        guard let installedSticker = fetchInstalledSticker(stickerInfo: stickerInfo, transaction: transaction) else {
            Logger.info("Skipping uninstall; not installed.")
            return nil
        }
        installedSticker.anyRemove(transaction: transaction)

        removeFromRecentStickers(stickerInfo,
                                 transaction: transaction)

        return {
            let url = stickerUrl(stickerInfo: stickerInfo)
            OWSFileSystem.deleteFileIfExists(url.path)
        }

        // No need to post StickersOrPacksDidChange; caller will do that.
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
                                     emojiString: String?) {
        assert(stickerData.count > 0)

        var hasInstalledSticker = false
        databaseStorage.readSwallowingErrors { (transaction) in
            hasInstalledSticker = nil != fetchInstalledSticker(stickerInfo: stickerInfo, transaction: transaction)
        }
        if hasInstalledSticker {
            // Sticker already installed, skip.
            return
        }

        DispatchQueue.global().async {
            let url = stickerUrl(stickerInfo: stickerInfo)
            do {
                try stickerData.write(to: url, options: .atomic)
            } catch let error as NSError {
                owsFailDebug("File write failed: \(error)")
                return
            }

            let installedSticker = InstalledSticker(info: stickerInfo, emojiString: emojiString)
            databaseStorage.writeSwallowingErrors { (transaction) in
                installedSticker.anySave(transaction: transaction)

                #if DEBUG
                guard self.isStickerInstalled(stickerInfo: stickerInfo, transaction: transaction) else {
                    owsFailDebug("Skipping redundant sticker install.")
                    return
                }
                if nil == self.filepathForInstalledSticker(stickerInfo: stickerInfo, transaction: transaction) {
                    owsFailDebug("Missing sticker data for installed sticker.")
                }
                #endif
            }
        }

        NotificationCenter.default.postNotificationNameAsync(StickersOrPacksDidChange, object: nil)
    }

    private class func tryToDownloadAndInstallSticker(stickerPack: StickerPack,
                                                      item: StickerPackItem,
                                                      transaction: SDSAnyReadTransaction) {
        let stickerInfo: StickerInfo = item.stickerInfo(with: stickerPack)
        let emojiString = item.emojiString

        guard !self.isStickerInstalled(stickerInfo: stickerInfo, transaction: transaction) else {
            Logger.verbose("Skipping redundant sticker install.")
            return
        }

        tryToDownloadSticker(stickerPack: stickerPack, stickerInfo: stickerInfo)
            .done(on: DispatchQueue.global()) { (stickerData) in
                self.installSticker(stickerInfo: stickerInfo, stickerData: stickerData, emojiString: emojiString)
            }.retainUntilComplete()
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

    @objc
    public class func emojiForSticker(stickerInfo: StickerInfo,
                                      transaction: SDSAnyReadTransaction) -> String? {

        let uniqueId = InstalledSticker.uniqueId(for: stickerInfo)

        guard let sticker = InstalledSticker.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
            return nil
        }
        guard let emojiString = sticker.emojiString else {
            return nil
        }
        return firstEmoji(inEmojiString: emojiString)
    }

    @objc
    public class func firstEmoji(inEmojiString emojiString: String?) -> String? {
        guard let emojiString = emojiString else {
            return nil
        }

        return emojiString.substring(to: 1)
    }

    // MARK: - Known Sticker Packs

    // TODO: We may want to cull these in the orphan data cleaner.
    @objc
    public class func addKnownStickerInfo(_ stickerInfo: StickerInfo,
                                          transaction: SDSAnyWriteTransaction) {
        let packInfo = stickerInfo.packInfo
        let pack: KnownStickerPack
        let uniqueId = KnownStickerPack.uniqueId(for: packInfo)
        if let existing = KnownStickerPack.anyFetch(uniqueId: uniqueId, transaction: transaction) {
            pack = existing
        } else {
            pack = KnownStickerPack(info: packInfo)

            DispatchQueue.global().async {
                self.tryToDownloadStickerPacks(stickerPacks: [packInfo], shouldInstall: false)
            }
        }
        pack.referenceCount += 1
        pack.anySave(transaction: transaction)
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
        pack.referenceCount -= 1
        if pack.referenceCount < 1 {
            pack.anyRemove(transaction: transaction)

            // Clean up the pack metadata unless either:
            //
            // * It's a default sticker pack.
            // * The pack has been installed.
            if !self.shared.isDefaultStickerPack(stickerPackInfo: packInfo),
                let stickerPack = StickerPack.anyFetch(uniqueId: StickerPack.uniqueId(for: packInfo), transaction: transaction),
                !stickerPack.isInstalled {
                self.uninstallStickerPack(stickerPackInfo: packInfo)
            }
        } else {
            pack.anySave(transaction: transaction)
        }
    }

    @objc
    public class func allKnownStickerPacks() -> [StickerPackInfo] {
        var result = [StickerPackInfo]()
        databaseStorage.readSwallowingErrors { (transaction) in
            KnownStickerPack.anyVisitAll(transaction: transaction) { (knownStickerPack) in
                result.append(knownStickerPack.info)
                return true
            }
        }
        return result
    }

    private class func tryToDownloadKnownStickerPacks() {
        let stickerPacks = allKnownStickerPacks()
        tryToDownloadStickerPacks(stickerPacks: stickerPacks,
                                  shouldInstall: false)
    }

    private class func tryToDownloadStickerPacks(stickerPacks: [StickerPackInfo],
                                                 shouldInstall: Bool) {

        var stickerPacksToDownload = [StickerPackInfo]()
        StickerManager.databaseStorage.readSwallowingErrors { (transaction) in
            for stickerPackInfo in stickerPacks {
                if !StickerManager.isStickerPackSaved(stickerPackInfo: stickerPackInfo, transaction: transaction) {
                    stickerPacksToDownload.append(stickerPackInfo)
                }
            }
        }

        for stickerPackInfo in stickerPacksToDownload {
            StickerManager.tryToDownloadAndSaveStickerPack(stickerPackInfo: stickerPackInfo,
                                                           shouldInstall: shouldInstall)
        }
    }

    // MARK: - Recents

    private static let kRecentStickersKey = "recentStickers"

    @objc
    public class func stickerWasSent(_ stickerInfo: StickerInfo,
                                     transaction: SDSAnyWriteTransaction) {
        let key = stickerInfo.asKey()
        // Prepend key to ensure descending order of recency.
        var recentStickerKeys = [key]
        if let storedValue = store.getObject(kRecentStickersKey) as? [String] {
            recentStickerKeys += storedValue.filter {
                $0 != key
            }
        }
        store.setObject(recentStickerKeys, key: kRecentStickersKey, transaction: transaction)

        NotificationCenter.default.postNotificationNameAsync(RecentStickersDidChange, object: nil)
    }

    private class func removeFromRecentStickers(_ stickerInfo: StickerInfo,
                                                transaction: SDSAnyWriteTransaction) {
        let key = stickerInfo.asKey()
        var recentStickerKeys = [String]()
        if let storedValue = store.getObject(kRecentStickersKey) as? [String] {
            guard storedValue.contains(key) else {
                // No work to do.
                return
            }
            recentStickerKeys += storedValue.filter {
                $0 != key
            }
        }
        store.setObject(recentStickerKeys, key: kRecentStickersKey, transaction: transaction)

        NotificationCenter.default.postNotificationNameAsync(RecentStickersDidChange, object: nil)
    }

    // Returned in descending order of recency.
    //
    // Only returns installed stickers.
    @objc
    public class func recentStickers() -> [StickerInfo] {
        var result = [StickerInfo]()
        databaseStorage.readSwallowingErrors { (transaction) in
            result = self.recentStickers(transaction: transaction)
        }
        return result
    }

    // Returned in descending order of recency.
    //
    // Only returns installed stickers.
    private class func recentStickers(transaction: SDSAnyReadTransaction) -> [StickerInfo] {
        var result = [StickerInfo]()
        if let keys = store.getObject(kRecentStickersKey, transaction: transaction) as? [String] {
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
        }
        return result
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
            databaseStorage.readSwallowingErrors { (transaction) in
                for stickerPack in self.allStickerPacks(transaction: transaction) {
                    ensureDownloads(forStickerPack: stickerPack, transaction: transaction)
                }
            }
        }
    }

    @objc
    public class func ensureDownloadsAsync(forStickerPack stickerPack: StickerPack) {
        DispatchQueue.global().async {
            databaseStorage.readSwallowingErrors { (transaction) in
                ensureDownloads(forStickerPack: stickerPack, transaction: transaction)
            }
        }
    }

    private class func ensureDownloads(forStickerPack stickerPack: StickerPack, transaction: SDSAnyReadTransaction) {
        // TODO: As an optimization, we could flag packs as "complete" if we know all
        // of their stickers are installed.

        // Install the covers for available sticker packs.
        let onlyInstallCover = !stickerPack.isInstalled
        installStickerPackContents(stickerPack: stickerPack, transaction: transaction, onlyInstallCover: onlyInstallCover)
    }

    // TODO: We could also send a sticker sync message after we link a new device.
    private class func enqueueStickerSyncMessage(operationType: StickerPackOperationType,
                                              packs: [StickerPackInfo],
                                              transaction: SDSAnyWriteTransaction) {
        let message = OWSStickerPackSyncMessage(packs: packs, operationType: operationType)

        switch transaction.writeTransaction {
        case .yapWrite(let ydbTransaction):
            self.messageSenderJobQueue.add(message: message, transaction: ydbTransaction)
        case .grdbWrite:
            // GRDB TODO: Support any transactions.
//            owsFailDebug("GRDB not yet supported.")
            break
        }
    }

    // MARK: - Debug

    // This is only intended for use while debugging.
    #if DEBUG
    @objc
    public class func uninstallAllStickerPacks() {
        var stickerPacks = [StickerPack]()
        databaseStorage.writeSwallowingErrors { (_) in
            stickerPacks = installedStickerPacks()
        }

        for stickerPack in stickerPacks {
            uninstallStickerPack(stickerPackInfo: stickerPack.info)
        }
    }

    @objc
    public class func tryToInstallAllAvailableStickerPacks() {
        databaseStorage.writeSwallowingErrors { (transaction) in
            for stickerPack in self.availableStickerPacks(transaction: transaction) {
                self.installStickerPack(stickerPack: stickerPack, transaction: transaction)
            }
        }

        shared.tryToDownloadDefaultStickerPacks(shouldInstall: true)
    }
    #endif
}
