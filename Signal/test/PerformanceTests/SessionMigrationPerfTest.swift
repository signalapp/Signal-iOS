//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
import AxolotlKit
import SignalServiceKit
import SignalClient

class SessionMigrationPerfTest: PerformanceBaseTest {
    func makeDeepSession(depth: Int = 2000) -> AxolotlKit.SessionRecord {
        let session = AxolotlKit.SessionRecord()!

        for _ in 1...5 {
            session.archiveCurrentState()

            let state = session.sessionState()!
            state.rootKey = RootKey(data: Curve25519.generateKeyPair().publicKey)
            let aliceParams = AliceAxolotlParameters(identityKey: Curve25519.generateKeyPair(),
                                                     theirIdentityKey: Curve25519.generateKeyPair().publicKey,
                                                     ourBaseKey: Curve25519.generateKeyPair(),
                                                     theirSignedPreKey: Curve25519.generateKeyPair().publicKey,
                                                     theirOneTimePreKey: nil,
                                                     theirRatchetKey: Curve25519.generateKeyPair().publicKey)
            try! RatchetingSession.initializeSession(state, sessionVersion: 3, aliceParameters: aliceParams)

            let receivingChains: [ReceivingChain] = (1...5).map { _ in
                let senderRatchetKey = Curve25519.generateKeyPair().publicKey
                let chain = ReceivingChain(chainKey: ChainKey(data: senderRatchetKey, index: 0),
                                           senderRatchetKey: senderRatchetKey)!
                let dummyKeys = MessageKeys(cipherKey: Data(repeating: 1, count: 32),
                                            macKey: Data(repeating: 2, count: 32),
                                            iv: Data(repeating: 3, count: 16),
                                            index: 0)!
                chain.messageKeysList.addObjects(from: Array(repeating: dummyKeys, count: depth))
                return chain
            }
            state.setValue(receivingChains, forKey: "receivingChains")
        }

        return session
    }

    func testSerializeDeepSession() {
        let x = makeDeepSession()
        measure {
            _ = try! x.serializeProto()
        }
    }

    func testDeserializeDeepSession() {
        let x = makeDeepSession()
        let data = try! x.serializeProto()
        measure {
            _ = try! SessionRecord(serializedProto: data)
        }
    }

    func testUnarchiveDeepSession() {
        let x = makeDeepSession()
        let data = NSKeyedArchiver.archivedData(withRootObject: x)
        measure {
            _ = NSKeyedUnarchiver.unarchiveObject(with: data)
        }
    }

    func testMigrateDeepSession() {
        let x = makeDeepSession()
        let data = try! x.serializeProto()
        measure {
            _ = try! SignalClient.SessionRecord(bytes: data)
        }
    }

    func testSerializeSomewhatDeepSession() {
        let x = makeDeepSession(depth: 200)
        measure {
            _ = try! x.serializeProto()
        }
    }

    func testDeserializeSomewhatDeepSession() {
        let x = makeDeepSession(depth: 200)
        let data = try! x.serializeProto()
        measure {
            _ = try! SessionRecord(serializedProto: data)
        }
    }

    func testUnarchiveSomewhatDeepSession() {
        let x = makeDeepSession(depth: 200)
        let data = NSKeyedArchiver.archivedData(withRootObject: x)
        measure {
            _ = NSKeyedUnarchiver.unarchiveObject(with: data)
        }
    }

    func testMigrateSomewhatDeepSession() {
        let x = makeDeepSession(depth: 200)
        let data = try! x.serializeProto()
        measure {
            _ = try! SignalClient.SessionRecord(bytes: data)
        }
    }
}
