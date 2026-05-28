//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import GRDB
import SignalServiceKit
import SignalUI

private func folderSizeRecursive(ofPath dirPath: String) -> UInt64? {
    do {
        let filePaths = try OWSFileSystem.recursiveFilesInDirectory(dirPath)
        var sum: UInt64 = 0
        for filePath in filePaths {
            sum += try OWSFileSystem.fileSize(ofPath: filePath)
        }
        return sum
    } catch {
        Logger.error("Couldn't fetch file sizes \(error)")
        return nil
    }
}

private func folderSizeRecursive(of dirUrl: URL) -> UInt64? {
    return folderSizeRecursive(ofPath: dirUrl.path)
}

class InternalDiskUsageViewController: OWSTableViewController2 {

    struct DiskUsage {
        let dbSize = SSKEnvironment.shared.databaseStorageRef.databaseFileSize
        let dbWalSize = SSKEnvironment.shared.databaseStorageRef.databaseWALFileSize
        let dbShmSize = SSKEnvironment.shared.databaseStorageRef.databaseSHMFileSize
        let attachmentSize = folderSizeRecursive(of: AttachmentStream.attachmentsDirectory())
        let emojiCacheSize = folderSizeRecursive(of: Emoji.cacheUrl)
        let stickerCacheSize = folderSizeRecursive(of: StickerManager.cacheDirUrl())
        let avatarCacheSize =
            (folderSizeRecursive(of: AvatarBuilder.avatarCacheDirectory) ?? 0)
                + (folderSizeRecursive(ofPath: OWSUserProfile.sharedDataProfileAvatarsDirPath) ?? 0)
                + (folderSizeRecursive(ofPath: OWSUserProfile.legacyProfileAvatarsDirPath) ?? 0)
        let voiceMessageCacheSize = folderSizeRecursive(of: VoiceMessageInterruptedDraftStore.draftVoiceMessageDirectory)
        let librarySize = folderSizeRecursive(ofPath: OWSFileSystem.appLibraryDirectoryPath()) ?? 0
        let libraryCachesSize = folderSizeRecursive(ofPath: OWSFileSystem.cachesDirectoryPath()) ?? 0
        let bundleSize = folderSizeRecursive(ofPath: Bundle.main.bundlePath)
        let tmpSize = folderSizeRecursive(ofPath: NSTemporaryDirectory())
    }

    let diskUsage: DiskUsage
    let orphanedAttachmentByteCount: UInt64

    nonisolated static func build() async -> InternalDiskUsageViewController {
        await Task.yield()
        try! await DependenciesBridge.shared.orphanedAttachmentCleaner.runUntilFinished()
        async let orphanedAttachmentByteCount = Self.orphanAttachmentByteCount()
        let diskUsage = DiskUsage()
        return await InternalDiskUsageViewController(
            diskUsage: diskUsage,
            orphanedAttachmentByteCount: orphanedAttachmentByteCount,
        )
    }

    private init(
        diskUsage: DiskUsage,
        orphanedAttachmentByteCount: UInt64,
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
        diskUsageSection.add(.copyableItem(label: "Library folder size (includes Caches)", value: byteCountFormatter.string(for: diskUsage.librarySize)))
        diskUsageSection.add(.copyableItem(label: "Caches folder size", value: byteCountFormatter.string(for: diskUsage.libraryCachesSize)))
        diskUsageSection.add(.copyableItem(label: "Tmp size", value: byteCountFormatter.string(for: diskUsage.tmpSize)))
        diskUsageSection.add(.copyableItem(label: "Bundle size", value: byteCountFormatter.string(for: diskUsage.bundleSize)))
        contents.add(diskUsageSection)

        self.contents = contents
    }

    private static func orphanAttachmentByteCount() -> UInt64 {
        var attachmentDirFiles = Set(try! OWSFileSystem.recursiveFilesInDirectory(AttachmentStream.attachmentsDirectory().path))
        DependenciesBridge.shared.db.read { tx in
            let cursor = try! Attachment.Record
                .filter(
                    Column(Attachment.Record.CodingKeys.localRelativeFilePath) != nil
                        || Column(Attachment.Record.CodingKeys.localRelativeFilePathThumbnail) != nil
                        || Column(Attachment.Record.CodingKeys.audioWaveformRelativeFilePath) != nil
                        || Column(Attachment.Record.CodingKeys.videoStillFrameRelativeFilePath) != nil,
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
        var byteCount: UInt64 = 0
        for file in attachmentDirFiles {
            byteCount += (try? OWSFileSystem.fileSize(ofPath: file)) ?? 0
        }
        return byteCount
    }
}
