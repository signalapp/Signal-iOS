//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalRingRTC

struct CallLink {
    // MARK: -

    private enum Constants {
        static let scheme = "https"
        static let host = "signal.link"
        static let path = "/call/"
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
            components.scheme == Constants.scheme,
            components.user == nil,
            components.password == nil,
            components.host == Constants.host,
            components.port == nil,
            components.path == Constants.path,
            components.query == nil
        else {
            return nil
        }
        components.percentEncodedQuery = components.percentEncodedFragment
        guard
            let queryItems = components.queryItems,
            queryItems.count == 1,
            let keyItem = queryItems.first,
            keyItem.name == Constants.key,
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
