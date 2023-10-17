//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class SVRAuthCredentialStorageMock: SVRAuthCredentialStorage {

    public init() {}

    // MARK: - SVR2

    public var currentSVR2Username: String?
    public var svr2Dict = [String: SVR2AuthCredential]()

    public func storeAuthCredentialForCurrentUsername(_ auth: SVR2AuthCredential, _ transaction: DBWriteTransaction) {
        svr2Dict[auth.credential.username] = auth
        currentSVR2Username = auth.credential.username
    }

    public func getAuthCredentials(_ transaction: DBReadTransaction) -> [SVR2AuthCredential] {
        return Array(svr2Dict.values)
    }

    public func getAuthCredentialForCurrentUser(_ transaction: DBReadTransaction) -> SVR2AuthCredential? {
        guard let currentUsername = currentSVR2Username else {
            return nil
        }
        return svr2Dict[currentUsername]
    }

    public func deleteInvalidCredentials(_ invalidCredentials: [SVR2AuthCredential], _ transaction: DBWriteTransaction) {
        invalidCredentials.lazy.map(\.credential.username).forEach { svr2Dict[$0] = nil }
    }

    public func removeSVR2CredentialsForCurrentUser(_ transaction: DBWriteTransaction) {
        guard let currentSVR2Username else { return }
        svr2Dict[currentSVR2Username] = nil
    }
}
#endif
