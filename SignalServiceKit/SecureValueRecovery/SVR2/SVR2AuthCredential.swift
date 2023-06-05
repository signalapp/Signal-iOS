//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Transparent wrapper that exists purely to make it clear to readers
// that the credential must be for SVR2, not an arbitrary RemoteAttestation.Auth.
public struct SVR2AuthCredential: Equatable, Codable {
    public let credential: RemoteAttestation.Auth

    public init(credential: RemoteAttestation.Auth) {
        self.credential = credential
    }
}

public enum SVR2 {
    /// An auth credential is needed to talk to the SVR server.
    /// This defines how we should get that auth credential
    public indirect enum AuthMethod: Equatable {
        /// Explicitly provide an auth credential to use directly with SVR2.
        /// note: if it fails, will fall back to the backup or implicit if unset.
        case svrAuth(SVR2AuthCredential, backup: AuthMethod?)
        /// Get an SVR2 auth credential from the chat server first with the
        /// provided credentials, then use it to talk to the SVR2 server.
        case chatServerAuth(AuthedAccount)
        /// Use whatever SVR2 auth credential we have cached; if unavailable or
        /// if invalid, falls back to getting a SVR2 auth credential from the chat server
        /// with the chat server auth credentials we have cached.
        case implicit
    }
}
