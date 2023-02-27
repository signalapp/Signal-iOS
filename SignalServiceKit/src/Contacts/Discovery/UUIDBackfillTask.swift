//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class UUIDBackfillTask {

    // MARK: - Properties

    private let contactDiscoveryManager: ContactDiscoveryManager
    private let databaseStorage: SDSDatabaseStorage

    private let queue: DispatchQueue
    private var e164sToFetch = Set<String>()
    private var attemptCount = 0

    // MARK: - Lifecycle

    init(contactDiscoveryManager: ContactDiscoveryManager, databaseStorage: SDSDatabaseStorage) {
        self.contactDiscoveryManager = contactDiscoveryManager
        self.databaseStorage = databaseStorage

        self.queue = DispatchQueue(label: "org.signal.uuid-backfill-task", target: .sharedUserInitiated)
    }

    // MARK: - Public

    func perform() -> Guarantee<Void> {
        let (guarantee, future) = Guarantee<Void>.pending()
        self.queue.async {
            self.onqueue_start(resolving: future)
        }
        return guarantee
    }

    // MARK: - Private

    private var backoffInterval: DispatchTimeInterval {
        let constantAdjustment: TimeInterval = 0.1
        let timeInterval = OWSOperation.retryIntervalForExponentialBackoff(
            failureCount: UInt(attemptCount),
            maxBackoff: 15 * kMinuteInterval + constantAdjustment
        ) - constantAdjustment
        return .milliseconds(Int(timeInterval * 1000))
    }

    private func onqueue_start(resolving future: GuaranteeFuture<Void>) {
        assertOnQueue(queue)

        let allRecipientsWithoutUUID = databaseStorage.read { transaction in
            return AnySignalRecipientFinder().registeredRecipientsWithoutUUID(transaction: transaction)
        }

        e164sToFetch.formUnion(
            allRecipientsWithoutUUID
                .lazy
                .compactMap { $0.recipientPhoneNumber }
                .compactMap { PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: $0)?.toE164() }
        )

        guard !e164sToFetch.isEmpty else {
            Logger.info("Completing early, no phone numbers to fetch.")
            future.resolve()
            return
        }

        Logger.info("Scheduling a fetch for \(e164sToFetch.count) phone numbers.")
        onqueue_performCDSFetch(resolving: future)
    }

    private func onqueue_performCDSFetch(resolving future: GuaranteeFuture<Void>) {
        assertOnQueue(queue)

        attemptCount += 1
        Logger.info("UUID Backfill starting attempt \(attemptCount)")

        firstly {
            contactDiscoveryManager.lookUp(
                phoneNumbers: e164sToFetch,
                mode: .uuidBackfill
            ).asVoid()
        }.done(on: queue) {
            Logger.info("UUID Backfill complete")
            future.resolve()
        }.catch(on: queue) { error in
            Logger.error("UUID Backfill failed: \(error). Scheduling retry...")
            let retryDelay: DispatchTimeInterval
            if let retryAfter = (error as? ContactDiscoveryError)?.retryAfterDate {
                retryDelay = .milliseconds(Int(retryAfter.timeIntervalSinceNow * 1000))
            } else {
                retryDelay = self.backoffInterval
            }
            self.queue.asyncAfter(deadline: .now() + retryDelay) {
                self.onqueue_performCDSFetch(resolving: future)
            }
        }
    }
}
