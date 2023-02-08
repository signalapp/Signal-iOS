//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Usernames {
    /// Facilitates sharing a username in various forms.
    struct ShareableUsername {
        private let username: String

        public init(username: String) {
            self.username = username
        }

        /// Returns a shareable string form.
        public var asString: String {
            username
        }

        /// Returns a string that looks similar to the shareable URL form, but
        /// is aesthetically shortened. Should not be treated as a valid URL.
        public var asShortUrlString: String {
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
            return urlString.dropFirst(2).asString
        }

        /// Returns a shareable URL form which links to this username's Signal
        /// account.
        public var asUrl: URL {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "signal.me"
            components.path = "/\(username)"

            guard let url = components.url else {
                owsFail("Unexpectedly failed to build shareable username URL!")
            }

            return url
        }
    }
}

private extension Substring {
    var asString: String {
        String(self)
    }
}
