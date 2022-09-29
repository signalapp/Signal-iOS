//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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
