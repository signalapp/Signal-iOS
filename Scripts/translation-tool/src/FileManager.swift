//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension FileManager {
    /// Copies an item, replacing the destination if it already exists.
    func copyItem(at srcURL: URL, replacingItemAt dstURL: URL) throws {
        do {
            try removeItem(at: dstURL)
        } catch CocoaError.fileNoSuchFile {
            // not an error if the file doesn't exist
        }
        try createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try copyItem(at: srcURL, to: dstURL)
    }
}
