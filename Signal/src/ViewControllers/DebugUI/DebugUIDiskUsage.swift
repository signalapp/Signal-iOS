//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUIDiskUsage: DebugUIPage {

    let name =  "Orphans & Disk Usage"

    func section(thread: TSThread?) -> OWSTableSection? {
        return OWSTableSection(title: name, items: [
            OWSTableItem(title: "Audit & Log",
                         actionBlock: { OWSOrphanDataCleaner.auditAndCleanup(false) }),
            OWSTableItem(title: "Audit & Clean Up",
                         actionBlock: { OWSOrphanDataCleaner.auditAndCleanup(true) }),
            OWSTableItem(title: "Clear All Attachment Thumbnails",
                         actionBlock: { DebugUIDiskUsage.clearAllAttachmentThumbnails() }),
        ])
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
}

#endif
