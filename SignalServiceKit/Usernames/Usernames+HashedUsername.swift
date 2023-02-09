//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension Usernames {
    public class HashedUsername {
        private typealias LibSignalUsername = LibSignalClient.Username

        // MARK: Init

        private let libSignalUsername: LibSignalUsername

        convenience init(forUsername username: String) throws {
            self.init(libSignalUsername: try .init(username))
        }

        private init(libSignalUsername: LibSignalUsername) {
            self.libSignalUsername = libSignalUsername
        }

        // MARK: Getters

        public var usernameString: String {
            libSignalUsername.value
        }

        public lazy var hashString: String = {
            Data(libSignalUsername.hash).asBase64Url
        }()

        public lazy var proofString: String = {
            Data(libSignalUsername.generateProof()).asBase64Url
        }()
    }
}

// MARK: - Generate candidates

extension Usernames.HashedUsername {
    static func generateCandidates(
        forNickname nickname: String,
        minNicknameLength: UInt32,
        maxNicknameLength: UInt32
    ) throws -> [Usernames.HashedUsername] {
        return try LibSignalUsername.candidates(
            from: nickname,
            withValidLengthWithin: minNicknameLength...maxNicknameLength
        ).map { candidate -> Usernames.HashedUsername in
            return .init(libsignalUsername: candidate)
        }
    }
}

// MARK: - Equatable

extension Usernames.HashedUsername: Equatable {
    public static func == (lhs: Usernames.HashedUsername, rhs: Usernames.HashedUsername) -> Bool {
        lhs.libsignalUsername.value == rhs.libsignalUsername.value
    }
}
