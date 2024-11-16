//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import LibSignalClient

@testable import SignalServiceKit

class SessionStoreTest: SSKBaseTest {
    func testLegacySessionIsDropped() {
        @objc(FakeLegacySession) class FakeLegacySession: NSObject, NSCoding {
            override init() {
            }

            required init?(coder: NSCoder) {
                fatalError("should never be deserialized")
            }

            func encode(with coder: NSCoder) {
                // no properties
            }
        }

        // We have to use the database-based KeyValueStore to test this
        // because the in-memory one skips the archiving step.
        let sessionStore = SSKSessionStore(for: .aci, recipientIdFinder: DependenciesBridge.shared.recipientIdFinder)
        let recipient = write {
            DependenciesBridge.shared.recipientFetcher.fetchOrCreate(serviceId: Aci.randomForTesting(), tx: $0.asV2Write)
        }

        // First make sure that if we write a "valid" session, it can be read.
        let singleValidSessionData = try! NSKeyedArchiver.archivedData(withRootObject: [1: Data()], requiringSecureCoding: true)
        write {
            sessionStore.keyValueStoreForTesting.setData(singleValidSessionData, key: recipient.uniqueId, transaction: $0.asV2Write)
        }

        read {
            XCTAssertTrue(sessionStore.mightContainSession(for: recipient, tx: $0.asV2Read))
            XCTAssertNotNil(try! sessionStore.loadSession(for: recipient.aci!, deviceId: 1, tx: $0.asV2Read))
        }

        // Then imitate a session store with a mix of legacy and modern sessions.
        let sessions: NSDictionary = [1: FakeLegacySession(), 2: Data()]
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("SSKLegacySessionClassThatNoLongerExists", for: FakeLegacySession.self)
        archiver.encode(sessions, forKey: NSKeyedArchiveRootObjectKey)

        write {
            sessionStore.keyValueStoreForTesting.setData(archiver.encodedData, key: recipient.uniqueId, transaction: $0.asV2Write)
        }

        read {
            // There's something in the store...
            XCTAssertTrue(sessionStore.mightContainSession(for: recipient, tx: $0.asV2Read))
            // ...but it turns into nil on load.
            XCTAssertNil(try! sessionStore.loadSession(for: recipient.aci!, deviceId: 2, tx: $0.asV2Read))
        }
    }
}
