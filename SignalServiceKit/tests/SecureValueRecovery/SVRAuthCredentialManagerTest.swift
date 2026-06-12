//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
@testable import SignalServiceKit

struct SVRAuthCredentialManagerTest {
    let credentialManager: SVRAuthCredentialManager
    let db = InMemoryDB()

    init() {
        self.credentialManager = SVRAuthCredentialManager.mock(storeCount: 2)
    }

    @Test
    func testGetCredentialForCurrentUsername() {
        let credential = SVR2AuthCredential(credential: RemoteAttestationAuth(username: "abc", password: "123"))
        db.write { tx in
            credentialManager.storeAuthCredentialForCurrentUsername(credential, tx)
        }
        let authCredential = db.read { tx in
            return credentialManager.getAuthCredentialForCurrentUser(tx)
        }
        #expect(authCredential?.credential.username == credential.credential.username)
        #expect(authCredential?.credential.password == credential.credential.password)
    }

    @Test
    func testDeleteInvalidCredentials() throws {
        let credential1 = SVR2AuthCredential(credential: RemoteAttestationAuth(username: "c1", password: "p1"))
        let credential2 = SVR2AuthCredential(credential: RemoteAttestationAuth(username: "c2", password: "p1"))
        let credential3 = SVR2AuthCredential(credential: RemoteAttestationAuth(username: "c3", password: "p2"))
        db.write { tx in
            credentialManager.storeAuthCredentialForCurrentUsername(credential1, tx)
            credentialManager.storeAuthCredentialForCurrentUsername(credential2, tx)
            credentialManager.storeAuthCredentialForCurrentUsername(credential3, tx)
        }
        do {
            let credential0 = SVR2AuthCredential(credential: RemoteAttestationAuth(username: "c1", password: "p2"))
            db.write { tx in
                credentialManager.deleteInvalidCredentials([credential0], tx)
            }
            let authCredentialCount = db.read { tx in
                return credentialManager.getAuthCredentials(tx).count
            }
            try #require(authCredentialCount == 3)
        }
        do {
            db.write { tx in
                credentialManager.deleteInvalidCredentials([credential1], tx)
            }
            let authCredentialCount = db.read { tx in
                return credentialManager.getAuthCredentials(tx).count
            }
            try #require(authCredentialCount == 2)
        }
    }

    @Test
    func testRemoveCredentialsForCurrentUser() {
        let credential = SVR2AuthCredential(credential: RemoteAttestationAuth(username: "abc", password: "123"))
        db.write { tx in
            credentialManager.storeAuthCredentialForCurrentUsername(credential, tx)
        }
        db.write { tx in
            credentialManager.removeSVR2CredentialsForCurrentUser(tx)
        }
        let authCredential = db.read { tx in
            return credentialManager.getAuthCredentialForCurrentUser(tx)
        }
        #expect(authCredential == nil)
    }
}
