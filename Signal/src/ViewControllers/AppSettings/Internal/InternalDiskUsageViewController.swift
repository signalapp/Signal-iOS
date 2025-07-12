//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import GRDB
import SignalServiceKit
import SignalUI

class InternalDiskUsageViewController: OWSTableViewController2 {

    struct DiskUsage {
        let dbSize = UInt(SSKEnvironment.shared.databaseStorageRef.databaseFileSize)
        let dbWalSize = UInt(SSKEnvironment.shared.databaseStorageRef.databaseWALFileSize)
        let dbShmSize = UInt(SSKEnvironment.shared.databaseStorageRef.databaseSHMFileSize)
        let attachmentSize = OWSFileSystem.folderSizeRecursive(of: AttachmentStream.attachmentsDirectory())?.uintValue
        let emojiCacheSize = OWSFileSystem.folderSizeRecursive(of: Emoji.cacheUrl)?.uintValue
        let stickerCacheSize = OWSFileSystem.folderSizeRecursive(of: StickerManager.cacheDirUrl())?.uintValue
        let avatarCacheSize =
            (OWSFileSystem.folderSizeRecursive(of: AvatarBuilder.avatarCacheDirectory)?.uintValue ?? 0)
            + (OWSFileSystem.folderSizeRecursive(ofPath: OWSUserProfile.sharedDataProfileAvatarsDirPath)?.uintValue ?? 0)
            + (OWSFileSystem.folderSizeRecursive(ofPath: OWSUserProfile.legacyProfileAvatarsDirPath)?.uintValue ?? 0)
        let voiceMessageCacheSize = OWSFileSystem.folderSizeRecursive(of: VoiceMessageInterruptedDraftStore.draftVoiceMessageDirectory)?.uintValue
        let librarySize = OWSFileSystem.folderSizeRecursive(ofPath: OWSFileSystem.appLibraryDirectoryPath())?.uintValue ?? 0
        let libraryCachesSize = OWSFileSystem.folderSizeRecursive(ofPath: OWSFileSystem.cachesDirectoryPath())?.uintValue ?? 0
        let documentsSize = OWSFileSystem.folderSizeRecursive(ofPath: OWSFileSystem.appDocumentDirectoryPath())?.uintValue
        let sharedDataSize = OWSFileSystem.folderSizeRecursive(ofPath: OWSFileSystem.appSharedDataDirectoryPath())?.uintValue

        let bundleSize = OWSFileSystem.folderSizeRecursive(ofPath: Bundle.main.bundlePath)?.uintValue
        let tmpSize = OWSFileSystem.folderSizeRecursive(ofPath: OWSTemporaryDirectory())?.uintValue
    }

    let diskUsage: DiskUsage
    let orphanedAttachmentByteCount: UInt

    public nonisolated static func build() async -> InternalDiskUsageViewController {
        await Task.yield()
        try! await DependenciesBridge.shared.orphanedAttachmentCleaner.runUntilFinished()
        let diskUsageTask = Task { DiskUsage() }
        let orphanedAttachmentByteCountTask = Task { await Self.orphanAttachmentByteCount() }
        let diskUsage = await diskUsageTask.value
        let orphanedAttachmentByteCount = await orphanedAttachmentByteCountTask.value
        return await InternalDiskUsageViewController(
            diskUsage: diskUsage,
            orphanedAttachmentByteCount: orphanedAttachmentByteCount,
        )
    }

