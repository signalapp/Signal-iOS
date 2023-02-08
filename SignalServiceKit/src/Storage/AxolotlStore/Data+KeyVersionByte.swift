//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Data {
    func prependKeyType() -> Data {
        return (self as NSData).prependKeyType() as Data
    }

    func removeKeyType() throws -> Data {
        return try (self as NSData).removeKeyType() as Data
    }
}
