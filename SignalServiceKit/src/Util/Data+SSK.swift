//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension Data {

    // MARK: -

    // base64url is _not_ the same as base64.  It is a
    // URL- and filename-safe variant of base64.
    //
    // See: https://tools.ietf.org/html/rfc4648#section-5
    static func data(fromBase64Url base64Url: String) throws -> Data {
        let base64 = Self.base64UrlToBase64(base64Url: base64Url)
        guard let data = Data(base64Encoded: base64) else {
            throw OWSAssertionError("Couldn't parse base64Url.")
        }
        return data
    }

    var asBase64Url: String {
        let base64 = base64EncodedString()
        return Self.base64ToBase64Url(base64: base64)
    }

    private static func base64UrlToBase64(base64Url: String) -> String {
        var base64 = base64Url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if base64.count % 4 != 0 {
            base64.append(String(repeating: "=", count: 4 - base64.count % 4))
        }
        return base64
    }

    private static func base64ToBase64Url(base64: String) -> String {
        let base64Url = base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return base64Url
    }
}
