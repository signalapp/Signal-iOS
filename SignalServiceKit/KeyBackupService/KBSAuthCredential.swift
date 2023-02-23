//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Transparent wrapper that exists purely to make it clear to readers
// that the credential must be for kbs, not an arbitrary RemoteAttestation.Auth.
public struct KBSAuthCredential: Equatable, Codable {
    public let credential: RemoteAttestation.Auth

    public var username: String { credential.username }

    public init(credential: RemoteAttestation.Auth) {
        self.credential = credential
    }
}
