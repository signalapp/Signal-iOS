//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

#if USE_DEBUG_UI

class DebugUIDiskUsage: DebugUIPage, Dependencies {

    let name =  "Orphans & Disk Usage"

    func section(thread: TSThread?) -> OWSTableSection? {
        return OWSTableSection(title: name, items: [
            OWSTableItem(title: "Audit & Log",
                         actionBlock: { OWSOrphanDataCleaner.auditAndCleanup(false) }),
            OWSTableItem(title: "Audit & Clean Up",
                         actionBlock: { OWSOrphanDataCleaner.auditAndCleanup(true) }),
            OWSTableItem(title: "Save All Attachments",
                         actionBlock: { DebugUIDiskUsage.saveAllAttachments() }),
            OWSTableItem(title: "Clear All Attachment Thumbnails",
                         actionBlock: { DebugUIDiskUsage.clearAllAttachmentThumbnails() }),
            OWSTableItem(title: "Delete Messages older than 3 Months",
                         actionBlock: { DebugUIDiskUsage.deleteOldMessages_3Months() })
        ])
    }

    // MARK: -

    private static func saveAllAttachments() {
        databaseStorage.write { transaction in
            var attachmentStreams: [TSAttachmentStream] = []
            TSAttachment.anyEnumerate(transaction: transaction) { attachment, _ in
                guard let attachmentStream = attachment as? TSAttachmentStream else { return }
                attachmentStreams.append(attachmentStream)
            }
            Logger.info("Saving \(attachmentStreams.count) attachment streams.")

            // Persist the new localRelativeFilePath property of TSAttachmentStream.
            // For performance, we want to upgrade all existing attachment streams in
            // a single transaction.
            attachmentStreams.forEach { attachmentStream in
                attachmentStream.anyUpdate(transaction: transaction) { _ in
                    // Do nothing, rewriting is sufficient.
                }
            }
        }
    }

    private static func clearAllAttachmentThumbnails() {
        let fileManager = FileManager.default
        guard let cacheContents = fileManager.enumerator(
            at: URL(fileURLWithPath: OWSFileSystem.cachesDirectoryPath()),
            includingPropertiesForKeys: nil,
            options: [ .skipsSubdirectoryDescendants ],
            errorHandler: { url, error in
                Logger.warn("could not visit \(url): \(error)")
                return true
            }
        ) else {
            Logger.error("Failed to enumerate caches.")
            return
        }

        var removedCount: UInt = 0
        for case let cacheItem as URL in cacheContents {
            let itemName = cacheItem.lastPathComponent
            guard itemName.hasSuffix("-thumbnails") || itemName.hasSuffix("-signal-ios-thumbnail.jpg") else { continue }

            do {
                try fileManager.removeItem(at: cacheItem)
                removedCount += 1
            } catch {
                Logger.warn("Could not remove \(cacheItem): \(error)")
            }
        }
        Logger.info("Deleted \(removedCount) items.")
    }

    private static func deleteOldMessages_3Months() {
        deleteOldMessages(maxAgeSeconds: kMonthInterval * 3)
    }

    private static func deleteOldMessages(maxAgeSeconds: TimeInterval) {
        databaseStorage.write { transaction in
            let threadIds = TSThread.anyAllUniqueIds(transaction: transaction)
            var interactionsToDelete: [TSInteraction] = []
            for threadId in threadIds {
                let interactionFinder = InteractionFinder(threadUniqueId: threadId)
                do {
                    try interactionFinder.enumerateRecentInteractions(transaction: transaction) { interaction, stop in
                        let ageSeconds = abs(interaction.receivedAtDate.timeIntervalSinceNow)
                        if ageSeconds >= maxAgeSeconds {
                            interactionsToDelete.append(interaction)
                        }
                    }
                } catch { }
            }

            Logger.info("Deleting \(interactionsToDelete.count) interactions.")

            for interation in interactionsToDelete {
                interation.anyRemove(transaction: transaction)
            }
        }
    }
}

#endif
