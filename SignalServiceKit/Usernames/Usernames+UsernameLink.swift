//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

public extension Usernames {
    /// Represents a Signal Dot Me link allowing access to a user's username.
    ///
    /// The username itself is not encoded directly into this link. Instead, the
    /// link encodes "entropy data" and a "handle UUID".
    ///
    /// These links look like
    /// `{https,sgnl}://signal.me/#eu/{base64url-encoded data}`.
    struct UsernameLink: Equatable {
        private enum LinkUrlComponents {
            static let httpsScheme = "https"
            static let sgnlScheme = "sgnl"
            static let host = "signal.me"
            static let path = "/"
            static let fragmentPrefix = "eu/"
        }

        private enum Constants {
            /// The expected length of username link entropy data.
            static let expectedEntropyLength: Int = 32

            /// The known length of a UUID in bytes.
            static let knownUuidLength: Int = 16
        }

        /// An identifier used to fetch the encrypted form of a username from
        /// the service.
        public let handle: UUID

        /// Entropy used to derive keys with which an encrypted username can be
        /// decrypted.
        public let entropy: Data

        public init?(handle: UUID, entropy: Data) {
            guard entropy.count == Constants.expectedEntropyLength else {
                return nil
            }

            self.handle = handle
            self.entropy = entropy
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
                (
                    components.path == LinkUrlComponents.path
                    || components.path.isEmpty
                ),
                let fragment = components.fragment,
                fragment.hasPrefix(fragmentPrefix),
                components.query == nil,
                components.user == nil,
                components.password == nil,
                components.port == nil
            else {
                return nil
            }

            let base64LinkData = String(fragment.dropFirst(fragmentPrefix.count))

            let linkData: Data
            do {
                linkData = try .data(fromBase64Url: base64LinkData)
            } catch {
                return nil
            }

            let expectedLinkDataLength = Constants.expectedEntropyLength + Constants.knownUuidLength

            guard linkData.count == expectedLinkDataLength else {
                UsernameLogger.shared.warn("Link data was of unexpected length... \(linkData.count)")
                return nil
            }

            let entropyData = linkData[0..<Constants.expectedEntropyLength]
            let handleData = linkData[Constants.expectedEntropyLength..<expectedLinkDataLength]

            guard let handle = UUID(data: handleData) else {
                UsernameLogger.shared.warn("Failed to create UUID from link handle...")
                return nil
            }

            self.entropy = entropyData
            self.handle = handle
        }

        /// Returns this username link as a shareable URL.
        public var url: URL {
            let linkData: Data = entropy + handle.data
            let base64LinkData = linkData.asBase64Url

            var components = URLComponents()
            components.scheme = LinkUrlComponents.httpsScheme
            components.host = LinkUrlComponents.host
            components.path = LinkUrlComponents.path
            components.fragment = "\(LinkUrlComponents.fragmentPrefix)\(base64LinkData)"

            guard let url = components.url else {
                owsFail("Unexpectedly failed to build shareable username URL!")
            }

            return url
        }
    }
}