    private init(
        diskUsage: DiskUsage,
        orphanedAttachmentByteCount: UInt,
    ) {
        self.diskUsage = diskUsage
        self.orphanedAttachmentByteCount = orphanedAttachmentByteCount
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Internal Disk Usage"

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let byteCountFormatter = ByteCountFormatter()

        let knownFilesSize: UInt = [UInt?](
            arrayLiteral:
                diskUsage.dbSize,
                diskUsage.dbWalSize,
                diskUsage.dbShmSize,
                diskUsage.attachmentSize,
                diskUsage.emojiCacheSize,
                diskUsage.stickerCacheSize,
                diskUsage.avatarCacheSize,
                diskUsage.voiceMessageCacheSize,
                diskUsage.librarySize,
            )
            .compacted()
            .reduce(0, +)
        var totalFilesystemSize: UInt = [UInt?](
            arrayLiteral:
                diskUsage.librarySize,
                diskUsage.documentsSize,
                diskUsage.sharedDataSize
            )
            .compacted()
            .reduce(0, +)

        let diskUsageSection = OWSTableSection(title: "Disk Usage")
        diskUsageSection.add(.copyableItem(label: "DB Size", value: byteCountFormatter.string(for: diskUsage.dbSize)))
        diskUsageSection.add(.copyableItem(label: "DB WAL Size", value: byteCountFormatter.string(for: diskUsage.dbWalSize)))
        diskUsageSection.add(.copyableItem(label: "DB SHM Size", value: byteCountFormatter.string(for: diskUsage.dbShmSize)))
        diskUsageSection.add(.copyableItem(label: "Total attachments size", value: byteCountFormatter.string(for: diskUsage.attachmentSize)))
        diskUsageSection.add(.copyableItem(label: "Orphaned attachments size", value: byteCountFormatter.string(for: orphanedAttachmentByteCount)))
        diskUsageSection.add(.copyableItem(label: "Emoji cache size", value: byteCountFormatter.string(for: diskUsage.emojiCacheSize)))
        diskUsageSection.add(.copyableItem(label: "Sticker cache size", value: byteCountFormatter.string(for: diskUsage.stickerCacheSize)))
        diskUsageSection.add(.copyableItem(label: "Avatar cache size", value: byteCountFormatter.string(for: diskUsage.avatarCacheSize)))
        diskUsageSection.add(.copyableItem(label: "Voice message drafts size", value: byteCountFormatter.string(for: diskUsage.voiceMessageCacheSize)))
        diskUsageSection.add(.copyableItem(label: "Library (minus caches) folder size", value: byteCountFormatter.string(for: diskUsage.librarySize - diskUsage.libraryCachesSize)))
        diskUsageSection.add(.copyableItem(label: "Caches folder size", value: byteCountFormatter.string(for: diskUsage.libraryCachesSize)))
        diskUsageSection.add(.copyableItem(label: "Ancillary files size", value: byteCountFormatter.string(for: totalFilesystemSize - knownFilesSize)))

        if TSConstants.isUsingProductionService {
            let stagingSharedDataSize = OWSFileSystem.folderSizeRecursive(
                ofPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TSConstantsStaging().applicationGroup)!.path
            )?.uintValue
            diskUsageSection.add(.copyableItem(label: "Staging app group size", value: byteCountFormatter.string(for: stagingSharedDataSize)))
            totalFilesystemSize += stagingSharedDataSize ?? 0
        } else {
            let prodSharedDataSize = OWSFileSystem.folderSizeRecursive(
                ofPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TSConstantsProduction().applicationGroup)!.path
            )?.uintValue
            diskUsageSection.add(.copyableItem(label: "Prod app group size", value: byteCountFormatter.string(for: prodSharedDataSize)))
            totalFilesystemSize += prodSharedDataSize ?? 0
        }
        diskUsageSection.add(.copyableItem(
            label: "Total filesystem size",
            subtitle: "Should match \"Documents & Data\" in Settings>General>Storage>Signal",
            value: byteCountFormatter.string(for: totalFilesystemSize)
        ))
        contents.add(diskUsageSection)

        let otherDiskUsageSection = OWSTableSection(title: "Other Disk Usage")
        otherDiskUsageSection.add(.copyableItem(label: "Tmp size", value: byteCountFormatter.string(for: diskUsage.tmpSize)))
        otherDiskUsageSection.add(.copyableItem(label: "Bundle size", value: byteCountFormatter.string(for: diskUsage.bundleSize)))

        contents.add(otherDiskUsageSection)

        self.contents = contents
    }

    private static func orphanAttachmentByteCount() -> UInt {
        var attachmentDirFiles = Set(try! OWSFileSystem.recursiveFilesInDirectory(AttachmentStream.attachmentsDirectory().path))
        DependenciesBridge.shared.db.read { tx in
            let cursor = try! Attachment.Record
                .filter(
                    Column(Attachment.Record.CodingKeys.localRelativeFilePath) != nil
                    || Column(Attachment.Record.CodingKeys.localRelativeFilePathThumbnail) != nil
                    || Column(Attachment.Record.CodingKeys.audioWaveformRelativeFilePath) != nil
                    || Column(Attachment.Record.CodingKeys.videoStillFrameRelativeFilePath) != nil
                )
                .fetchCursor(tx.database)
            while let attachmentRecord = try! cursor.next() {
                for relFilePath in attachmentRecord.allFilesRelativePaths {
                    let absolutePath = AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: relFilePath).path
                    attachmentDirFiles.remove(absolutePath)
                }
            }
        }
        if attachmentDirFiles.isEmpty {
            return 0
        }
        var byteCount: UInt = 0
        for file in attachmentDirFiles {
            byteCount += OWSFileSystem.fileSize(ofPath: file)?.uintValue ?? 0
        }
        return byteCount
    }
}
