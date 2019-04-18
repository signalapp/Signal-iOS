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

    private class func stickerUrl(packId: Data,
                                  stickerId: UInt32) -> URL {
        assert(packId.count > 0)

        let uniqueId = InstalledSticker.uniqueId(forPackId: packId, stickerId: stickerId)

        var url = cacheDirUrl()
        // All stickers are .webp.
        url.appendPathComponent("\(uniqueId).webp")
        return url
    }

    // MARK: - Sticker Packs

    @objc
    public class func isStickerPackInstalled(packId: Data) -> Bool {
        assert(packId.count > 0)

        var result = false
        databaseStorage.readSwallowingErrors { (transaction) in
            result = nil != fetchInstalledStickerPack(packId: packId, transaction: transaction)
        }
        return result
    }

    @objc
    public class func fetchInstalledStickerPack(packId: Data,
                                                transaction: SDSAnyReadTransaction) -> InstalledStickerPack? {
        assert(packId.count > 0)

        let uniqueId = InstalledStickerPack.uniqueId(forPackId: packId)

        return InstalledStickerPack.anyFetch(withUniqueId: uniqueId, transaction: transaction)
    }

    @objc
    public class func tryToDownloadAndInstallStickerPack(packId: Data,
                                                         packKey: Data) {
        assert(packId.count > 0)
        assert(packKey.count > 0)

        let operation = DownloadStickerPackOperation(packId: packId,
                                                     packKey: packKey,
                                                     success: { (manifestData) in
                                                        DispatchQueue.global().async {
                                                            // installStickerPack is expensive.
                                                            self.installStickerPack(packId: packId,
                                                                                    packKey: packKey,
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
    private class func installStickerPack(packId: Data,
                                          packKey: Data,
                                          manifestData: Data) {
        assert(packId.count > 0)
        assert(packKey.count > 0)
        assert(manifestData.count > 0)

        var hasInstalledStickerPack = false
        databaseStorage.readSwallowingErrors { (transaction) in
            hasInstalledStickerPack = nil != fetchInstalledStickerPack(packId: packId, transaction: transaction)
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

        let installedStickerPack = InstalledStickerPack(packId: packId, packKey: packKey, title: title, author: author, cover: cover, stickers: items)
        databaseStorage.writeSwallowingErrors { (transaction) in
            installedStickerPack.anySave(transaction: transaction)
        }

        installStickerPackContents(installedStickerPack: installedStickerPack)
    }

    private class func installStickerPackContents(installedStickerPack: InstalledStickerPack) {
        // Note: It's safe to kick off downloads of stickers that are already installed.

        // The cover.
        tryToDownloadAndInstallSticker(packId: installedStickerPack.packId,
                                       packKey: installedStickerPack.packKey,
                                       stickerId: installedStickerPack.cover.stickerId)
        // The stickers.
        for item in installedStickerPack.stickers {
            tryToDownloadAndInstallSticker(packId: installedStickerPack.packId,
                                           packKey: installedStickerPack.packKey,
                                           stickerId: item.stickerId)
        }
    }

    // MARK: - Stickers

    @objc
    public class func filepathForInstalledSticker(packId: Data,
                                                  packKey: Data,
                                                  stickerId: UInt32) -> String? {
        assert(packId.count > 0)
        assert(packKey.count > 0)

        if isStickerInstalled(packId: packId,
                              stickerId: stickerId) {
            return stickerUrl(packId: packId, stickerId: stickerId).path
        } else {
            // TODO: We may want to kick off download here on cache miss.

            return nil
        }
    }

    @objc
    public class func isStickerInstalled(packId: Data,
                                         stickerId: UInt32) -> Bool {
        assert(packId.count > 0)

        var result = false
        databaseStorage.readSwallowingErrors { (transaction) in
            result = nil != fetchInstalledSticker(packId: packId, stickerId: stickerId, transaction: transaction)
        }
        return result
    }

    @objc
    public class func fetchInstalledSticker(packId: Data,
                                            stickerId: UInt32,
                                            transaction: SDSAnyReadTransaction) -> InstalledSticker? {
        assert(packId.count > 0)

        let uniqueId = InstalledSticker.uniqueId(forPackId: packId, stickerId: stickerId)

        return InstalledSticker.anyFetch(withUniqueId: uniqueId, transaction: transaction)
    }

    @objc
    public class func installSticker(packId: Data,
                                     packKey: Data,
                                     stickerId: UInt32,
                                     stickerData: Data) {
        assert(packId.count > 0)
        assert(packKey.count > 0)
        assert(stickerData.count > 0)

        var hasInstalledSticker = false
        databaseStorage.readSwallowingErrors { (transaction) in
            hasInstalledSticker = nil != fetchInstalledSticker(packId: packId, stickerId: stickerId, transaction: transaction)
        }
        if hasInstalledSticker {
            // Sticker already installed, skip.
            return
        }

        DispatchQueue.global().async {
            let url = stickerUrl(packId: packId, stickerId: stickerId)
            do {
                try stickerData.write(to: url, options: .atomic)
            } catch let error as NSError {
                owsFailDebug("File write failed: \(error)")
                return
            }

            databaseStorage.writeSwallowingErrors { (transaction) in
                let installedSticker = InstalledSticker(packId: packId, packKey: packKey, stickerId: stickerId)
                installedSticker.anySave(transaction: transaction)
            }
        }
    }

    @objc
    public class func tryToDownloadAndInstallSticker(packId: Data,
                                                     packKey: Data,
                                                     stickerId: UInt32) {
        assert(packId.count > 0)
        assert(packKey.count > 0)

        let operation = DownloadStickerOperation(packId: packId,
                                                 packKey: packKey,
                                                 stickerId: stickerId,
                                                 success: { (stickerData) in
                                                    self.installSticker(packId: packId, packKey: packKey, stickerId: stickerId, stickerData: stickerData)
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
}
