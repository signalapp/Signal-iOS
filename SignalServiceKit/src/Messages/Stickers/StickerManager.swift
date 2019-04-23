//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

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
        // Resume sticker and sticker pack downloads when app is ready.
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            StickerManager.enqueueAllStickerDownloads()
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

    // TODO: Handle sorting.
    @objc
    public class func allStickerPacks() -> [StickerPack] {

        var result = [StickerPack]()
        databaseStorage.readSwallowingErrors { (transaction) in
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
                    return
                }
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

    @objc
    public class func isStickerPackSaved(stickerPackInfo: StickerPackInfo) -> Bool {

        var result = false
        databaseStorage.readSwallowingErrors { (transaction) in
            result = nil != fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction)
        }
        return result
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

            // TODO: I'm not sure we want to uninstall the stickers.
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

        if stickerPack.isInstalled {
            return
        }

        databaseStorage.writeSwallowingErrors { (transaction) in
            stickerPack.update(withIsInstalled: true, transaction: transaction)

            sendStickerSyncMessage(operationType: .remove,
                                   packs: [stickerPack.info],
                                   transaction: transaction)
        }

        installStickerPackContents(stickerPack: stickerPack)

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
                                                        DispatchQueue.global().async {
                                                            // saveStickerPack is expensive.
                                                            guard let stickerPack = self.saveStickerPack(stickerPackInfo: stickerPackInfo,
                                                                                                         manifestData: manifestData) else {
                                                                                                            return
                                                            }
                                                            if shouldInstall {
                                                                self.installStickerPack(stickerPack: stickerPack)
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
                                       manifestData: Data) -> StickerPack? {
        assert(manifestData.count > 0)

        let manifestProto: SSKProtoPack
        do {
            manifestProto = try SSKProtoPack.parseData(manifestData)
        } catch let error as NSError {
            owsFailDebug("Couldn't parse protos: \(error)")
            return nil
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
            return nil
        }
        let cover = manifestCover ?? firstItem

        let stickerPack = StickerPack(info: stickerPackInfo, title: title, author: author, cover: cover, stickers: items)
        databaseStorage.writeSwallowingErrors { (transaction) in
            let oldCopy = fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction)

            stickerPack.anySave(transaction: transaction)

            // Preserve old mutable state.
            if let oldCopy = oldCopy {
                stickerPack.update(withIsInstalled: oldCopy.isInstalled, transaction: transaction)
            }

            sendStickerSyncMessage(operationType: .install,
                                   packs: [stickerPack.info],
                                   transaction: transaction)
        }

        // If the pack is already installed, make sure all stickers are installed.
        if stickerPack.isInstalled {
            installStickerPackContents(stickerPack: stickerPack)
        }

        NotificationCenter.default.postNotificationNameAsync(StickersOrPacksDidChange, object: nil)

        return stickerPack
    }

    private class func installStickerPackContents(stickerPack: StickerPack) {
        // Note: It's safe to kick off downloads of stickers that are already installed.

        // The cover.
        tryToDownloadAndInstallSticker(stickerInfo: stickerPack.coverInfo)
        // The stickers.
        for stickerInfo in stickerPack.stickerInfos {
            tryToDownloadAndInstallSticker(stickerInfo: stickerInfo)
        }
    }

    //    https://cdn-staging.signal.org/stickers/0123456789abcdef0123456789abcdef/manifest.proto
    //
    //    Using key:
    //    abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789

    @objc
    public class func refreshAvailableStickerPacks() {
        // TODO: Fetch actual list from service.
        // TODO: Should this include other "encountered" packs?
        guard let packId = Data.data(fromHex: "0123456789abcdef0123456789abcdef") else {
            owsFailDebug("Invalid packId")
            return
        }
        assert(packId.count == StickerManager.packIdLength)
        guard let packKey = Data.data(fromHex: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789") else {
            owsFailDebug("Invalid packKey")
            return
        }
        assert(packKey.count == StickerManager.packKeyLength)

        let stickerPackInfos = [StickerPackInfo(packId: packId, packKey: packKey)]
        for stickerPackInfo in stickerPackInfos {
            tryToDownloadAndSaveStickerPack(stickerPackInfo: stickerPackInfo,
                                            shouldInstall: false)
        }
    }

    // MARK: - Stickers

    @objc
    public class func filepathForInstalledSticker(stickerInfo: StickerInfo) -> String? {

        if isStickerInstalled(stickerInfo: stickerInfo) {
            return stickerUrl(stickerInfo: stickerInfo).path
        } else {
            // Kick off download here on cache miss.
            tryToDownloadAndInstallSticker(stickerInfo: stickerInfo)

            return nil
        }
    }

    @objc
    public class func isStickerInstalled(stickerInfo: StickerInfo) -> Bool {

        var result = false
        databaseStorage.readSwallowingErrors { (transaction) in
            result = nil != fetchInstalledSticker(stickerInfo: stickerInfo, transaction: transaction)
        }
        return result
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
                                     stickerData: Data) {
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

            databaseStorage.writeSwallowingErrors { (transaction) in
                let installedSticker = InstalledSticker(info: stickerInfo)
                installedSticker.anySave(transaction: transaction)
            }
        }

        NotificationCenter.default.postNotificationNameAsync(StickersOrPacksDidChange, object: nil)
    }

    @objc
    public class func tryToDownloadAndInstallSticker(stickerInfo: StickerInfo) {

        let operation = DownloadStickerOperation(stickerInfo: stickerInfo,
                                                 success: { (stickerData) in
                                                    self.installSticker(stickerInfo: stickerInfo, stickerData: stickerData)
        },
                                                 failure: { (_) in
                                                    // Do nothing.
        })
        operationQueue.addOperation(operation)
    }

    // MARK: - Misc.

    // Data might be a sticker or a sticker pack manifest.
    public class func decrypt(ciphertext: Data,
                              packKey: Data) throws -> Data {

        guard let key = OWSAES256Key(data: packKey) else {
            owsFailDebug("Invalid pack key.")
            throw StickerError.invalidInput
        }

        // TODO: We might want to rename this method if we end up using it for more than
        //       profile data.
        guard let plaintext = Cryptography.decryptAESGCMProfileData(encryptedData: ciphertext, key: key) else {
            owsFailDebug("Decryption failed.")
            throw StickerError.invalidInput
        }

        return plaintext
    }

    private class func enqueueAllStickerDownloads() {
        // TODO: As an optimization, we could flag packs as "complete" if we know all
        // of their stickers are installed.

        DispatchQueue.global().async {
            var stickerPacks = [StickerPack]()
            self.databaseStorage.readSwallowingErrors { (transaction) in
                switch transaction.readTransaction {
                case .yapRead(let ydbTransaction):
                    StickerPack.enumerateCollectionObjects(with: ydbTransaction) { (object, _) in
                        guard let pack = object as? StickerPack else {
                            owsFailDebug("Unexpected object: \(type(of: object))")
                            return
                        }
                        stickerPacks.append(pack)
                    }
                case .grdbRead(let grdbTransaction):
                    let cursor = StickerPack.grdbFetchCursor(transaction: grdbTransaction)
                    do {
                        stickerPacks += try cursor.all()
                    } catch let error as NSError {
                        owsFailDebug("Couldn't load models: \(error)")
                        return
                    }
                }
            }

            for stickerPack in stickerPacks {
                installStickerPackContents(stickerPack: stickerPack)
            }
        }
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
            owsFailDebug("GRDB not yet supported.")
        }
    }
}
