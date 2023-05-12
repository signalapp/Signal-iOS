//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
import SignalServiceKit
import LibSignalClient

class SessionMigrationPerfTest: PerformanceBaseTest {
    static let newlyInitializedSessionStateData: Data = {
        let dataURL = Bundle(for: SessionMigrationPerfTest.self).url(forResource: "newlyInitializedSessionState",
                                                                     withExtension: "")!
        return try! Data(contentsOf: dataURL)
    }()

    static func makeNewlyInitializedSessionState() -> LegacySessionState {
        try! NSKeyedUnarchiver.unarchivedObject(
            ofClass: LegacySessionState.self,
            from: newlyInitializedSessionStateData,
            requiringSecureCoding: false
        )!
    }

    func makeDeepSession(depth: Int = 2000) -> LegacySessionRecord {
        let session = LegacySessionRecord()!

        for _ in 1...5 {
            session.archiveCurrentState()

            let state = Self.makeNewlyInitializedSessionState()
            session.setState(state)

            state.receivingChains = (1...5).map { _ in
                let senderRatchetKey = Curve25519.generateKeyPair().publicKey
                let chain = LegacyReceivingChain(chainKey: LegacyChainKey(data: senderRatchetKey, index: 0),
                                           senderRatchetKey: senderRatchetKey)!
                let dummyKeys = LegacyMessageKeys(cipherKey: Data(repeating: 1, count: 32),
                                            macKey: Data(repeating: 2, count: 32),
                                            iv: Data(repeating: 3, count: 16),
                                            index: 0)!
                chain.messageKeysList.addObjects(from: Array(repeating: dummyKeys, count: depth))
                return chain
            }
        }

        return session
    }

    override func setUp() {
        super.setUp()
        setUpIteration()
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
            _ = try! LegacySessionRecord(serializedProto: data)
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
            _ = try! SessionRecord(bytes: data)
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
            _ = try! LegacySessionRecord(serializedProto: data)
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
            _ = try! SessionRecord(bytes: data)
        }
    }
}
