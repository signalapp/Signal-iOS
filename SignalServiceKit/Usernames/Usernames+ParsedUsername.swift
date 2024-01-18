//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

public extension Usernames {
    /// Represents a username parsed into its user-generated nickname and
    /// programmatically-generated numeric discriminator.
    struct ParsedUsername: Equatable {
        public static let separator: Character = "."

        public let nickname: String
        public let discriminator: String

        public init?(rawUsername: String?) {
            guard let rawUsername else {
                return nil
            }

            let components = rawUsername.split(separator: Self.separator)

            guard components.count == 2 else {
                owsFailDebug("Unexpected component count!")
                return nil
            }

            guard
                let nickname = String(components.first!).nilIfEmpty,
                let discriminator = String(components.last!).nilIfEmpty
            else {
                owsFailDebug("Nickname or discriminator was empty!")
                return nil
            }

            self.nickname = nickname
            self.discriminator = discriminator
        }

        init(nickname: String, discriminator: String) {
            self.nickname = nickname
            self.discriminator = discriminator
        }

        public var reassembled: String {
            "\(nickname)\(Self.separator)\(discriminator)"
        }

        public func updatingNickame(
            newNickname: String
        ) -> ParsedUsername {
            return ParsedUsername(
                nickname: newNickname,
                discriminator: discriminator
            )
        }
    }
}
