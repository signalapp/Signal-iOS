//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol TSResourceBackupThumbnail {

    var image: UIImage? { get }

    var resource: TSResource { get }

    // MARK: - Cached media properties

    var originalMimeType: String { get }

    var estimatedOriginalSizeInBytes: UInt32 { get }
}
