//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

// Unlike per-conversation expiration, per-message expiration has
// short expiration times and the countdown is manually initiated.
// There should be very few countdowns in flight at a time.
// Therefore we can adopt a much simpler approach to countdown
// logic and use async dispatch for each countdown.
@objc
public class PerMessageExpiration: NSObject {

    // MARK: - Dependencies

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    @objc
    public class func startPerMessageExpiration(forMessage message: TSMessage,
                                                transaction: SDSAnyWriteTransaction) {
        AssertIsOnMainThread()

        if message.perMessageExpireStartedAt < 1 {
            // Mark the countdown as begun.
            message.updateWithPerMessageExpireStarted(at: NSDate.ows_millisecondTimeStamp(),
                                                      transaction: transaction)
        } else {
            owsFailDebug("Per-message expiration countdown already begun.")
        }

        schedulePerMessageExpiration(forMessage: message)
    }

    private class func schedulePerMessageExpiration(forMessage message: TSMessage) {
        let perMessageExpiresAtMS = message.perMessageExpiresAt
        let nowMs = NSDate.ows_millisecondTimeStamp()

        guard perMessageExpiresAtMS > nowMs else {
            DispatchQueue.global().async {
                self.completePerMessageExpiration(forMessage: message)
            }
            return
        }

        let delaySeconds: TimeInterval = Double(perMessageExpiresAtMS - nowMs) / 1000
        DispatchQueue.global().asyncAfter(deadline: .now() + delaySeconds) {
            self.completePerMessageExpiration(forMessage: message)
        }
    }

    private class func completePerMessageExpiration(forMessage message: TSMessage) {
        databaseStorage.write { (transaction) in
            self.completePerMessageExpiration(forMessage: message,
                                              transaction: transaction)
        }
    }

    private class func completePerMessageExpiration(forMessage message: TSMessage,
                                                    transaction: SDSAnyWriteTransaction) {
        message.setPerMessageExpiredAndRemoveRenderableContentWith(transaction)
    }

    // MARK: -

    @objc
    public class func appDidBecomeReady() {
        AssertIsOnMainThread()

        // Find all messages with per-message expiration whose countdown has begun.
        // Cull expired messages & resume countdown for others.
    }
}
