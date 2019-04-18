//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// TODO: Determine how views can be notified of sticker downloads.
@objc
public class InstalledStickers: NSObject {

    private static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

//    public static let stickerPackCollection = "InstalledStickers"
//
//    private let stickerPackStore = SDSKeyValueStore(collection: InstalledStickers.stickerPackCollection)

    private static let operationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "org.signal.installedStickers"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    private override init() {
        // TODO: Resume sticker and sticker pack downloads when app is ready.
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
    public class func fetchInstalledStickerPack(packId: Data,
                                                transaction: SDSAnyReadTransaction) -> InstalledStickerPack? {
        assert(packId.count > 0)

        let uniqueId = InstalledStickerPack.uniqueId(forPackId: packId)

        return InstalledStickerPack.anyFetch(withUniqueId: uniqueId, transaction: transaction)
    }

    // MARK: -

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

        var result: InstalledSticker?
        databaseStorage.readSwallowingErrors { (transaction) in
            if let installedSticker = fetchInstalledSticker(packId: packId, stickerId: stickerId, transaction: transaction) {
                result = installedSticker
            }
        }
        if result != nil {
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

    @objc
    public class func tryToDownloadAndInstallStickerPack(packId: Data,
                                                         packKey: Data) {
        assert(packId.count > 0)
        assert(packKey.count > 0)

        // TODO: Mark sticker pack as downloading in kv store.

        let operation = DownloadStickerPackOperation(packId: packId,
                                                     packKey: packKey,
                                                     success: { (_) in
                                                        // TODO: Mark sticker pack as downloaded in kv store.
                                                        // TODO: Enqueue all stickers in pack for download.
        },
                                                     failure: { (_) in
                                                        // Do nothing.
        })
        operationQueue.addOperation(operation)
    }

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
}
