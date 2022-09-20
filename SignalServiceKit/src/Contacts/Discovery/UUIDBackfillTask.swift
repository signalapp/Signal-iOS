//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSUUIDBackfillTask)
public class UUIDBackfillTask: NSObject {

    // MARK: - Properties

    private let queue: DispatchQueue
    private var phoneNumbersToFetch: [(persisted: String, e164: String?)] = []
    private var completionBlock: (() -> Void)?

    private var didStart: Bool = false
    private var attemptCount = 0

    // MARK: - Properties (External Dependencies)
    private let readiness: ReadinessProvider
    private let persistence: PersistenceProvider

    // MARK: - Lifecycle

    public convenience init(targetQueue: DispatchQueue = .sharedUtility) {
        self.init(targetQueue: targetQueue,
                  persistence: .default,
                  readiness: .default)
    }

    init(targetQueue: DispatchQueue = .sharedUtility,
         persistence: PersistenceProvider = .default,
         readiness: ReadinessProvider = .default) {

        self.queue = DispatchQueue(
            label: OWSDispatch.createLabel("\(type(of: self))"),
            target: targetQueue)
        self.persistence = persistence
        self.readiness = readiness
        super.init()
    }

    // MARK: - Public

    func performWithCompletion(_ completion: @escaping () -> Void = {}) {
        readiness.runNowOrWhenAppDidBecomeReadySync {
            self.queue.async {
                self.onqueue_start(with: completion)
            }
        }
    }

    // MARK: - Testing

    internal var testing_shortBackoffInterval = false
    internal var testing_backoffInterval: DispatchTimeInterval {
        return backoffInterval
    }
    internal var testing_attemptCount: Int {
        get {
            return attemptCount
        }
        set {
            attemptCount = newValue
        }
    }

    // MARK: - Private

    private var backoffInterval: DispatchTimeInterval {
        // (Similar code exists elsewhere in the project, this pattern is used in a few places)
        // (IOS-649: Factor out exponential backoff tracking into class)
        //
        // Arbitrary backoff factor...
        // With backOffFactor of 1.9
        // attempt 1:  0.00s
        // attempt 2:  90ms
        // ...
        // attempt 5:  1.20s
        // ...
        // attempt 11:  61.2s
        let backoffFactor = 1.9
        let maxBackoff = 15 * kMinuteInterval
        let secondsToBackoff = 0.1 * (pow(backoffFactor, Double(attemptCount)) - 1)
        let secondsCapped = min(maxBackoff, secondsToBackoff)
        let milliseconds = Int(secondsCapped * 1000)

        let millisecondsToBackoff = testing_shortBackoffInterval ? (milliseconds / 100) : milliseconds
        return .milliseconds(millisecondsToBackoff)
    }

    private func onqueue_start(with completion: @escaping () -> Void) {
        assertOnQueue(queue)

        guard self.didStart == false else {
            owsFailDebug("perform() invoked multiple times")
            return
        }
        self.didStart = true
        self.completionBlock = completion

        let allRecipientsWithoutUUID = self.persistence.fetchRegisteredRecipientsWithoutUUID()
        assert(allRecipientsWithoutUUID.allSatisfy({ (recipient) in
            recipient.recipientPhoneNumber != nil &&
            recipient.recipientUUID == nil
        }), "Invalid recipient returned from persistence")

        self.phoneNumbersToFetch = allRecipientsWithoutUUID
            .compactMap { $0.recipientPhoneNumber }
            .map { (persisted: $0, e164: PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: $0)?.toE164()) }

        if self.phoneNumbersToFetch.isEmpty {
            Logger.info("Completing early, no phone numbers to fetch.")
            self.onqueue_complete()

        } else {
            Logger.info("Scheduling a fetch for \(self.phoneNumbersToFetch.count) phone numbers.")
            self.onqueue_schedule()
        }
    }

    private func onqueue_schedule(for date: Date? = nil) {
        assertOnQueue(queue)

        let delay: DispatchTimeInterval
        if let date = date {
            let msDelay = max(date.timeIntervalSinceNow * 1000, 0)
            delay = .milliseconds(Int(msDelay))
        } else {
            delay = backoffInterval
        }

        queue.asyncAfter(deadline: .now() + delay, execute: onqueue_performCDSFetch)
    }

    private func onqueue_performCDSFetch() {
        assertOnQueue(queue)
        let e164Numbers = Set(phoneNumbersToFetch.compactMap { $0.e164 })

        attemptCount += 1
        Logger.info("Beginning ContactDiscovery for UUID backfill")

        let discoveryTask = ContactDiscoveryTask(phoneNumbers: e164Numbers)
        discoveryTask.isCriticalPriority = true

        discoveryTask.perform()
            .done(on: queue) { _ in self.onqueue_complete() }
            .recover(on: queue) { error in self.onqueue_handleError(error: error) }
    }

    func onqueue_handleError(error: Error) {
        assertOnQueue(queue)
        Logger.error("UUID Backfill failed: \(error). Scheduling retry...")
        onqueue_schedule(for: (error as? ContactDiscoveryError)?.retryAfterDate)
    }

    func onqueue_complete() {
        Logger.info("UUID Backfill complete")
        assertOnQueue(queue)
        completionBlock?()
        completionBlock = nil
    }
}

// MARK: -

extension UUIDBackfillTask {

    // This extension encapsulates some of UUIDBackfillTask's cross-class dependencies
    // Default versions of these structs are passed in at init(), but they can be customized
    // and overridden to shim out any dependencies for testing.

    class PersistenceProvider {
        static var `default`: PersistenceProvider { return PersistenceProvider() }

        func fetchRegisteredRecipientsWithoutUUID() -> [SignalRecipient] {
            SDSDatabaseStorage.shared.read { (readTx) in
                return AnySignalRecipientFinder().registeredRecipientsWithoutUUID(transaction: readTx)
            }
        }
    }

    class ReadinessProvider {
        static var `default`: ReadinessProvider { return ReadinessProvider() }

        func runNowOrWhenAppDidBecomeReadySync(_ workItem: @escaping () -> Void) {
            AppReadiness.runNowOrWhenAppDidBecomeReadySync(workItem)
        }
    }
}
