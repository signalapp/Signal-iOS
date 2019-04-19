//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// TODO: Hang this singleton on SSKEnvironment.
// TODO: Maybe this could be better described as "sticker manager".
// TODO: Determine how views can be notified of sticker downloads.
@objc
public class InstalledStickers: NSObject {

    private static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private static var primaryStorage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }

    private static var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    private static let operationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "org.signal.installedStickers"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    private override init() {
        // Resume sticker and sticker pack downloads when app is ready.
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            InstalledStickers.enqueueAllStickerDownloads()
        }
    }

    // MARK: - Paths

    // TODO: Clean up sticker data on orphan data cleaner.
    // TODO: Clean up sticker data if user deletes all user data.
    @objc
    public class func cacheDirUrl() -> URL {
        var url = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
        url.appendPathComponent("InstalledStickers")
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
    public class func isStickerPackInstalled(stickerPackInfo: StickerPackInfo) -> Bool {

        var result = false
        databaseStorage.readSwallowingErrors { (transaction) in
            result = nil != fetchInstalledStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction)
        }
        return result
    }

    @objc
    public class func uninstallStickerPack(stickerPackInfo: StickerPackInfo) {

        var completions = [CleanupCompletion]()
        databaseStorage.writeSwallowingErrors { (transaction) in
            guard let installedStickerPack = fetchInstalledStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction) else {
                Logger.info("Skipping uninstall; not installed.")
                return
            }
            installedStickerPack.anyRemove(transaction: transaction)

            for stickerInfo in installedStickerPack.stickerInfos {
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
    }

    @objc
    public class func fetchInstalledStickerPack(stickerPackInfo: StickerPackInfo,
                                                transaction: SDSAnyReadTransaction) -> InstalledStickerPack? {

        let uniqueId = InstalledStickerPack.uniqueId(for: stickerPackInfo)

        return InstalledStickerPack.anyFetch(uniqueId: uniqueId, transaction: transaction)
    }

    @objc
    public class func tryToDownloadAndInstallStickerPack(stickerPackInfo: StickerPackInfo) {

        let operation = DownloadStickerPackOperation(stickerPackInfo: stickerPackInfo,
                                                     success: { (manifestData) in
                                                        DispatchQueue.global().async {
                                                            // installStickerPack is expensive.
                                                            self.installStickerPack(stickerPackInfo: stickerPackInfo,
                                                                                    manifestData: manifestData)
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

    private class func parsePackItem(_ proto: SSKProtoPackSticker?) -> InstalledStickerPackItem? {
        guard let proto = proto else {
            return nil
        }
        let stickerId = proto.id
        let emojiString = parseOptionalString(proto.emoji) ?? ""
        return InstalledStickerPackItem(stickerId: stickerId, emojiString: emojiString)
    }

    // This method tries to parse a downloaded manifest.
    // If valid, we install the pack and then kick off
    // download of its contents.
    private class func installStickerPack(stickerPackInfo: StickerPackInfo,
                                          manifestData: Data) {
        assert(manifestData.count > 0)

        var hasInstalledStickerPack = false
        databaseStorage.readSwallowingErrors { (transaction) in
            hasInstalledStickerPack = nil != fetchInstalledStickerPack(stickerPackInfo: stickerPackInfo, transaction: transaction)
        }
        if hasInstalledStickerPack {
            // Sticker pack already installed, skip.
            return
        }

        let manifestProto: SSKProtoPack
        do {
            manifestProto = try SSKProtoPack.parseData(manifestData)
        } catch let error as NSError {
            owsFailDebug("Couldn't parse protos: \(error)")
            return
        }
        let title = parseOptionalString(manifestProto.title)
        let author = parseOptionalString(manifestProto.author)
        let manifestCover = parsePackItem(manifestProto.cover)
        var items = [InstalledStickerPackItem]()
        for stickerProto in manifestProto.stickers {
            if let item = parsePackItem(stickerProto) {
                items.append(item)
            }
        }
        guard let firstItem = items.first else {
            owsFailDebug("Invalid manifest, no stickers")
            return
        }
        let cover = manifestCover ?? firstItem

        let installedStickerPack = InstalledStickerPack(info: stickerPackInfo, title: title, author: author, cover: cover, stickers: items)
        databaseStorage.writeSwallowingErrors { (transaction) in
            installedStickerPack.anySave(transaction: transaction)

            sendStickerSyncMessage(operationType: .install,
                                   packs: [installedStickerPack.info],
                                   transaction: transaction)
        }

        installStickerPackContents(installedStickerPack: installedStickerPack)
    }

    private class func installStickerPackContents(installedStickerPack: InstalledStickerPack) {
        // Note: It's safe to kick off downloads of stickers that are already installed.

        // The cover.
        tryToDownloadAndInstallSticker(stickerInfo: installedStickerPack.coverInfo)
        // The stickers.
        for stickerInfo in installedStickerPack.stickerInfos {
            tryToDownloadAndInstallSticker(stickerInfo: stickerInfo)
        }
    }

    // MARK: - Stickers

    @objc
    public class func filepathForInstalledSticker(stickerInfo: StickerInfo) -> String? {

        if isStickerInstalled(stickerInfo: stickerInfo) {
            return stickerUrl(stickerInfo: stickerInfo).path
        } else {
            // TODO: We may want to kick off download here on cache miss.

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
        DispatchQueue.global().async {
            var installedStickerPacks = [InstalledStickerPack]()
            self.databaseStorage.readSwallowingErrors { (transaction) in
                switch transaction.readTransaction {
                case .yapRead(let ydbTransaction):
                    InstalledStickerPack.enumerateCollectionObjects(with: ydbTransaction) { (object, _) in
                        guard let pack = object as? InstalledStickerPack else {
                            owsFailDebug("Unexpected object: \(type(of: object))")
                            return
                        }
                        installedStickerPacks.append(pack)
                    }
                case .grdbRead(let grdbTransaction):
                    let cursor = InstalledStickerPack.grdbFetchCursor(transaction: grdbTransaction)
                    do {
                        installedStickerPacks += try cursor.all()
                    } catch let error as NSError {
                        owsFailDebug("Couldn't load models: \(error)")
                        return
                    }
                }
            }

            for installedStickerPack in installedStickerPacks {
                installStickerPackContents(installedStickerPack: installedStickerPack)
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
