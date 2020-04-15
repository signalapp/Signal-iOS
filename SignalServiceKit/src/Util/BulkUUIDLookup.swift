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

    private enum UpdateOutcome {
        case networkFailure(date: Date)
        case retryLimit(date: Date)
        case serviceError(date: Date)
        case unknownError(date: Date)
        case success(date: Date)
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

        // De-bounce.

        Logger.verbose("Updating: \(phoneNumbers)")

        // Perform update.
        isUpdateInFlight = true
        firstly {
            return contactsUpdater.lookupIdentifiersPromise(phoneNumbers: Array(phoneNumbers)).asVoid()
        }.done {
            self.serialQueue.async {
                self.isUpdateInFlight = false
                let now = Date()
                for phoneNumber in phoneNumbers {
                    self.lastOutcomeMap[phoneNumber] = .success(date: now)
                }
                self.process()
            }
        }.catch { error in
            self.serialQueue.async {
                self.isUpdateInFlight = false
                let now = Date()

                let outcome: UpdateOutcome
                let nsError = error as NSError
                if nsError.domain == OWSSignalServiceKitErrorDomain &&
                    nsError.code == OWSErrorCode.contactsUpdaterRateLimit.rawValue {
                    Logger.error("Error: \(error)")
                    outcome = .retryLimit(date: now)
                    self.lastRateLimitErrorDate = now
                } else {
                    switch error {
                    case ContactDiscoveryService.ServiceError.error4xx,
                         ContactDiscoveryService.ServiceError.error5xx:
                        owsFailDebug("Error: \(error)")
                        outcome = .serviceError(date: now)
                    case ContactDiscoveryService.ServiceError.tooManyRequests:
                        Logger.error("Error: \(error)")
                        outcome = .retryLimit(date: now)
                        self.lastRateLimitErrorDate = now
                    default:
                        if IsNetworkConnectivityFailure(error) {
                            Logger.warn("Error: \(error)")
                            outcome = .networkFailure(date: now)
                        } else if error.httpStatusCode == 413 {
                            Logger.error("Error: \(error)")
                            outcome = .retryLimit(date: now)
                            self.lastRateLimitErrorDate = now
                        } else if let httpStatusCode = error.httpStatusCode,
                            httpStatusCode >= 400,
                            httpStatusCode <= 599 {
                            owsFailDebug("Error: \(error)")
                            outcome = .serviceError(date: now)
                        } else {
                            owsFailDebug("Error: \(error)")
                            outcome = .unknownError(date: now)
                        }
                    }
                }

                for phoneNumber in phoneNumbers {
                    self.lastOutcomeMap[phoneNumber] = outcome
                }

                self.process()
            }
        }.retainUntilComplete()
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
        let elapsedSeconds: TimeInterval

        switch lastOutcome {
        case .networkFailure(let date):
            minElapsedSeconds = 1 * kMinuteInterval
            elapsedSeconds = date.timeIntervalSinceNow
        case .retryLimit(let date):
            minElapsedSeconds = 15 * kMinuteInterval
            elapsedSeconds = date.timeIntervalSinceNow
        case .serviceError(let date):
            minElapsedSeconds = 30 * kMinuteInterval
            elapsedSeconds = date.timeIntervalSinceNow
        case .unknownError(let date):
            minElapsedSeconds = 60 * kMinuteInterval
            elapsedSeconds = date.timeIntervalSinceNow
        case .success(let date):
            minElapsedSeconds = 60 * kMinuteInterval
            elapsedSeconds = date.timeIntervalSinceNow
        }

        return elapsedSeconds >= minElapsedSeconds
    }
}
