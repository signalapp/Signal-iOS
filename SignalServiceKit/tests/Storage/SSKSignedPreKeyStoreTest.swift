//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

private extension SSKSignedPreKeyStore {
    func loadSignedPreKey(_ id: Int32) -> SignedPreKeyRecord? {
        return self.databaseStorage.read { transaction in
            loadSignedPreKey(id, transaction: transaction)
        }
    }

    var countSignedPreKeys: Int {
        return self.databaseStorage.read { transaction in
            loadSignedPreKeys(with: transaction).count
        }
    }
}

class SSKSignedPreKeyStoreTest: SSKBaseTestSwift {
    func testPniStoreIsSeparate() {
        let aciStore = SSKSignedPreKeyStore(for: .aci)
        let pniStore = SSKSignedPreKeyStore(for: .pni)

        XCTAssertEqual(0, aciStore.countSignedPreKeys)
        XCTAssertEqual(0, pniStore.countSignedPreKeys)

        let days: Int32 = 3
        let lastPreKeyId = days

        for i in 0...days { // 4 signed keys are generated, one per day from now until 3 days ago.
            let secondsAgo = TimeInterval(i - days) * kDayInterval
            assert(secondsAgo <= 0, "Time in past must be negative")
            let generatedAt = Date(timeIntervalSinceNow: secondsAgo)
            let record = SignedPreKeyRecord(id: i,
                                            keyPair: ECKeyPair.generateKeyPair(),
                                            signature: Data(),
                                            generatedAt: generatedAt)
            self.databaseStorage.write { transaction in
                aciStore.storeSignedPreKey(i, signedPreKeyRecord: record, transaction: transaction)
            }
        }

        XCTAssertEqual(4, aciStore.countSignedPreKeys)
        XCTAssertNotNil(aciStore.loadSignedPreKey(lastPreKeyId))

        for i in 0...days { // 4 signed keys are generated, one per day from now until 3 days ago.
            let secondsAgo = TimeInterval(i - days) * kDayInterval
            assert(secondsAgo <= 0, "Time in past must be negative")
            let generatedAt = Date(timeIntervalSinceNow: secondsAgo)
            let record = SignedPreKeyRecord(id: i,
                                            keyPair: ECKeyPair.generateKeyPair(),
                                            signature: Data(),
                                            generatedAt: generatedAt)
            self.databaseStorage.write { transaction in
                pniStore.storeSignedPreKey(i, signedPreKeyRecord: record, transaction: transaction)
            }
        }

        XCTAssertEqual(4, pniStore.countSignedPreKeys)
        XCTAssertNotNil(pniStore.loadSignedPreKey(lastPreKeyId))

        self.databaseStorage.write { transaction in
            aciStore.removeSignedPreKey(lastPreKeyId, transaction: transaction)
        }

        XCTAssertNil(aciStore.loadSignedPreKey(lastPreKeyId))
        XCTAssertNotNil(pniStore.loadSignedPreKey(lastPreKeyId))
    }

    func testGenerateWithCorrectSignature() {
        let identityManager = DependenciesBridge.shared.identityManager

        let aciStore = SSKSignedPreKeyStore(for: .aci)
        let pniStore = SSKSignedPreKeyStore(for: .pni)

        let aciIdentity = identityManager.generateAndPersistNewIdentityKey(for: .aci)
        let aciRecord = aciStore.generateRandomSignedRecord()
        let aciPublicKey = aciIdentity.identityKeyPair.publicKey
        XCTAssert(try! aciPublicKey.verifySignature(message: aciRecord.keyPair.identityKeyPair.publicKey.serialize(),
                                                   signature: aciRecord.signature))

        let pniIdentity = identityManager.generateAndPersistNewIdentityKey(for: .pni)
        let pniRecord = pniStore.generateRandomSignedRecord()
        let pniPublicKey = pniIdentity.identityKeyPair.publicKey
        XCTAssert(try! pniPublicKey.verifySignature(message: pniRecord.keyPair.identityKeyPair.publicKey.serialize(),
                                                    signature: pniRecord.signature))
    }
}
