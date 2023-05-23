//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class SVRAuthCredentialStorageMock: SVRAuthCredentialStorage {

    public var dict: [String: SVRAuthCredential] {
        get { return kbsDict }
        set { kbsDict = newValue }
    }
    public var currentUsername: String? {
        get { return currentKBSUsername }
        set { currentKBSUsername = newValue }
    }

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

    // MARK: - KBS

    public var currentKBSUsername: String?
    public var kbsDict = [String: KBSAuthCredential]()

    public func storeAuthCredentialForCurrentUsername(_ auth: KBSAuthCredential, _ transaction: DBWriteTransaction) {
        kbsDict[auth.credential.username] = auth
        currentKBSUsername = auth.credential.username
    }

    public func getAuthCredentials(_ transaction: DBReadTransaction) -> [KBSAuthCredential] {
        return Array(kbsDict.values)
    }

    public func getAuthCredentialForCurrentUser(_ transaction: DBReadTransaction) -> KBSAuthCredential? {
        guard let currentUsername = currentKBSUsername else {
            return nil
        }
        return kbsDict[currentUsername]
    }

    public func deleteInvalidCredentials(_ invalidCredentials: [KBSAuthCredential], _ transaction: DBWriteTransaction) {
        invalidCredentials.lazy.map(\.credential.username).forEach { kbsDict[$0] = nil }
    }
}
#endif
