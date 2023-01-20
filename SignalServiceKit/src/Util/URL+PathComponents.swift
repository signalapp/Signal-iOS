//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension URL {
    private static let allowedCharacters: CharacterSet = {
        var result = CharacterSet.urlPathAllowed
        result.remove("/")
        return result
    }()

    init?(pathComponents: [String]) {
        let string: String = pathComponents
            .compactMap { $0.nilIfEmpty?.addingPercentEncoding(withAllowedCharacters: Self.allowedCharacters) }
            .joined(separator: "/")

        self.init(string: string)
    }
}
