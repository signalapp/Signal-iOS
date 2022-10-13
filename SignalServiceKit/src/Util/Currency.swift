//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct Currency {
    public typealias Code = String
    public struct Info {
        public let code: Code
        public let name: String

        public init(code: Code, name: String) {
            self.code = code
            self.name = name
        }

        public init?(code: Code, ignoreMissingName: Bool = false) {
            if let name = Currency.name(for: code) {
                self.init(code: code, name: name)
            } else if ignoreMissingName {
                self.init(code: code, name: code)
            } else {
                return nil
            }
        }
    }

    public static func name(for code: Code) -> String? {
        Locale.current.localizedString(forCurrencyCode: code)
    }

    public static func infos(
        for codes: [Code],
        ignoreMissingNames: Bool,
        shouldSort: Bool
    ) -> [Info] {
        owsAssertDebug(codes.count == Set(codes).count)
        var infos = codes.compactMap { Info(code: $0, ignoreMissingName: ignoreMissingNames) }
        if shouldSort { infos.sort { $0.name < $1.name } }
        return infos
    }
}
