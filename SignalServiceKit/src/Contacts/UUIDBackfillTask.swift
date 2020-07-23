//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(OWSUUIDBackfillTask)
public class UUIDBackfillTask: NSObject {

    // MARK: - Properties

    private let queue: DispatchQueue
    private var phoneNumbersToFetch: [(persisted: String, e164: String?)] = []
    private var completionBlock: (() -> Void)?

    private var didStart: Bool = false
    private var attemptCount = 0

    // MARK: - Properies (External Dependencies)
    private let readiness: ReadinessProvider
    private let persistence: PersistenceProvider
    private let network: NetworkProvider

    // MARK: - Lifecycle

    public convenience init(targetQueue: DispatchQueue = .sharedUtility) {
        self.init(targetQueue: targetQueue,
                  persistence: .default,
                  network: .default,
                  readiness: .default)
    }

    init(targetQueue: DispatchQueue = .sharedUtility,
         persistence: PersistenceProvider = .default,
         network: NetworkProvider = .default,
         readiness: ReadinessProvider = .default) {

        self.queue = DispatchQueue(label: "org.whispersystems.signal.\(type(of: self))", target: targetQueue)
        self.persistence = persistence
        self.network = network
        self.readiness = readiness
        super.init()
    }

    // MARK: - Public

    func perform(completion: @escaping () -> Void = {}) {
        readiness.runNowOrWhenAppDidBecomeReady {
            self.queue.async {
                self.onqueue_start(with: completion)
            }
        }
    }

    // MARK: - Testing

    internal var testing_skipProductionCheck = false
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

        if !FeatureFlags.useOnlyModernContactDiscovery && !testing_skipProductionCheck {
            Logger.info("Modern CDS is not available. Completing early.")
            self.onqueue_complete()

        } else if self.phoneNumbersToFetch.isEmpty {
            Logger.info("Completing early, no phone numbers to fetch.")
            self.onqueue_complete()

        } else {
            Logger.info("Scheduling a fetch for \(self.phoneNumbersToFetch.count) phone numbers.")
            self.onqueue_schedule()
        }
    }

    private func onqueue_schedule() {
        assertOnQueue(queue)
        queue.asyncAfter(deadline: .now() + backoffInterval, execute: onqueue_performCDSFetch)
    }

    private func onqueue_performCDSFetch() {
        assertOnQueue(queue)

        attemptCount += 1
        firstly { () throws -> Promise<Set<CDSRegisteredContact>> in
            return Promise { resolver in
                Logger.info("Beginning CDS fetch for UUID backfill")
                let e164Numbers = self.phoneNumbersToFetch.compactMap { $0.e164 }
                network.fetchServiceAddress(for: e164Numbers) { (contacts, error) in
                    resolver.resolve(contacts, error)
                }
            }
        }.done(on: queue) { (result) in
            self.onqueue_handleResults(results: result)
        }.catch(on: queue) { (error) in
            self.onqueue_handleError(error: error)
        }
    }

    func onqueue_handleError(error: Error) {
        assertOnQueue(queue)
        Logger.error("UUID Backfill failed: \(error). Scheduling retry...")
        onqueue_schedule()
    }

    func onqueue_handleResults(results: Set<CDSRegisteredContact>) {
        assertOnQueue(queue)

        let resultMap = results.reduce(into: [:]) { (dict, contact) in
            dict[contact.e164PhoneNumber] = contact.signalUuid
        }
        let addresses = phoneNumbersToFetch.map { (numberTuple) -> SignalServiceAddress in
            if let e164 = numberTuple.e164, let uuid = resultMap[e164] {
                return SignalServiceAddress(uuid: uuid, phoneNumber: numberTuple.persisted)
            } else {
                return SignalServiceAddress(uuid: nil, phoneNumber: numberTuple.persisted)
            }
        }

        let toRegister = addresses.filter { $0.uuid != nil }
        let toUnregister = addresses.filter { $0.uuid == nil }

        assert({
            let registeredNumberSet = Set(toRegister.map { $0.phoneNumber })
            let unregisteredNumberSet = Set(toUnregister.map { $0.phoneNumber })
            return registeredNumberSet.isDisjoint(with: unregisteredNumberSet)
        }(), "The same number is being both registered an unregistered")
        Logger.info("Updating \(toRegister.count) recipients with UUID")
        Logger.info("Unregistering \(toUnregister.count) recipients")

        persistence.updateSignalRecipients(registering: toRegister, unregistering: toUnregister)
        onqueue_complete()
    }

    func onqueue_complete() {
        Logger.info("UUID Backfill complete")
        assertOnQueue(queue)
        completionBlock?()
        completionBlock = nil
    }
}

// MARK: - Dependencies
extension UUIDBackfillTask {

    // This extension encapsulates some of UUIDBackfillTask's cross-class dependencies
    // Default versions of these structs are passed in at init(), but they can be customized
    // and overridden to shim out any dependencies for testing.

    class NetworkProvider {
        static var `default`: NetworkProvider { return NetworkProvider() }

        func fetchServiceAddress(for phoneNumbers: [String],
                                 completion: @escaping (Set<CDSRegisteredContact>, Error?) -> Void) {
            let operation = ContactDiscoveryOperation(phoneNumbersToLookup: phoneNumbers)
            operation.completionBlock = {
                completion(operation.registeredContacts, operation.failingError)
            }
            operation.perform()
        }
    }

    class PersistenceProvider {
        static var `default`: PersistenceProvider { return PersistenceProvider() }

        func fetchRegisteredRecipientsWithoutUUID() -> [SignalRecipient] {
            SDSDatabaseStorage.shared.read { (readTx) in
                return AnySignalRecipientFinder().registeredRecipientsWithoutUUID(transaction: readTx)
            }
        }

        func updateSignalRecipients(registering addressesToRegister: [SignalServiceAddress],
                                    unregistering addressesToUnregister: [SignalServiceAddress]) {
            SDSDatabaseStorage.shared.write { (writeTx) in
                addressesToRegister.forEach { (toRegister) in
                    SignalRecipient.mark(asRegisteredAndGet: toRegister, transaction: writeTx)
                }
                addressesToUnregister.forEach { (toUnregister) in
                    SignalRecipient.mark(asUnregistered: toUnregister, transaction: writeTx)
                }
            }
        }
    }

    class ReadinessProvider {
        static var `default`: ReadinessProvider { return ReadinessProvider() }

        func runNowOrWhenAppDidBecomeReady(_ workItem: @escaping () -> Void) {
            AppReadiness.runNowOrWhenAppDidBecomeReady(workItem)
        }
    }
}
