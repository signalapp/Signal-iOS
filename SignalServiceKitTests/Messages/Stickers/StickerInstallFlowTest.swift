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
