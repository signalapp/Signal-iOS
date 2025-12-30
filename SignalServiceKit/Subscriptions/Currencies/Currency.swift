//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum Currency {
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
        for codes: any Sequence<Code>,
        ignoreMissingNames: Bool,
        shouldSort: Bool,
    ) -> [Info] {
#if TESTABLE_BUILD
        owsPrecondition(Array(codes).count == Set(codes).count)
#endif
        var infos = codes.compactMap { Info(code: $0, ignoreMissingName: ignoreMissingNames) }
        if shouldSort { infos.sort { $0.name < $1.name } }
        return infos
    }

    // MARK: -

    public enum Symbol: Equatable {
        case before(String)
        case after(String)
        case currencyCode

        private static let symbols: [Currency.Code: Symbol] = [
            "USD": .before("$"),
            "AUD": .before("A$"),
            "BRL": .before("R$"),
            "GBP": .before("£"),
            "CAD": .before("CA$"),
            "CNY": .before("CN¥"),
            "EUR": .before("€"),
            "HKD": .before("HK$"),
            "INR": .before("₹"),
            "JPY": .before("¥"),
            "KRW": .before("₩"),
            "PLN": .after("zł"),
            "SEK": .after("kr"),
        ]

        public static func `for`(currencyCode: Currency.Code) -> Symbol {
            return symbols[currencyCode, default: .currencyCode]
        }
    }
}
