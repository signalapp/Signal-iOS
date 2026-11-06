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

struct SVRAuthCredentialDistributedTest {
    @Test
    func testTwoSignalOneCloud() {
        let db = InMemoryDB()
        // Each device has its own "local" store.
        let localStore1 = KeyValueStore(collection: "Local.1")
        let localStore2 = KeyValueStore(collection: "Local.2")
        // But they share a single "cloud" store.
        let cloudStore = KeyValueStore(collection: "Cloud")

        let manager1 = SVRAuthCredentialManager(
            credentialStores: [localStore1, cloudStore].map(SVRAuthCredentialLocalStore.init(kvStore:)),
            usernameStore: localStore1,
        )
        let manager2 = SVRAuthCredentialManager(
            credentialStores: [localStore2, cloudStore].map(SVRAuthCredentialLocalStore.init(kvStore:)),
            usernameStore: localStore2,
        )

        // These are used to allow reading from individual stores.
        let localOnly1 = SVRAuthCredentialManager(
            credentialStores: [SVRAuthCredentialLocalStore(kvStore: localStore1)],
            usernameStore: localStore1,
        )
        let localOnly2 = SVRAuthCredentialManager(
            credentialStores: [SVRAuthCredentialLocalStore(kvStore: localStore2)],
            usernameStore: localStore2,
        )
        let cloudOnly = SVRAuthCredentialManager(
            credentialStores: [SVRAuthCredentialLocalStore(kvStore: cloudStore)],
            usernameStore: KeyValueStore(collection: ""),
        )

        func getUsernames(_ manager: SVRAuthCredentialManager) -> Set<String> {
            return Set(db.read { tx in
                return manager.getAuthCredentials(tx).map(\.credential.username)
            })
        }

        // Store a credential on Device 1.
        let username1 = Randomness.generateRandomBytes(10).hexadecimalString
        db.write { tx in
            let credential = SVR2AuthCredential(credential: RemoteAttestationAuth(username: username1, password: "asdf"))
            manager1.storeAuthCredentialForCurrentUsername(credential, tx)
        }
        // Store a credential on Device 2.
        let username2 = Randomness.generateRandomBytes(10).hexadecimalString
        db.write { tx in
            let credential = SVR2AuthCredential(credential: RemoteAttestationAuth(username: username2, password: "asdf"))
            manager2.storeAuthCredentialForCurrentUsername(credential, tx)
        }

        // At this point, both credentials are accessible.
        #expect(getUsernames(manager1).contains(username1))
        #expect(getUsernames(cloudOnly).contains(username1))
        #expect(getUsernames(localOnly1).contains(username1))
        #expect(getUsernames(manager2).contains(username2))
        #expect(getUsernames(cloudOnly).contains(username2))
        #expect(getUsernames(localOnly2).contains(username2))

        // Remove the credential on Device 1.
        db.write { tx in
            manager1.removeSVR2CredentialsForCurrentUser(tx)
        }
        // It's totally gone from everything Device 1 can access.
        #expect(!getUsernames(manager1).contains(username1))
        #expect(!getUsernames(cloudOnly).contains(username1))
        #expect(!getUsernames(localOnly1).contains(username1))
        // But Device 2's credential is still accessible to Device 2.
        #expect(getUsernames(manager2).contains(username2))
        #expect(getUsernames(cloudOnly).contains(username2))
        #expect(getUsernames(localOnly2).contains(username2))

        // Store a new credential on Device 2.
        db.write { tx in
            let credential = SVR2AuthCredential(credential: RemoteAttestationAuth(username: username2, password: "1234"))
            manager2.storeAuthCredentialForCurrentUsername(credential, tx)
        }
        // And ensure that username1 is still gone.
        #expect(!getUsernames(manager1).contains(username1))
        #expect(!getUsernames(cloudOnly).contains(username1))
        #expect(!getUsernames(localOnly1).contains(username1))
        #expect(getUsernames(manager2).contains(username2))
        #expect(getUsernames(cloudOnly).contains(username2))
        #expect(getUsernames(localOnly2).contains(username2))
    }
}

struct SVRAuthCredentialConsolidationTest {

    typealias AuthCredential = SVRAuthCredentialManager.AuthCredential

    // NOTE: "passwords" here are written as if they were user-inputted
    // passwords in the conventional sense. In a real auth credential,
    // they are not that. It just makes the tests easier and more fun.

    @Test
    func testConsolidation_noOverlap() {
        let now = Date()
        let consolidated = SVRAuthCredentialManager.consolidateCredentials(allUnsortedCredentials: [
            .init(username: "luke", password: "vaderismyfather", insertionTime: now),
            .init(username: "vader", password: "lukeismyson", insertionTime: now.addingTimeInterval(-1)),
        ])
        #expect(consolidated.map(\.username) == ["luke", "vader"])
    }

    @Test
    func testConsolidation_latestPerUsername() {
        let now = Date()
        let consolidated = SVRAuthCredentialManager.consolidateCredentials(allUnsortedCredentials: [
            .init(username: "luke", password: "leiaismysister?!?", insertionTime: now),
            .init(username: "luke", password: "vaderismyfather", insertionTime: now.addingTimeInterval(-2)),
            .init(username: "vader", password: "lukeismyson", insertionTime: now.addingTimeInterval(-1)),
        ])
        #expect(consolidated.map(\.username) == ["luke", "vader"])
        #expect(consolidated.map(\.password) == ["leiaismysister?!?", "lukeismyson"])
    }

    @Test
    func testConsolidation_sameCredentialDoesntUpdateDate() {
        let now = Date()
        let consolidated = SVRAuthCredentialManager.consolidateCredentials(allUnsortedCredentials: [
            .init(username: "luke", password: "vaderismyfather", insertionTime: now),
            .init(username: "luke", password: "vaderismyfather", insertionTime: now.addingTimeInterval(-2)),
            .init(username: "vader", password: "lukeismyson", insertionTime: now.addingTimeInterval(-1)),
        ])
        #expect(consolidated.map(\.username) == ["vader", "luke"])
        #expect(consolidated.map(\.password) == ["lukeismyson", "vaderismyfather"])
        #expect(consolidated.map(\.insertionTime) == [now.addingTimeInterval(-1), now.addingTimeInterval(-2)])
    }

    @Test
    func testConsolidation_greaterThanMaxCount() {
        let now = Date()
        var credentials = [AuthCredential]()
        var expectedConsolidatedCredentials = [AuthCredential]()
        for i in 0..<(SVR.maxSVRAuthCredentialsBackedUp * 2) {
            var credential = AuthCredential(
                username: "\(i)",
                password: "\(i)",
                insertionTime: now.addingTimeInterval(Double(-i)),
            )
            credentials.append(credential)
            if i < SVR.maxSVRAuthCredentialsBackedUp {
                expectedConsolidatedCredentials.append(credential)
            }
            for j in 1...5 {
                // Add extra entries per each username, should only keep the latest one.
                credential = AuthCredential(
                    username: "\(i)",
                    password: "\(i)_\(j)",
                    insertionTime: now.addingTimeInterval(Double(-i - j)),
                )
                credentials.append(credential)
            }
        }
        // We inserted them in order. To test sorting, scramble them.
        credentials = credentials.shuffled()
        let consolidated = SVRAuthCredentialManager.consolidateCredentials(allUnsortedCredentials: credentials)
        #expect(consolidated == expectedConsolidatedCredentials)
    }
}
