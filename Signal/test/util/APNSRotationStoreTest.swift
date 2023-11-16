//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalMessaging
@testable import SignalServiceKit

final class APNSRotationStoreTest: SignalBaseTest {

    lazy var messageFactory = IncomingMessageFactory()

    override func setUp() {
        super.setUp()

        let remoteConfigManager = self.remoteConfigManager as! StubbableRemoteConfigManager
        remoteConfigManager.cachedConfig = RemoteConfig(
            clockSkew: 0,
            isEnabledFlags: ["ios.enableAutoAPNSRotation": true],
            valueFlags: [:],
            timeGatedFlags: [:]
        )
    }

    override func tearDown() {
        super.tearDown()

        APNSRotationStore.nowMs = { return Date().ows_millisecondsSince1970 }
    }

    func testHasNoPushToken() {
        // Make sure we don't have an APNS token
        preferences.removeAllValues()
        let now = Date().ows_millisecondsSince1970

        // Make sure we are otherwise eligible to rotate, so
        // that we know it is the lack of an APNS token that stopped it.
        write { transaction in
            // Mark as checked in the past so that we'd be eligible after an app update.
            APNSRotationStore.nowMs = {
                return now
                    - APNSRotationStore.Constants.appVersionBakeTimeMs
                    - 1
            }
            APNSRotationStore.setAppVersionTimeForAPNSRotationIfNeeded(transaction: transaction)

            // Fake a missed message so we'd rotate.
            self.createIncomingMessage(
                receivedTimestamp: now - kMinuteInMs,
                transaction: transaction
            )
        }

        read {
            APNSRotationStore.nowMs = { now }
            // No rotation because there's no APNS token.
            XCTAssertFalse(APNSRotationStore.canRotateAPNSToken(transaction: $0))
        }

        // Set an APNS token.
        write { tx in
            preferences.setPushToken("123", tx: tx)
        }

        read {
            // Nothing changed but the token, but we should now rotate.
            XCTAssert(APNSRotationStore.canRotateAPNSToken(transaction: $0))
        }
    }

    func testHasWorkingPushToken() {
        let now = Date().ows_millisecondsSince1970

        // Make sure we are otherwise eligible to rotate, so
        // that we know it is having a good APNS token that stopped it.

        // Set an APNS token.
        write { tx in
            preferences.setPushToken("123", tx: tx)
        }

        write { transaction in
            // Mark as checked in the past so that we'd be eligible after an app update.
            APNSRotationStore.nowMs = {
                return now
                    - APNSRotationStore.Constants.appVersionBakeTimeMs
                    - 1
            }
            APNSRotationStore.setAppVersionTimeForAPNSRotationIfNeeded(transaction: transaction)
        }

        read {
            APNSRotationStore.nowMs = { now }
            // Make sure we need to rotate before marking the token as good.
            XCTAssert(APNSRotationStore.canRotateAPNSToken(transaction: $0))
        }

        // Now mark receiving a push (marking the token as working)
        write {
            APNSRotationStore.didReceiveAPNSPush(transaction: $0)
        }

        read {
            // The token should now be marked as good and not needing rotation.
            XCTAssertFalse(APNSRotationStore.canRotateAPNSToken(transaction: $0))
        }

        // Change the token!
        write { tx in
            preferences.setPushToken("abc", tx: tx)
        }

        read {
            // Now we need to rotate again because the token changed but we had missed
            // messages.
            XCTAssert(APNSRotationStore.canRotateAPNSToken(transaction: $0))
        }
    }

    func testHasWorkingPushTokenFromLongAgo() {
        let now = Date().ows_millisecondsSince1970

        // Make sure we are otherwise eligible to rotate, so
        // that we know the determining factor is the APNS token.

        // Set an APNS token.
        write { tx in
            preferences.setPushToken("123", tx: tx)
        }

        write { transaction in
            // Mark as checked in the past so that we'd be eligible after an app update.
            APNSRotationStore.nowMs = {
                return now
                    - APNSRotationStore.Constants.appVersionBakeTimeMs
                    - 1
            }
            APNSRotationStore.setAppVersionTimeForAPNSRotationIfNeeded(transaction: transaction)
        }

        read {
            APNSRotationStore.nowMs = { now }
            // Make sure we need to rotate before marking the token as good.
            XCTAssert(APNSRotationStore.canRotateAPNSToken(transaction: $0))
        }

        // Now mark receiving a push (marking the token as working)
        write {
            APNSRotationStore.didReceiveAPNSPush(transaction: $0)
        }

        read {
            // The token should now be marked as good and not needing rotation.
            XCTAssertFalse(APNSRotationStore.canRotateAPNSToken(transaction: $0))
        }

        // Let some time pass, but not too long.
        APNSRotationStore.nowMs = { now + APNSRotationStore.Constants.lastKnownWorkingAPNSTokenExpirationTimeMs - 1 }

        read {
            // Still no need to rotate, it was marked good a short time ago.
            XCTAssertFalse(APNSRotationStore.canRotateAPNSToken(transaction: $0))
        }

        // Now move the time far up, long since we marked the token as good,
        // so it can now be rotated.
        APNSRotationStore.nowMs = { now + APNSRotationStore.Constants.lastKnownWorkingAPNSTokenExpirationTimeMs + 1 }

        read {
            // Now we need to rotate because it was marked good too long ago.
            XCTAssert(APNSRotationStore.canRotateAPNSToken(transaction: $0))
        }
    }

