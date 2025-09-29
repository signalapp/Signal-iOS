//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

final public class MockUsernameLinkManager: UsernameLinkManager {
    var entropyToGenerate: Result<Data, Error>?
    public func generateEncryptedUsername(username: String, existingEntropy: Data?) throws -> (entropy: Data, encryptedUsername: Data) {
        if let existingEntropy {
            return (existingEntropy, Data())
        }

        guard let entropyToGenerate else {
            owsFail("No mock set!")
        }

        self.entropyToGenerate = nil

        switch entropyToGenerate {
        case .success(let entropy):
            return (entropy, Data())
        case .failure(let error):
            throw error
        }
    }

    var decryptEncryptedLinkMocks = [(Usernames.UsernameLink) async throws -> String?]()
    public func decryptEncryptedLink(link: Usernames.UsernameLink) async throws -> String? {
        return try await decryptEncryptedLinkMocks.removeFirst()(link)
    }
}

#endif
