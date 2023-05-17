//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Usernames {
    /// Represents a Signal Dot Me link pointing to a user's username. These
    /// URLs look like `{https,sgnl}://signal.me/#u/<base64-encoded username>`.
    struct UsernameLink: Equatable {
        private enum LinkUrlComponents {
            static let httpsScheme = "https"
            static let sgnlScheme = "sgnl"
            static let host = "signal.me"
            static let path = "/"
            static let fragmentPrefix = "u/"
        }

        public let username: String

        public init(username: String) {
            self.username = username
        }

        public init?(usernameLinkUrl: URL) {
            guard let components = URLComponents(
                url: usernameLinkUrl,
                resolvingAgainstBaseURL: true
            ) else {
                return nil
            }

            let fragmentPrefix = LinkUrlComponents.fragmentPrefix

            guard
                (
                    components.scheme == LinkUrlComponents.httpsScheme
                    || components.scheme == LinkUrlComponents.sgnlScheme
                ),
                components.host == LinkUrlComponents.host,
                components.path == LinkUrlComponents.path,
                let fragment = components.fragment,
                fragment.hasPrefix(fragmentPrefix),
                components.query == nil,
                components.user == nil,
                components.password == nil,
                components.port == nil
            else {
                return nil
            }

            let base64UrlUsername = String(fragment.dropFirst(fragmentPrefix.count))

            let usernameData: Data
            do {
                usernameData = try .data(fromBase64Url: base64UrlUsername)
            } catch {
                return nil
            }

            guard let username = String(data: usernameData, encoding: .utf8) else {
                return nil
            }

            self.username = username
        }

        /// Returns an aesthetically modified string for displaying the username
        /// link. Should not be treated as a valid URL.
        public var asAestheticUrlString: String {
            guard
                var components = URLComponents(url: asUrl, resolvingAgainstBaseURL: true)
            else {
                owsFail("Unexpectedly failed to get components for shareable short URL string!")
            }

            components.scheme = nil

            guard let urlString = components.url?.absoluteString else {
                owsFail("Unexpectedly failed to get URL after stripping scheme!")
            }

            // After we drop the scheme there will still be a `//` at the
            // front, per RFC 3986 - so we drop those chars manually.
            return String(urlString.dropFirst(2))
        }

        /// Returns this username link as a shareable URL.
        public var asUrl: URL {
            let base64Username = {
                guard let usernameData = username.data(using: .utf8) else {
                    owsFail("Failed to get UTF-8 data for the username!")
                }

                return usernameData.asBase64Url
            }()

            var components = URLComponents()
            components.scheme = LinkUrlComponents.httpsScheme
            components.host = LinkUrlComponents.host
            components.path = LinkUrlComponents.path
            components.fragment = "\(LinkUrlComponents.fragmentPrefix)\(base64Username)"

            guard let url = components.url else {
                owsFail("Unexpectedly failed to build shareable username URL!")
            }

            return url
        }
    }
}
