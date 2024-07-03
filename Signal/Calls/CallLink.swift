//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit

struct CallLink {
    // MARK: -

    private enum Constants {
        static let scheme = "https"
        static let host = "signal.link"
        static let path = "/call/"
        static let legacyPath = "/call"
        static let key = "key"
    }

    // MARK: -

    let rootKey: CallLinkRootKey

    init(rootKey: CallLinkRootKey) {
        self.rootKey = rootKey
    }

    /// Parses a URL of the form: https://signal.link/call/#key=value
    init?(url: URL) {
        guard
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == Constants.scheme || components.scheme == UrlOpener.Constants.sgnlPrefix,
            components.user == nil,
            components.password == nil,
            components.host == Constants.host,
            components.port == nil,
            components.path == Constants.path || components.path == Constants.legacyPath,
            components.query == nil
        else {
            return nil
        }
        components.percentEncodedQuery = components.percentEncodedFragment
        guard
            let queryItems = components.queryItems?.filter({ $0.name == Constants.key }),
            queryItems.count == 1,
            let keyItem = queryItems.first,
            let keyValue = keyItem.value,
            let rootKey = try? CallLinkRootKey(keyValue)
        else {
            return nil
        }
        self.init(rootKey: rootKey)
    }

    static func generate() -> CallLink {
        let rootKey = CallLinkRootKey.generate()
        return CallLink(rootKey: rootKey)
    }

    func url() -> URL {
        var components = URLComponents()
        components.scheme = Constants.scheme
        components.host = Constants.host
        components.path = Constants.path
        components.queryItems = [
            URLQueryItem(name: Constants.key, value: rootKey.description),
        ]
        components.percentEncodedFragment = components.percentEncodedQuery
        components.query = nil
        return components.url!
    }
}
