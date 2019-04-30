//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import HKDFKit

// TODO: Determine how views can be notified of sticker downloads.
@objc
public class StickerManager: NSObject {

    private class var shared: StickerManager {
        return SSKEnvironment.shared.stickerManager
    }

    // MARK: - Constants

    @objc
    public static let packIdLength: UInt = 16

    @objc
    public static let packKeyLength: UInt = 32

    // MARK: - Notifications

    @objc
    public static let StickersOrPacksDidChange = Notification.Name("StickersOrPacksDidChange")

    // MARK: - Dependencies

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

    // MARK: - Initializers

    @objc
    public override init() {
        super.init()

        // Resume sticker and sticker pack downloads when app is ready.
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            self.refreshAvailableStickerPacks()

            StickerManager.ensureAllStickerDownloadsAsync()
        }
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
        var result = [StickerPack]()
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            StickerPack.enumerateCollectionObjects(with: ydbTransaction) { (object, _) in
                guard let model = object as? StickerPack else {
                    owsFailDebug("unexpected object: \(type(of: object))")
                    return
                }
                result.append(model)
            }
        case .grdbRead(let grdbTransaction):
            do {
                result += try StickerPack.grdbFetchCursor(transaction: grdbTransaction).all()
            } catch let error as NSError {
                owsFailDebug("Couldn't fetch models: \(error)")
            }
        }
        return result
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

            sendStickerSyncMessage(operationType: .remove,
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

        sendStickerSyncMessage(operationType: .remove,
                               packs: [stickerPack.info],
                               transaction: transaction)

        NotificationCenter.default.postNotificationNameAsync(StickersOrPacksDidChange, object: nil)
    }

    @objc
    public class func fetchStickerPack(stickerPackInfo: StickerPackInfo,
                                       transaction: SDSAnyReadTransaction) -> StickerPack? {

        let uniqueId = StickerPack.uniqueId(for: stickerPackInfo)

        return StickerPack.anyFetch(uniqueId: uniqueId, transaction: transaction)
    }

    @objc
    public class func tryToDownloadAndSaveStickerPack(stickerPackInfo: StickerPackInfo,
                                                      shouldInstall: Bool = false) {

        let operation = DownloadStickerPackOperation(stickerPackInfo: stickerPackInfo,
                                                     success: { (manifestData) in
                                                        // saveStickerPack is expensive, do async.
                                                        DispatchQueue.global().async {
                                                            do {
                                                                try self.saveStickerPack(stickerPackInfo: stickerPackInfo,
                                                                                         manifestData: manifestData,
                                                                                         shouldInstall: shouldInstall)
                                                            } catch let error as NSError {
                                                                owsFailDebug("Couldn't save sticker pack: \(error)")
                                                                return
                                                            }
                                                        }
        },
                                                     failure: { (_) in
                                                        // Do nothing.
        })
        operationQueue.addOperation(operation)
    }

    private class func parseOptionalString(_ value: String?) -> String? {
        guard let value = value?.ows_stripped(), value.count > 0 else {
            return nil
        }
        return value
    }

    private class func parsePackItem(_ proto: SSKProtoPackSticker?) -> StickerPackItem? {
        guard let proto = proto else {
            return nil
        }
        let stickerId = proto.id
        let emojiString = parseOptionalString(proto.emoji) ?? ""
        return StickerPackItem(stickerId: stickerId, emojiString: emojiString)
    }

    // This method tries to parse a downloaded manifest.
    // If valid, we save the pack.
    private class func saveStickerPack(stickerPackInfo: StickerPackInfo,
                                       manifestData: Data,
                                       shouldInstall: Bool = false) throws {
        assert(manifestData.count > 0)

        let manifestProto: SSKProtoPack
        do {
            manifestProto = try SSKProtoPack.parseData(manifestData)
        } catch let error as NSError {
            owsFailDebug("Couldn't parse protos: \(error)")
            throw StickerError.invalidInput
        }
        let title = parseOptionalString(manifestProto.title)
        let author = parseOptionalString(manifestProto.author)
        let manifestCover = parsePackItem(manifestProto.cover)
        var items = [StickerPackItem]()
        for stickerProto in manifestProto.stickers {
            if let item = parsePackItem(stickerProto) {
                items.append(item)
            }
        }
        guard let firstItem = items.first else {
            owsFailDebug("Invalid manifest, no stickers")
            throw StickerError.invalidInput
        }
        let cover = manifestCover ?? firstItem

        let stickerPack = StickerPack(info: stickerPackInfo, title: title, author: author, cover: cover, stickers: items)
        databaseStorage.writeSwallowingErrors { (transaction) in
            let oldCopy = fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction)

            // Preserve old mutable state.
            if let oldCopy = oldCopy {
                stickerPack.update(withIsInstalled: oldCopy.isInstalled, transaction: transaction)
            } else {
                stickerPack.anySave(transaction: transaction)
            }

            sendStickerSyncMessage(operationType: .install,
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
        tryToDownloadAndInstallSticker(stickerPack: stickerPack, item: stickerPack.cover)

        guard !onlyInstallCover else {
            return
        }

        // The stickers.
        for item in stickerPack.items {
            tryToDownloadAndInstallSticker(stickerPack: stickerPack, item: item)
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

    // This is only intended for use while debugging.
    #if DEBUG
    @objc
    public class func tryToInstallAllAvailableStickerPacks() {
        databaseStorage.writeSwallowingErrors { (transaction) in
            for stickerPack in self.availableStickerPacks(transaction: transaction) {
                self.installStickerPack(stickerPack: stickerPack, transaction: transaction)
            }
        }

        shared.refreshAvailableStickerPacks(shouldInstall: true)
    }
    #endif

    @objc
    public func refreshAvailableStickerPacks() {
        refreshAvailableStickerPacks(shouldInstall: false)
    }

    private func refreshAvailableStickerPacks(shouldInstall: Bool) {
        let defaultStickerPackMap = self.defaultStickerPackMap.values

        var stickerPacksToDownload = [StickerPackInfo]()
        StickerManager.databaseStorage.readSwallowingErrors { (transaction) in
            for stickerPackInfo in defaultStickerPackMap {
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

    @objc
    public class func installedStickers(forStickerPack stickerPack: StickerPack) -> [StickerInfo] {
        var result = [StickerInfo]()
        databaseStorage.readSwallowingErrors { (transaction) in
            for stickerInfo in stickerPack.stickerInfos {
                if isStickerInstalled(stickerInfo: stickerInfo, transaction: transaction) {
                    result.append(stickerInfo)
                }
            }
        }
        return result
    }

    // MARK: - Stickers

    @objc
    public class func filepathForInstalledSticker(stickerInfo: StickerInfo) -> String? {

        if isStickerInstalled(stickerInfo: stickerInfo) {
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
            }
        }

        NotificationCenter.default.postNotificationNameAsync(StickersOrPacksDidChange, object: nil)
    }

    private class func tryToDownloadAndInstallSticker(stickerPack: StickerPack,
                                                      item: StickerPackItem) {

        let stickerInfo: StickerInfo = item.stickerInfo(with: stickerPack)
        let emojiString = item.emojiString

        let operation = DownloadStickerOperation(stickerInfo: stickerInfo,
                                                 success: { (stickerData) in
                                                    self.installSticker(stickerInfo: stickerInfo, stickerData: stickerData, emojiString: emojiString)
        },
                                                 failure: { (_) in
                                                    // Do nothing.
        })
        operationQueue.addOperation(operation)
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
    private class func sendStickerSyncMessage(operationType: StickerPackOperationType,
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
}
