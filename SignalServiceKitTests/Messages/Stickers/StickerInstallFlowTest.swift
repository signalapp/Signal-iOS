//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
import UIKit

@testable import SignalServiceKit

@MainActor
final class StickerInstallFlowTest {
    private let db = InMemoryDB()
    private let stickerManager: StickerManager
    private let tempDirPath: String

    init() {
        let dateProvider = { Date() }
        let appReadiness = AppReadinessMock()

        self.tempDirPath = OWSFileSystem.temporaryFilePath(isAvailableWhileDeviceLocked: false).appendingPathComponent("StickerInstallFlowTest")
        OWSFileSystem.ensureDirectoryExists(tempDirPath)

        self.stickerManager = StickerManager(
            appReadiness: appReadiness,
            dateProvider: dateProvider,
            attachmentStore: AttachmentStore(),
            attachmentDownloadStore: AttachmentDownloadStore(dateProvider: dateProvider),
            tsAccountManager: MockTSAccountManager(),
            messageSenderJobQueue: MessageSenderJobQueue(appReadiness: appReadiness),
            interactionStore: InteractionStoreImpl(),
            cacheDirUrl: URL(fileURLWithPath: self.tempDirPath),
            stickerFavoriteStore: StickerFavoriteStore(),
            storageServiceManager: FakeStorageServiceManager(),
            stickerDownloader: MockStickerDownloader(stickerData: UIImage(systemName: "circle")!.pngData()!),
            db: db,
        )
    }

    deinit {
        try? FileManager.default.removeItem(atPath: tempDirPath)
    }

    @Test
    func installStickerHappyPath() async throws {
        let plaintext = sampleStickerPlaintext()
        let info = randomStickerInfo()

        let didInstall = await stickerManager.installSticker(
            stickerInfo: info,
            stickerData: plaintext,
            contentType: MimeType.imagePng.rawValue,
            emojiString: nil,
        )
        #expect(didInstall)

        let record = try #require(db.read { tx in
            stickerManager.fetchInstalledSticker(stickerInfo: info, transaction: tx)
        })
        let localKey = try #require(record.localKey)
        let plaintextLength = try #require(record.plaintextLength)
        #expect(plaintextLength == UInt32(plaintext.count))

        let fileUrl = stickerManager.stickerDataUrl(
            forInstalledSticker: record,
            verifyExists: true,
        )!
        let onDisk = try Data(contentsOf: fileUrl)
        #expect(onDisk != plaintext)

        let metadata = EncryptedStickerMetadata(
            stickerInfo: info,
            stickerType: .apng,
            emojiString: nil,
            encryptedStickerDataUrl: fileUrl,
            encryptionKey: localKey,
            plaintextLength: plaintextLength,
        )

        // Make sure its a valid image.
        let decrypted = try metadata.readStickerData()
        #expect(decrypted == plaintext)
        #expect(DataImageSource(decrypted).ows_isValidImage)
    }

    @Test
    func installStickerReturnsFalseWhenAlreadyInstalled() async throws {
        let plaintext = sampleStickerPlaintext()
        let info = randomStickerInfo()

        #expect(await stickerManager.installSticker(
            stickerInfo: info,
            stickerData: plaintext,
            contentType: MimeType.imagePng.rawValue,
            emojiString: nil,
        ))
        #expect(await !stickerManager.installSticker(
            stickerInfo: info,
            stickerData: plaintext,
            contentType: MimeType.imagePng.rawValue,
            emojiString: nil,
        ))
    }

    @Test
    func installStickerRepairsRecordWithMissingFile() async throws {
        let plaintext = sampleStickerPlaintext()
        let info = randomStickerInfo()

        #expect(await stickerManager.installSticker(
            stickerInfo: info,
            stickerData: plaintext,
            contentType: MimeType.imagePng.rawValue,
            emojiString: nil,
        ))
        let originalRecord = try #require(db.read { tx in
            stickerManager.fetchInstalledSticker(stickerInfo: info, transaction: tx)
        })
        let originalFileUrl = try #require(stickerManager.stickerDataUrl(
            forInstalledSticker: originalRecord,
            verifyExists: true,
        ))

        // Simulate the file being moved out from under the installed sticker.
        try FileManager.default.removeItem(at: originalFileUrl)
        #expect(!db.read { tx in stickerManager.isStickerInstalled(stickerInfo: info, transaction: tx) })

        // Repair.
        #expect(await stickerManager.installSticker(
            stickerInfo: info,
            stickerData: plaintext,
            contentType: MimeType.imagePng.rawValue,
            emojiString: nil,
        ))

        let repairedRecord = try #require(db.read { tx in
            stickerManager.fetchInstalledSticker(stickerInfo: info, transaction: tx)
        })
        #expect(repairedRecord.localKey != originalRecord.localKey)
        #expect(db.read { tx in stickerManager.isStickerInstalled(stickerInfo: info, transaction: tx) })
        let count = try db.read { tx in
            try InstalledStickerRecord.fetchCount(tx.database)
        }
        #expect(count == 1)

        // The file on disk must decrypt with the key stored in the repaired record.
        let metadata = try #require(stickerManager.installedStickerMetadata(installedSticker: repairedRecord))
        #expect(try metadata.readStickerData() == plaintext)
    }

    // MARK: - Helpers

    private func sampleStickerPlaintext() -> Data {
        return UIImage(systemName: "circle")!.pngData()!
    }

    private func randomStickerInfo() -> StickerInfo {
        return StickerInfo(
            packId: Randomness.generateRandomBytes(16),
            packKey: Randomness.generateRandomBytes(StickerManager.packKeyLength),
            stickerId: UInt32.random(in: 0..<1024),
        )
    }
}
