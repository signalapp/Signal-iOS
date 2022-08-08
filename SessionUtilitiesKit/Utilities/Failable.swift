// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

/// The `Failable<T>` type allows for coding an array of values without failing the entire array if a single
/// value fails to encode/decode correctly
public struct Failable<T: Codable>: Codable {
    public let value: T?

    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.singleValueContainer() else {
            self.value = nil
            return
        }

        self.value = try? container.decode(T.self)
    }

    public func encode(to encoder: Encoder) throws {
        guard let value: T = value else { return }

        var container: SingleValueEncodingContainer = encoder.singleValueContainer()

        try container.encode(value)
    }
}
