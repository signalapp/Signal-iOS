//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct AuthCredentialSalt {
    public let rawValue: Data

    public init(rawValue: Data) throws {
        guard rawValue.count == 16 else {
            throw OWSGenericError("auth credential salt must be 16 bytes")
        }
        self.rawValue = rawValue
    }
}
