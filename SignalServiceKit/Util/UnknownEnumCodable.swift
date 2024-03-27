//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Conforming an enum type with an unknown case to this protocol causes it to decode unknown values as `.unknown`.
public protocol UnknownEnumCodable: Codable where Self: RawRepresentable, Self.RawValue: Decodable {
    static var unknown: Self { get }
}

public extension UnknownEnumCodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(RawValue.self)
        self = Self(rawValue: string) ?? .unknown
    }
}
