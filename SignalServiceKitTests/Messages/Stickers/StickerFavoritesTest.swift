//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
import UIKit

@testable import SignalServiceKit

@MainActor
final class StickerFavoritesTest {
    private let db = InMemoryDB()
    // Using Date() includes fractions of seconds, but favorite sticker records don't.
    // Use a whole number to avoid discrepencies when comparing times.
    private let clock = AtomicValue(Date(millisecondsSince1970: 1_700_000_000_000), lock: .init())
    private let stickerFavoriteStore = StickerFavoriteStore()
    private let stickerManager: StickerManager
    private let tempDirPath: String

    init() {
        let clock = self.clock
        let dateProvider = { clock.get() }
        let appReadiness = AppReadinessMock()

        self.tempDirPath = OWSFileSystem.temporaryFilePath(isAvailableWhileDeviceLocked: false).appendingPathComponent("StickerFavoritesTest")
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
            stickerFavoriteStore: stickerFavoriteStore,
            db: db,
        )
        OWSFileSystem.ensureDirectoryExists(stickerManager.favoritesCacheDirUrl().path)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: tempDirPath)
    }

    // MARK: - Add

    @Test
    func addStickerToFavoritesHappyPath() async throws {
        let plaintext = sampleStickerPlaintext()
        let metadata = transientStickerMetadata(plaintext: plaintext, emojiString: "🌼")

        try await stickerManager.addStickerToFavorites(stickerMetadata: metadata)

        let record = try #require(db.read { tx in
            stickerFavoriteStore.fetchFavoriteSticker(stickerInfo: metadata.stickerInfo, tx: tx)
        })
        #expect(record.packId == metadata.packId)
        #expect(record.packKey == metadata.packKey)
        #expect(record.stickerId == metadata.stickerId)
        #expect(record.emojiString == "🌼")
        #expect(record.contentType == MimeType.imagePng.rawValue)
        #expect(record.plaintextLength == UInt32(plaintext.count))
        #expect(record.favoritedAt! == now.ows_millisecondsSince1970)
        #expect(record.unfavoritedAt == nil)

        db.read { tx in
            #expect(stickerManager.isStickerFavorited(stickerInfo: metadata.stickerInfo, tx: tx))
            #expect(stickerManager.stickerFavoriteCount(tx: tx) == 1)
        }

        let filePath = try #require(favoriteFilePaths().first)
        #expect(filePath.hasPrefix(stickerManager.favoritesCacheDirUrl().path))
        let fileUrl = URL(fileURLWithPath: filePath)
        #expect(try Data(contentsOf: fileUrl) != plaintext)

        let encryptedMetadata = EncryptedStickerMetadata(
            stickerInfo: metadata.stickerInfo,
            stickerType: .apng,
            emojiString: record.emojiString,
            encryptedStickerDataUrl: fileUrl,
            encryptionKey: record.localKey!,
            plaintextLength: record.plaintextLength!,
        )
        let decrypted = try encryptedMetadata.readStickerData()
        #expect(decrypted == plaintext)
        #expect(DataImageSource(decrypted).ows_isValidImage)
    }

    @Test
    func addStickerToFavoritesTwiceIsNoOp() async throws {
        let metadata = transientStickerMetadata()

        try await stickerManager.addStickerToFavorites(stickerMetadata: metadata)
        let firstRecord = try #require(db.read { tx in
            stickerFavoriteStore.fetchFavoriteSticker(stickerInfo: metadata.stickerInfo, tx: tx)
        })

        try await stickerManager.addStickerToFavorites(stickerMetadata: metadata)
        let secondRecord = try #require(db.read { tx in
            stickerFavoriteStore.fetchFavoriteSticker(stickerInfo: metadata.stickerInfo, tx: tx)
        })

        // The second add shouldn't re-key or rewrite the favorite.
        #expect(firstRecord.id == secondRecord.id)
        #expect(firstRecord.localKey == secondRecord.localKey)
        db.read { tx in
            #expect(stickerManager.stickerFavoriteCount(tx: tx) == 1)
        }
        #expect(favoriteFilePaths().count == 1)
    }

    @Test
    func addStickerToFavoritesThrowsWhenLimitReached() async throws {
        await db.awaitableWrite { tx in
            for stickerId in 0..<UInt32(StickerManager.maxStickerFavorites) {
                stickerFavoriteStore.addStickerToFavorites(
                    stickerInfo: randomStickerInfo(stickerId: stickerId),
                    contentType: MimeType.imagePng.rawValue,
                    emojiString: nil,
                    localKey: AttachmentKey.generate().combinedKey,
                    plaintextLength: 1,
                    favoritedAtTimestamp: now.ows_millisecondsSince1970,
                    tx: tx,
                )
            }
        }

        let metadata = transientStickerMetadata()
        await #expect(throws: StickerFavoriteError.limitReached) {
            try await self.stickerManager.addStickerToFavorites(stickerMetadata: metadata)
        }

        db.read { tx in
            #expect(!stickerManager.isStickerFavorited(stickerInfo: metadata.stickerInfo, tx: tx))
            #expect(stickerManager.stickerFavoriteCount(tx: tx) == StickerManager.maxStickerFavorites)
        }
        #expect(favoriteDirContents().isEmpty)
    }

    @Test
    func addFavoriteIsIndependentOfInstalledSticker() async throws {
        let plaintext = sampleStickerPlaintext()
        let metadata = transientStickerMetadata(plaintext: plaintext)

        #expect(await stickerManager.installSticker(
            stickerInfo: metadata.stickerInfo,
            stickerData: plaintext,
            contentType: MimeType.imagePng.rawValue,
            emojiString: nil,
        ))
        try await stickerManager.addStickerToFavorites(stickerMetadata: metadata)

        let installed = try #require(db.read { tx in
            stickerManager.fetchInstalledSticker(stickerInfo: metadata.stickerInfo, transaction: tx)
        })
        let favorite = try #require(db.read { tx in
            stickerFavoriteStore.fetchFavoriteSticker(stickerInfo: metadata.stickerInfo, tx: tx)
        })
        let installedPath = try #require(stickerManager.stickerDataUrl(forInstalledSticker: installed, verifyExists: true)).path
        let favoritePath = try #require(favoriteFilePaths().first)

        #expect(installedPath != favoritePath)
        #expect(installed.localKey != favorite.localKey)

        // Removing the favorite does not touch the installed sticker's file.
        await stickerManager.removeStickerFromFavorites(stickerInfo: metadata.stickerInfo)
        #expect(FileManager.default.fileExists(atPath: installedPath))
        #expect(!FileManager.default.fileExists(atPath: favoritePath))
    }

    // MARK: - Remove

    @Test
    func removeStickerFromFavoritesDeletesFileAndMarksUnfavorited() async throws {
        let metadata = transientStickerMetadata()
        try await stickerManager.addStickerToFavorites(stickerMetadata: metadata)
        let filePath = try #require(favoriteFilePaths().first)
        #expect(FileManager.default.fileExists(atPath: filePath))

        advanceClock(by: 1)
        await stickerManager.removeStickerFromFavorites(stickerInfo: metadata.stickerInfo)

        db.read { tx in
            #expect(!stickerManager.isStickerFavorited(stickerInfo: metadata.stickerInfo, tx: tx))
            #expect(stickerManager.stickerFavoriteCount(tx: tx) == 0)
        }
        #expect(!FileManager.default.fileExists(atPath: filePath))
        #expect(favoriteFilePaths().isEmpty)

        let record = try fetchRecordIncludingUnfavorited(stickerInfo: metadata.stickerInfo)
        #expect(record!.unfavoritedAt! == now.ows_millisecondsSince1970)
        #expect(record!.favoritedAt == nil)
        #expect(record!.packKey == nil)
    }

    @Test
    func removeStickerFromFavoritesWhenNotFavoritedIsNoOp() async throws {
        let favorited = transientStickerMetadata()
        try await stickerManager.addStickerToFavorites(stickerMetadata: favorited)

        await stickerManager.removeStickerFromFavorites(stickerInfo: randomStickerInfo())

        db.read { tx in
            #expect(stickerManager.isStickerFavorited(stickerInfo: favorited.stickerInfo, tx: tx))
            #expect(stickerManager.stickerFavoriteCount(tx: tx) == 1)
        }
        #expect(favoriteFilePaths().count == 1)
    }

    @Test
    func removeOnlyRemovesMatchingSticker() async throws {
        let first = transientStickerMetadata()
        let second = transientStickerMetadata(stickerInfo: StickerInfo(
            packId: first.packId,
            packKey: first.packKey,
            stickerId: first.stickerId + 1,
        ))
        try await stickerManager.addStickerToFavorites(stickerMetadata: first)
        try await stickerManager.addStickerToFavorites(stickerMetadata: second)

        await stickerManager.removeStickerFromFavorites(stickerInfo: first.stickerInfo)

        db.read { tx in
            #expect(!stickerManager.isStickerFavorited(stickerInfo: first.stickerInfo, tx: tx))
            #expect(stickerManager.isStickerFavorited(stickerInfo: second.stickerInfo, tx: tx))
        }
        #expect(favoriteFilePaths().count == 1)
    }

    // MARK: - Refavorite

    @Test
    func refavoriteAfterUnfavoriteReusesRow() async throws {
        let metadata = transientStickerMetadata()
        try await stickerManager.addStickerToFavorites(stickerMetadata: metadata)
        let original = try #require(db.read { tx in
            stickerFavoriteStore.fetchFavoriteSticker(stickerInfo: metadata.stickerInfo, tx: tx)
        })

        advanceClock(by: 1)
        await stickerManager.removeStickerFromFavorites(stickerInfo: metadata.stickerInfo)

        advanceClock(by: 1)
        try await stickerManager.addStickerToFavorites(stickerMetadata: metadata)

        let refavorited = try #require(db.read { tx in
            stickerFavoriteStore.fetchFavoriteSticker(stickerInfo: metadata.stickerInfo, tx: tx)
        })
        #expect(refavorited.id == original.id)
        #expect(refavorited.favoritedAt! == now.ows_millisecondsSince1970)
        #expect(refavorited.favoritedAt != original.favoritedAt)
        #expect(refavorited.unfavoritedAt == nil)
        #expect(refavorited.localKey != original.localKey)
        #expect(refavorited.packKey != nil && refavorited.packKey == original.packKey)

        db.read { tx in
            #expect(stickerManager.isStickerFavorited(stickerInfo: metadata.stickerInfo, tx: tx))
            #expect(stickerManager.stickerFavoriteCount(tx: tx) == 1)
        }

        // The re-favorited file is readable with the new key.
        let filePath = try #require(favoriteFilePaths().first)
        #expect(favoriteFilePaths().count == 1)
        let encryptedMetadata = EncryptedStickerMetadata(
            stickerInfo: metadata.stickerInfo,
            stickerType: .apng,
            emojiString: refavorited.emojiString,
            encryptedStickerDataUrl: URL(fileURLWithPath: filePath),
            encryptionKey: refavorited.localKey!,
            plaintextLength: refavorited.plaintextLength!,
        )
        #expect(try encryptedMetadata.readStickerData() == metadata.readStickerData())
    }

    // MARK: - Unfavorited records

    @Test
    func unfavoritedStickersAreExcludedFromFavorites() async throws {
        let kept = transientStickerMetadata()
        let removed = transientStickerMetadata()
        try await stickerManager.addStickerToFavorites(stickerMetadata: kept)
        try await stickerManager.addStickerToFavorites(stickerMetadata: removed)

        await stickerManager.removeStickerFromFavorites(stickerInfo: removed.stickerInfo)

        #expect(try fetchRecordIncludingUnfavorited(stickerInfo: removed.stickerInfo) != nil)

        db.read { tx in
            #expect(stickerFavoriteStore.fetchFavoriteSticker(stickerInfo: removed.stickerInfo, tx: tx) == nil)
            #expect(stickerManager.stickerFavoriteCount(tx: tx) == 1)
            #expect(stickerFavoriteStore.favoritedStickers(tx: tx).map(\.packId) == [kept.packId])
        }
        #expect(favoriteFilePaths().count == 1)
        #expect(Set(favoriteFilePaths()) == Set(favoriteDirContents()))
    }

    @Test
    func unfavoritedStickersDoNotCountTowardLimit() async throws {
        let stickerInfos = (0..<UInt32(StickerManager.maxStickerFavorites)).map { randomStickerInfo(stickerId: $0) }
        await db.awaitableWrite { tx in
            for stickerInfo in stickerInfos {
                stickerFavoriteStore.addStickerToFavorites(
                    stickerInfo: stickerInfo,
                    contentType: MimeType.imagePng.rawValue,
                    emojiString: nil,
                    localKey: AttachmentKey.generate().combinedKey,
                    plaintextLength: 1,
                    favoritedAtTimestamp: now.ows_millisecondsSince1970,
                    tx: tx,
                )
            }
        }

        await stickerManager.removeStickerFromFavorites(stickerInfo: stickerInfos[0])

        let metadata = transientStickerMetadata()
        try await stickerManager.addStickerToFavorites(stickerMetadata: metadata)

        db.read { tx in
            #expect(stickerManager.isStickerFavorited(stickerInfo: metadata.stickerInfo, tx: tx))
            #expect(stickerManager.stickerFavoriteCount(tx: tx) == StickerManager.maxStickerFavorites)
        }
    }

    // MARK: - Fetch

    @Test
    func favoritedStickersAreMostRecentFirst() async throws {
        let first = transientStickerMetadata()
        let second = transientStickerMetadata()
        let third = transientStickerMetadata()
        for metadata in [first, second, third] {
            try await stickerManager.addStickerToFavorites(stickerMetadata: metadata)
        }

        let packIds = db.read { tx in
            stickerFavoriteStore.favoritedStickers(tx: tx).map(\.packId)
        }
        #expect(packIds == [third.packId, second.packId, first.packId])
    }

    @Test
    func filePathsForAllFavoritedStickersMatchFilesOnDisk() async throws {
        for _ in 0..<3 {
            try await stickerManager.addStickerToFavorites(stickerMetadata: transientStickerMetadata())
        }

        let paths = favoriteFilePaths()
        #expect(paths.count == 3)
        for path in paths {
            #expect(FileManager.default.fileExists(atPath: path))
        }
        #expect(Set(paths) == Set(favoriteDirContents()))
    }

    @Test
    func expirationJobDeletesOnlyExpiredUnfavorites() async throws {
        let job = FavoriteStickerExpirationJob(
            dateProvider: { [clock] in clock.get() },
            db: db,
            stickerFavoriteStore: stickerFavoriteStore,
        )
        let unfavorited = transientStickerMetadata()
        let favorited = transientStickerMetadata()
        try await stickerManager.addStickerToFavorites(stickerMetadata: unfavorited)
        try await stickerManager.addStickerToFavorites(stickerMetadata: favorited)
        await stickerManager.removeStickerFromFavorites(stickerInfo: unfavorited.stickerInfo)

        let next = try #require(db.read { tx in job.nextExpiringElement(tx: tx) })
        #expect(next.packId == unfavorited.packId)
        #expect(
            job.expirationDate(ofElement: next) ==
                now.addingTimeInterval(FavoriteStickerExpirationJob.unfavoritedExpiresAt),
        )
        db.write { tx in job.deleteExpiredElement(next, tx: tx) }
        #expect(try fetchRecordIncludingUnfavorited(stickerInfo: unfavorited.stickerInfo) == nil)
        db.read { tx in
            #expect(job.nextExpiringElement(tx: tx) == nil)
            #expect(stickerManager.isStickerFavorited(stickerInfo: favorited.stickerInfo, tx: tx))
        }
    }

    // MARK: - Helpers

    private var now: Date {
        clock.get()
    }

    private func advanceClock(by interval: TimeInterval) {
        clock.update { $0 += interval }
    }

    private func fetchRecordIncludingUnfavorited(stickerInfo: StickerInfo) throws -> FavoriteStickerRecord? {
        return try db.read { tx in
            try FavoriteStickerRecord
                .filter(stickerInfo: stickerInfo, currentFavoritesOnly: false)
                .fetchOne(tx.database)
        }
    }

    private func favoriteFilePaths() -> [String] {
        return db.read { tx in
            stickerManager.filePathsForAllFavoritedStickers(transaction: tx)
        }
    }

    private func favoriteDirContents() -> [String] {
        let dirUrl = stickerManager.favoritesCacheDirUrl()
        let fileNames = (try? FileManager.default.contentsOfDirectory(atPath: dirUrl.path)) ?? []
        return fileNames.map { dirUrl.appendingPathComponent($0).path }
    }

    private func transientStickerMetadata(
        stickerInfo: StickerInfo? = nil,
        plaintext: Data? = nil,
        emojiString: String? = nil,
    ) -> TransientStickerMetadata {
        return TransientStickerMetadata(
            stickerInfo: stickerInfo ?? randomStickerInfo(),
            stickerType: .apng,
            emojiString: emojiString,
            stickerData: plaintext ?? sampleStickerPlaintext(),
        )
    }

    private func sampleStickerPlaintext() -> Data {
        return UIImage(systemName: "circle")!.pngData()!
    }

    private func randomStickerInfo(stickerId: UInt32? = nil) -> StickerInfo {
        return StickerInfo(
            packId: Randomness.generateRandomBytes(16),
            packKey: Randomness.generateRandomBytes(StickerManager.packKeyLength),
            stickerId: stickerId ?? UInt32.random(in: 0..<1024),
        )
    }
}
