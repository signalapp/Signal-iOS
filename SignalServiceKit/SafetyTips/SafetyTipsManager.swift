//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension NSNotification.Name {
    public static let smsVerificationCodeRequested = Notification.Name("SafetyTipsKeyValueStore.smsVerificationCodeRequested")
}

@MainActor
public class SafetyTipsManager {
    private static var hasStartedObserving = false
    static let expiryTimeSeconds = (TimeInterval.minute * 10)

    private enum StoreKeys {
        static let smsCodeRequestedTimestampMs: String = "smsCodeRequestedTimestampMsKey"
    }

    private let kvStore: NewKeyValueStore

    public init() {
        self.kvStore = NewKeyValueStore(collection: "SafetyTips")
    }

    public func setLastVerificationCodeRequestedTimestampMs(
        value: UInt64,
        transaction: DBWriteTransaction,
    ) {
        kvStore.writeValue(
            value,
            forKey: StoreKeys.smsCodeRequestedTimestampMs,
            tx: transaction,
        )

        transaction.addSyncCompletion {
            // Wake up observer in the main app to check KV store
            DarwinNotificationCenter.postNotification(name: .smsVerificationCodeRequested)
        }
    }

    public func lastVerificationCodeTimestampMsWithinExpiryTime(
        transaction: DBReadTransaction,
    ) -> UInt64? {
        guard
            let timestamp = kvStore.fetchValue(
                UInt64.self,
                forKey: StoreKeys.smsCodeRequestedTimestampMs,
                tx: transaction,
            )
        else {
            return nil
        }

        let timestampDate = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
        let seconds = Date().timeIntervalSince(timestampDate)
        guard seconds <= Self.expiryTimeSeconds else {
            return nil
        }
        return timestamp
    }

    public func removeVerificationCodeRequestedTimestampMs(
        transaction: DBWriteTransaction,
    ) {
        kvStore.removeValue(forKey: StoreKeys.smsCodeRequestedTimestampMs, tx: transaction)
    }

    public static func startObservingDarwinNotifications() {
        guard !hasStartedObserving else { return }
        hasStartedObserving = true
        _ = DarwinNotificationCenter.addObserver(name: .smsVerificationCodeRequested, queue: .main) { _ in
            NotificationCenter.default.post(name: .smsVerificationCodeRequested, object: nil)
        }
    }
}
