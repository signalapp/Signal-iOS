//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import PromiseKit

@objc
public class BulkUUIDLookup: NSObject {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    private var reachabilityManager: SSKReachabilityManager {
        return SSKEnvironment.shared.reachabilityManager
    }

    private var contactsUpdater: ContactsUpdater {
        return SSKEnvironment.shared.contactsUpdater
    }

    // MARK: - 

    private let serialQueue = DispatchQueue(label: "BulkUUIDLookup")

    // This property should only be accessed on serialQueue.
    private var phoneNumberQueue = Set<String>()

    // This property should only be accessed on serialQueue.
    private var isUpdateInFlight = false

    struct UpdateOutcome {
        let outcome: Outcome
        enum Outcome {
            case networkFailure
            case retryLimit
            case serviceError
            case success
            case unknownError
        }
        let date: Date

        init(_ outcome: Outcome) {
            self.outcome = outcome
            self.date = Date()
        }
    }

    // This property should only be accessed on serialQueue.
    private var lastOutcomeMap = [String: UpdateOutcome]()

    // This property should only be accessed on serialQueue.
    private var lastRateLimitErrorDate: Date?

    @objc
    public required override init() {
        super.init()

        SwiftSingletons.register(self)

        observeNotifications()
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(forName: SSKReachability.owsReachabilityDidChange,
                                               object: nil, queue: nil) { [weak self] _ in
                                                guard let self = self else { return }
                                                self.serialQueue.async {
                                                    self.process()
                                                }
        }
        NotificationCenter.default.addObserver(forName: .registrationStateDidChange, object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            self.serialQueue.async {
                self.process()
            }
        }
    }

    // This should be used for non-urgent uuid lookups.
    @objc
    public func lookupUuids(phoneNumbers: [String]) {
        serialQueue.async {
            self.phoneNumberQueue.formUnion(phoneNumbers)
            self.process()
        }
    }

    private func process() {
        assertOnQueue(serialQueue)

        guard !CurrentAppContext().isRunningTests else { return }

        guard CurrentAppContext().isMainApp else {
            return
        }
        guard reachabilityManager.isReachable else {
            return
        }
        guard tsAccountManager.isRegisteredAndReady else {
            return
        }
        guard FeatureFlags.useOnlyModernContactDiscovery ||
            FeatureFlags.compareLegacyContactDiscoveryAgainstModern else {
                // Can't fill in UUIDs using legacy contact intersections.
                return
        }

        // Only one update in flight at a time.
        guard !self.isUpdateInFlight else {
            return
        }

        // Build batch.
        let phoneNumbers = phoneNumberQueue.filter { self.shouldUpdatePhoneNumber($0) }
        phoneNumberQueue.removeAll()

        guard !phoneNumbers.isEmpty else {
            return
        }

        // De-bounce.

        Logger.verbose("Updating: \(phoneNumbers)")

        // Perform update.
        isUpdateInFlight = true
        firstly {
            return contactsUpdater.lookupIdentifiersPromise(phoneNumbers: Array(phoneNumbers)).asVoid()
        }.done {
            self.serialQueue.async {
                self.isUpdateInFlight = false
                let outcome = UpdateOutcome(.success)
                for phoneNumber in phoneNumbers {
                    self.lastOutcomeMap[phoneNumber] = outcome
                }
                self.process()
            }
        }.catch { error in
            self.serialQueue.async {
                self.isUpdateInFlight = false

                let outcome: UpdateOutcome
                let nsError = error as NSError
                if nsError.domain == OWSSignalServiceKitErrorDomain &&
                    nsError.code == OWSErrorCode.contactsUpdaterRateLimit.rawValue {
                    Logger.error("Error: \(error)")
                    outcome = UpdateOutcome(.retryLimit)
                    self.lastRateLimitErrorDate = Date()
                } else {
                    switch error {
                    case ContactDiscoveryService.ServiceError.error4xx,
                         ContactDiscoveryService.ServiceError.error5xx:
                        owsFailDebug("Error: \(error)")
                        outcome = UpdateOutcome(.serviceError)
                    case ContactDiscoveryService.ServiceError.tooManyRequests:
                        Logger.error("Error: \(error)")
                        outcome = UpdateOutcome(.retryLimit)
                        self.lastRateLimitErrorDate = Date()
                    default:
                        if IsNetworkConnectivityFailure(error) {
                            Logger.warn("Error: \(error)")
                            outcome = UpdateOutcome(.networkFailure)
                        } else if error.httpStatusCode == 413 {
                            Logger.error("Error: \(error)")
                            outcome = UpdateOutcome(.retryLimit)
                            self.lastRateLimitErrorDate = Date()
                        } else if let httpStatusCode = error.httpStatusCode,
                            httpStatusCode >= 400,
                            httpStatusCode <= 599 {
                            owsFailDebug("Error: \(error)")
                            outcome = UpdateOutcome(.serviceError)
                        } else {
                            owsFailDebug("Error: \(error)")
                            outcome = UpdateOutcome(.unknownError)
                        }
                    }
                }

                for phoneNumber in phoneNumbers {
                    self.lastOutcomeMap[phoneNumber] = outcome
                }

                self.process()
            }
        }
    }

    private func shouldUpdatePhoneNumber(_ phoneNumber: String) -> Bool {
        assertOnQueue(serialQueue)

        guard SignalServiceAddress(phoneNumber: phoneNumber).uuid == nil else {
            return false
        }

        // Skip if we've recently had a rate limit error.
        if let lastRateLimitErrorDate = self.lastRateLimitErrorDate {
            let minElapsedSeconds = 5 * kMinuteInterval
            let elapsedSeconds = lastRateLimitErrorDate.timeIntervalSinceNow
            guard elapsedSeconds >= minElapsedSeconds else {
                return false
            }
        }

        guard let lastOutcome = lastOutcomeMap[phoneNumber] else {
            return true
        }

        let minElapsedSeconds: TimeInterval
        let elapsedSeconds = lastOutcome.date.timeIntervalSinceNow

        switch lastOutcome.outcome {
        case .networkFailure:
            minElapsedSeconds = 1 * kMinuteInterval
        case .retryLimit:
            minElapsedSeconds = 15 * kMinuteInterval
        case .serviceError:
            minElapsedSeconds = 30 * kMinuteInterval
        case .unknownError:
            minElapsedSeconds = 60 * kMinuteInterval
        case .success:
            minElapsedSeconds = 60 * kMinuteInterval
        }

        return elapsedSeconds >= minElapsedSeconds
    }
}
