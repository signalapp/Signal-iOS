//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct AuthCredentialSalt: Codable {
    public let rawValue: Data

    public init(rawValue: Data) throws {
        guard rawValue.count == 16 else {
            throw OWSGenericError("auth credential salt must be 16 bytes")
        }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(Data.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}
