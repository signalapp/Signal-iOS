//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

import libwebp
import YYImage

extension NSData {
    @objc
    @available(swift, obsoleted: 1)
    public func imageMetadata(withPath filePath: String?, mimeType: String?) -> ImageMetadata {
        (self as Data).imageMetadata(withPath: filePath, mimeType: mimeType)
    }
}
