//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class KBSAuthCredentialStorageMock: KBSAuthCredentialStorage {

    public var currentUsername: String?
    public var dict = [String: KBSAuthCredential]()

    public init() {}

    public func storeAuthCredentialForCurrentUsername(_ auth: KBSAuthCredential, _ transaction: DBWriteTransaction) {
        dict[auth.username] = auth
        currentUsername = auth.username
    }

    public func getAuthCredentials(_ transaction: DBReadTransaction) -> [KBSAuthCredential] {
        return Array(dict.values)
    }

    public func getAuthCredentialForCurrentUser(_ transaction: DBReadTransaction) -> KBSAuthCredential? {
        guard let currentUsername = currentUsername else {
            return nil
        }
        return dict[currentUsername]
    }

    public func deleteInvalidCredentials(_ invalidCredentials: [KBSAuthCredential], _ transaction: DBWriteTransaction) {
        invalidCredentials.lazy.map(\.username).forEach { dict[$0] = nil }
    }
}
#endif
