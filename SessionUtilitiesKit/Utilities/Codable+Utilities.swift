// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public extension Decodable {
    static func decoded<CodingKeys: CodingKey>(with container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Self {
        return try container.decode(Self.self, forKey: key)
    }
}
