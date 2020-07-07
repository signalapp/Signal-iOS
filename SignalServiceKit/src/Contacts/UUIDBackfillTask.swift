//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(OWSUUIDBackfillTask)
public class UUIDBackfillTask: NSObject {

    // MARK: - Properties

    private let queue: DispatchQueue
    private let persistence: PersistenceProvider
    private let network: NetworkProvider
    private let phoneNumbersToFetch: [String]

    private var completionBlock: (() -> Void)?

    private var didStart: Bool = false
    private var attemptCount = 0
    private var hardFailureCount = 0

    // MARK: - Lifecycle

    init(targetQueue: DispatchQueue = .sharedUtility,
         persistence: PersistenceProvider = .default,
         network: NetworkProvider = .default) {

        let allRecipientsWithoutUUID = persistence.fetchSignalRecipientsWithoutUUID()
        assert(allRecipientsWithoutUUID.allSatisfy({ (recipient) in
            recipient.recipientPhoneNumber != nil &&
            recipient.recipientUUID == nil &&
            true // Pull request note: Is there a way to check for valid e164?
        }), "Invalid recipient returned from persistence")

        self.queue = DispatchQueue(label: "org.whispersystems.signal.\(type(of: self))", target: targetQueue)
        self.persistence = persistence
        self.network = network
        self.phoneNumbersToFetch = allRecipientsWithoutUUID.compactMap { $0.recipientPhoneNumber }
        super.init()
    }

    // MARK: - Public

    func perform(completion: @escaping () -> Void = {}) {
        queue.async {
            guard self.didStart == false else {
                assertionFailure("perform() invoked multiple times")
                return
            }
            self.didStart = true
            self.completionBlock = completion

            // Early exit if there's nothing to do:
            if self.phoneNumbersToFetch.count > 0 {
                Logger.info("Scheduling a fetch for \(self.phoneNumbersToFetch.count) phone numbers.")
                self.onqueue_schedule()
            } else {
                Logger.info("Completing early, no phone numbers to fetch.")
                self.onqueue_complete()
            }
        }
    }

    // MARK: - Private

    private func onqueue_schedule() {
        assertOnQueue(queue)

        let delay = DispatchTimeInterval.seconds(1)   // TODO: Incremental backoff based on the number of attempts
        queue.asyncAfter(deadline: .now() + delay) {
            self.onqueue_perform()
        }
    }

    private func onqueue_perform() {
        assertOnQueue(queue)

        attemptCount += 1
        firstly { () throws -> Promise<Set<CDSRegisteredContact>> in
            Logger.info("Beginning CDS fetch for UUID backfill")
            let (promise, resolver) = Promise<Set<CDSRegisteredContact>>.pending()
            network.fetchServiceAddress(for: self.phoneNumbersToFetch) { (contacts, error) in
                resolver.resolve(contacts, error)
            }
            return promise
        }.done(on: queue) { (result) in
            self.onqueue_handleResults(results: result)
        }.catch(on: queue) { (error) in
            self.onqueue_handleError(error: error)
        }
    }

    func onqueue_handleError(error: Error) {
        assertOnQueue(queue)

        switch error {
        case TSNetworkManagerError.failedConnection:
            Logger.info("UUID Backfill failed due to network failure")
        default:
            Logger.error("UUID Backfill failed: \(error)")
            hardFailureCount += 1
        }

        // After a certain number of unexpected errors we'll just give up
        if hardFailureCount <= 5 {
            Logger.info("UUID backfill will retry")
            self.onqueue_schedule()
        } else {
            Logger.info("UUID backfill failed too many times. Giving up.")
            self.onqueue_complete()
        }
    }

    func onqueue_handleResults(results: Set<CDSRegisteredContact>) {
        assertOnQueue(queue)

        let resultMap = results.reduce(into: [:]) { (dict, contact) in
            dict[contact.e164PhoneNumber] = contact.signalUuid
        }
        let addresses = phoneNumbersToFetch
            .map { SignalServiceAddress(uuid: resultMap[$0], phoneNumber: $0) }

        let toRegister = addresses.filter { $0.uuid != nil }
        let toUnregister = addresses.filter { $0.uuid == nil }

        toRegister.forEach { Logger.info("Registering \($0)") }
        toUnregister.forEach { Logger.info("Unregistering \($0)") }

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

@objc public extension UUIDBackfillTask {
    private static let postLaunchLock = UnfairLock()
    private static var postLaunchTask: UUIDBackfillTask?

    static func registerPostLaunchTask(completion: @escaping () -> Void = {}) {
        postLaunchLock.withLock {
            guard postLaunchTask == nil else { return }
            postLaunchTask = UUIDBackfillTask()
        }

        AppReadiness.runNowOrWhenAppDidBecomeReady {
            postLaunchTask?.perform(completion: {
                completion()
                didCompletePostLaunchTask()
            })
        }
    }

    private static func didCompletePostLaunchTask() {
        postLaunchLock.withLock {
            postLaunchTask = nil
        }
    }
}

// MARK: - Dependencies
extension UUIDBackfillTask {

    // This extension encapsulates some of UUIDBackfillTask's cross-class dependencies
    // Default versions of these structs are passed in at init(), but they can be customized
    // and overridden to shim out any dependencies for testing.

    class NetworkProvider {
        static let `default` = NetworkProvider()

        func fetchServiceAddress(for phoneNumbers: [String],
                                 completion: @escaping (Set<CDSRegisteredContact>, Error?) -> Void) {
            let operation = ContactDiscoveryOperation(phoneNumbersToLookup: phoneNumbers)
            operation.completionBlock = {
                completion(operation.registeredContacts, operation.failingError)
            }
            ContactDiscoveryOperation.operationQueue.addOperations(operation.dependencies, waitUntilFinished: false)
            ContactDiscoveryOperation.operationQueue.addOperation(operation)
        }
    }

    class PersistenceProvider {
        static let `default` = PersistenceProvider()

        func fetchSignalRecipientsWithoutUUID() -> [SignalRecipient] {
            SDSDatabaseStorage.shared.read { (readTx) in
                return AnySignalRecipientFinder().signalRecipientsWithoutUUID(transaction: readTx)
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
}
