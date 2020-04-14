//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import PromiseKit

@objc
public class BulkProfileFetch: NSObject {

    // MARK: - Dependencies

    private var profileManager: ProfileManagerProtocol {
        return SSKEnvironment.shared.profileManager
    }

    private var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    private var reachabilityManager: SSKReachabilityManager {
        return SSKEnvironment.shared.reachabilityManager
    }

    // MARK: - 

    private let serialQueue = DispatchQueue(label: "BulkProfileFetch")

    // This property should only be accessed on serialQueue.
    private var addressQueue = OrderedSet<SignalServiceAddress>()

    // This property should only be accessed on serialQueue.
    private var isUpdateInFlight = false

    private enum UpdateOutcome {
        case networkFailure(date: Date)
        case retryLimit(date: Date)
        case noProfile(date: Date)
        case serviceError(date: Date)
        case success(date: Date)
    }

    // This property should only be accessed on serialQueue.
    private var lastOutcomeMap = [SignalServiceAddress: UpdateOutcome]()

    // This property should only be accessed on serialQueue.
    private var lastRateLimitErrorDate: Date?

    @objc
    public required override init() {
        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppDidBecomeReady {
            // TODO: There would be benefit to trying to update
            // missing & stale profiles on launch.
        }

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

    // This should be used for non-urgent profile updates.
    @objc
    public func fetchAndUpdateProfiles(thread: TSThread) {
        fetchAndUpdateProfiles(addresses: thread.recipientAddresses)
    }

    // This should be used for non-urgent profile updates.
    @objc
    public func fetchAndUpdateProfile(address: SignalServiceAddress) {
        fetchAndUpdateProfiles(addresses: [address])
    }

    // This should be used for non-urgent profile updates.
    @objc
    public func fetchAndUpdateProfiles(addresses: [SignalServiceAddress]) {
        serialQueue.async {
            guard let localAddress = self.tsAccountManager.localAddress else {
                owsFailDebug("missing local address")
                return
            }
            for address in addresses {
                guard address != localAddress else {
                    continue
                }
                guard !self.addressQueue.contains(address) else {
                    continue
                }
                self.addressQueue.append(address)
            }
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

        // Only one update in flight at a time.
        guard !self.isUpdateInFlight else {
            return
        }

        // Dequeue.
        guard let address = self.addressQueue.first else {
            return
        }
        self.addressQueue.remove(address)

        // De-bounce.
        guard self.shouldUpdateAddress(address) else {
            return
        }

        Logger.verbose("Updating: \(address)")

        // Perform update.
        isUpdateInFlight = true
        // We need to throttle these jobs.
        // Always wait N seconds between update jobs.
        let updateDelaySeconds: TimeInterval = 3
        firstly {
            self.profileManager.updateProfile(forAddressPromise: address,
                                              mainAppOnly: true,
                                              ignoreThrottling: false).asVoid()
        }.done {
            self.serialQueue.asyncAfter(deadline: DispatchTime.now() + updateDelaySeconds) {
                self.isUpdateInFlight = false
                self.lastOutcomeMap[address] = .success(date: Date())
                self.process()
            }
        }.catch { error in
            self.serialQueue.asyncAfter(deadline: DispatchTime.now() + updateDelaySeconds) {
                self.isUpdateInFlight = false
                let now = Date()
                switch error {
                default:
                    if IsNetworkConnectivityFailure(error) {
                        Logger.warn("Error: \(error)")
                        self.lastOutcomeMap[address] = .networkFailure(date: now)
                    } else if error.httpStatusCode == 413 {
                        Logger.error("Error: \(error)")
                        self.lastOutcomeMap[address] = .retryLimit(date: now)
                        self.lastRateLimitErrorDate = now
                    } else if error.httpStatusCode == 404 {
                        Logger.error("Error: \(error)")
                        self.lastOutcomeMap[address] = .noProfile(date: now)
                    } else {
                        // TODO: We may need to handle more status codes.
                        owsFailDebug("Error: \(error)")
                        self.lastOutcomeMap[address] = .serviceError(date: now)
                    }
                }
//                public enum ProfileFetchError: Int, Error {
//                    case missing
//                    case throttled
//                    case notMainApp
//                    case cantRequestVersionedProfile
//                }

                self.process()
            }
        }.retainUntilComplete()
    }

    private func shouldUpdateAddress(_ address: SignalServiceAddress) -> Bool {
        assertOnQueue(serialQueue)

        // Skip if we've recently had a rate limit error.
        if let lastRateLimitErrorDate = self.lastRateLimitErrorDate {
            let minElapsedSeconds = 5 * kMinuteInterval
            let elapsedSeconds = lastRateLimitErrorDate.timeIntervalSinceNow
            guard elapsedSeconds >= minElapsedSeconds else {
                return false
            }
        }

        guard let lastOutcome = lastOutcomeMap[address] else {
            return true
        }

        let minElapsedSeconds: TimeInterval
        let elapsedSeconds: TimeInterval

        switch lastOutcome {
        case .networkFailure(let date):
            minElapsedSeconds = 1 * kMinuteInterval
            elapsedSeconds = date.timeIntervalSinceNow
        case .retryLimit(let date):
            minElapsedSeconds = 5 * kMinuteInterval
            elapsedSeconds = date.timeIntervalSinceNow
        case .noProfile(let date):
            minElapsedSeconds = 6 * kHourInterval
            elapsedSeconds = date.timeIntervalSinceNow
        case .serviceError(let date):
            minElapsedSeconds = 30 * kMinuteInterval
            elapsedSeconds = date.timeIntervalSinceNow
        case .success(let date):
            minElapsedSeconds = 15 * kMinuteInterval
            elapsedSeconds = date.timeIntervalSinceNow
        }

        return elapsedSeconds >= minElapsedSeconds
    }
}