    func testHasUpdatedRecently() {
        // Make sure we have an APNS Token
        write { tx in
            preferences.setPushToken("123", tx: tx)
        }
        let now = Date().ows_millisecondsSince1970

        // Should not want to rotate, because the NSE hasn't even had a chance
        // to write anything.
        read {
            APNSRotationStore.nowMs = { now }
            XCTAssertFalse(APNSRotationStore.canRotateAPNSToken(transaction: $0))
        }

        write {
            // mark the app version.
            APNSRotationStore.nowMs = { now }
            APNSRotationStore.setAppVersionTimeForAPNSRotationIfNeeded(transaction: $0)
        }

        read {
            // Simulate time having passed
            APNSRotationStore.nowMs = { now + APNSRotationStore.Constants.appVersionBakeTimeMs + 1 }
            // Now check, we should be eligible to rotate.
            XCTAssert(APNSRotationStore.canRotateAPNSToken(transaction: $0))
        }
    }

    func testHasRotatedRecently() {
        // Make sure we have an APNS Token
        write { tx in
            preferences.setPushToken("123", tx: tx)
        }
        let now = Date().ows_millisecondsSince1970

        // Make sure we are otherwise eligible to rotate, so
        // that we know it is the the recent rotation that stopped it.
        write { transaction in
            // Mark as checked in the past so that we'd be eligible after an app update.
            APNSRotationStore.nowMs = {
                return now
                    - APNSRotationStore.Constants.appVersionBakeTimeMs
                    - 1
            }
            APNSRotationStore.setAppVersionTimeForAPNSRotationIfNeeded(transaction: transaction)

            // But make a recent rotation.
            APNSRotationStore.nowMs = { now - APNSRotationStore.Constants.minRotationInterval + 1 }
            APNSRotationStore.didRotateAPNSToken(transaction: transaction)
        }

        read {
            APNSRotationStore.nowMs = { now }
            // No rotation because we just rotated recently.
            XCTAssertFalse(APNSRotationStore.canRotateAPNSToken(transaction: $0))

            // Move time forward.
            APNSRotationStore.nowMs = { now + APNSRotationStore.Constants.minRotationInterval + 1 }
            // Now we want to rotate
            XCTAssert(APNSRotationStore.canRotateAPNSToken(transaction: $0))
        }
    }

    func testRecentMissedMessages() {
        // Make sure we have an APNS Token
        write { tx in
            preferences.setPushToken("123", tx: tx)
        }
        let now = Date().ows_millisecondsSince1970

        let lastPushTime = now
            - APNSRotationStore.Constants.appVersionBakeTimeMs
            - 1
        write { transaction in
            // Mark as checked in the past so that we'd be eligible after an app update.
            APNSRotationStore.nowMs = {
                return lastPushTime
            }
            APNSRotationStore.setAppVersionTimeForAPNSRotationIfNeeded(transaction: transaction)
            APNSRotationStore.didReceiveAPNSPush(transaction: transaction)
        }

        // Change the token so its not marked good anymore.
        write { tx in
            preferences.setPushToken("abc", tx: tx)
        }

        read {
            APNSRotationStore.nowMs = { now }
            // We should be eligible for a rotation
            XCTAssert(APNSRotationStore.canRotateAPNSToken(transaction: $0))
        }

        // Insert a message in the past.
        write { transaction in
            self.createIncomingMessage(
                receivedTimestamp: lastPushTime,
                transaction: transaction
            )
        }

        // We shouldn't rotate without unprocessed messages.
        var onMessagesFlushed = APNSRotationStore.rotateIfNeededOnAppLaunchAndReadiness(performRotation: {
            XCTFail("Rotating when we shouldn't!")
        })
        XCTAssertNotNil(onMessagesFlushed)
        onMessagesFlushed?()

        // But if we insert some messages on app launch we should rotate!
        var didRotate = false
        onMessagesFlushed = APNSRotationStore.rotateIfNeededOnAppLaunchAndReadiness(performRotation: {
            didRotate = true
        })
        XCTAssertNotNil(onMessagesFlushed)
        XCTAssertFalse(didRotate)

        // Insert a message.
        write { transaction in
            self.createIncomingMessage(
                receivedTimestamp: now,
                transaction: transaction
            )
        }

        onMessagesFlushed?()

        XCTAssert(didRotate)
    }

    // MARK: - Helpers

    private func createIncomingMessage(
        receivedTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        let message = self.messageFactory.create(transaction: transaction)
        message.replaceReceived(atTimestamp: receivedTimestamp, transaction: transaction)
    }
}
