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
        return .shared()
    }

    private var reachabilityManager: SSKReachabilityManager {
        return SSKEnvironment.shared.reachabilityManager
    }

    private var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    // MARK: -

    private let serialQueue = DispatchQueue(label: "BulkProfileFetch")

    // This property should only be accessed on serialQueue.
    private var uuidQueue = OrderedSet<UUID>()

    // This property should only be accessed on serialQueue.
    private var isUpdateInFlight = false

    struct UpdateOutcome {
        let outcome: Outcome
        enum Outcome {
            case networkFailure
            case retryLimit
            case noProfile
            case serviceError
            case success
            case throttled
            case invalid
        }
        let date: Date

        init(_ outcome: Outcome) {
            self.outcome = outcome
            self.date = Date()
        }
    }

    // This property should only be accessed on serialQueue.
    private var lastOutcomeMap = [UUID: UpdateOutcome]()

    // This property should only be accessed on serialQueue.
    private var lastRateLimitErrorDate: Date?

    @objc
    public required override init() {
        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppDidBecomeReadyPolite {
            // Try to update missing & stale profiles on launch.
            DispatchQueue.global(qos: .utility).async {
                self.fetchMissingAndStaleProfiles()
            }
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
    public func fetchProfiles(thread: TSThread) {
        fetchProfiles(addresses: thread.recipientAddresses)
    }

    // This should be used for non-urgent profile updates.
    @objc
    public func fetchProfile(address: SignalServiceAddress) {
        fetchProfiles(addresses: [address])
    }

    // This should be used for non-urgent profile updates.
    @objc
    public func fetchProfiles(addresses: [SignalServiceAddress]) {
        let uuids = addresses.compactMap { $0.uuid }
        fetchProfiles(uuids: uuids)
    }

    // This should be used for non-urgent profile updates.
    @objc
    public func fetchProfile(uuid: UUID) {
        fetchProfiles(uuids: [uuid])
    }

    // This should be used for non-urgent profile updates.
    @objc
    public func fetchProfiles(uuids: [UUID]) {
        serialQueue.async {
            guard let localUuid = self.tsAccountManager.localUuid else {
                owsFailDebug("missing localUuid")
                return
            }
            for uuid in uuids {
                guard uuid != localUuid else {
                    continue
                }
                guard !self.uuidQueue.contains(uuid) else {
                    continue
                }
                self.uuidQueue.append(uuid)
            }
            self.process()
        }
    }

    private func process() {
        assertOnQueue(serialQueue)

        guard !CurrentAppContext().isRunningTests else {  return }

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
        guard let uuid = self.uuidQueue.first else {
            return
        }
        self.uuidQueue.remove(uuid)

        // De-bounce.
        guard self.shouldUpdateUuid(uuid) else {
            return
        }

        Logger.verbose("Updating: \(SignalServiceAddress(uuid: uuid))")

        // Perform update.
        isUpdateInFlight = true

        // We need to throttle these jobs.
        //
        // The profile fetch rate limit is a bucket size of 4320, which
        // refills at a rate of 3 per minute.
        //
        // This class handles the "bulk" profile fetches which
        // are common but not urgent.  The app also does other
        // "blocking" profile fetches which are less common but urgent.
        // To ensure that "blocking" profile fetches never fail,
        // the "bulk" profile fetches need to be cautious. This
        // takes two forms:
        //
        // * Rate-limiting bulk profiles somewhat (faster than the
        //   service rate limit).
        // * Backing off aggressively if we hit the rate limit.
        //
        // Always wait N seconds between update jobs.
        let updateDelaySeconds: TimeInterval = 0.1

        var hasHitRateLimitRecently = false
        if let lastRateLimitErrorDate = self.lastRateLimitErrorDate {
            let minElapsedSeconds = 5 * kMinuteInterval
            let elapsedSeconds = abs(lastRateLimitErrorDate.timeIntervalSinceNow)
            if elapsedSeconds < minElapsedSeconds {
                hasHitRateLimitRecently = true
            }
        }

        firstly { () -> Guarantee<Void> in
            if hasHitRateLimitRecently {
                // Wait before updating if we've recently hit the rate limit.
                // This will give the rate limit bucket time to refill.
                return after(seconds: 20.0)
            } else {
                return Guarantee.value(())
            }
        }.then(on: .global()) {
            self.profileManager.fetchProfile(forAddressPromise: SignalServiceAddress(uuid: uuid),
                                             mainAppOnly: true,
                                             ignoreThrottling: false).asVoid()
        }.done(on: .global()) {
            self.serialQueue.asyncAfter(deadline: DispatchTime.now() + updateDelaySeconds) {
                self.isUpdateInFlight = false
                self.lastOutcomeMap[uuid] = UpdateOutcome(.success)
                self.process()
            }
        }.catch(on: .global()) { error in
            self.serialQueue.asyncAfter(deadline: DispatchTime.now() + updateDelaySeconds) {
                self.isUpdateInFlight = false
                switch error {
                case ProfileFetchError.missing:
                    self.lastOutcomeMap[uuid] = UpdateOutcome(.noProfile)
                case ProfileFetchError.throttled:
                    self.lastOutcomeMap[uuid] = UpdateOutcome(.throttled)
                case ProfileFetchError.rateLimit:
                    Logger.error("Error: \(error)")
                    self.lastOutcomeMap[uuid] = UpdateOutcome(.retryLimit)
                    self.lastRateLimitErrorDate = Date()
                case SignalServiceProfile.ValidationError.invalidIdentityKey:
                    // There will be invalid identity keys on staging that can be safely ignored.
                    if FeatureFlags.isUsingProductionService {
                        owsFailDebug("Error: \(error)")
                    } else {
                        Logger.warn("Error: \(error)")
                    }
                    self.lastOutcomeMap[uuid] = UpdateOutcome(.invalid)
                default:
                    if IsNetworkConnectivityFailure(error) {
                        Logger.warn("Error: \(error)")
                        self.lastOutcomeMap[uuid] = UpdateOutcome(.networkFailure)
                    } else if error.httpStatusCode == 413 {
                        Logger.error("Error: \(error)")
                        self.lastOutcomeMap[uuid] = UpdateOutcome(.retryLimit)
                        self.lastRateLimitErrorDate = Date()
                    } else if error.httpStatusCode == 404 {
                        Logger.error("Error: \(error)")
                        self.lastOutcomeMap[uuid] = UpdateOutcome(.noProfile)
                    } else {
                        // TODO: We may need to handle more status codes.
                        if self.tsAccountManager.isRegisteredAndReady {
                            owsFailDebug("Error: \(error)")
                        } else {
                            Logger.warn("Error: \(error)")
                        }
                        self.lastOutcomeMap[uuid] = UpdateOutcome(.serviceError)
                    }
                }

                self.process()
            }
        }
    }

    private func shouldUpdateUuid(_ uuid: UUID) -> Bool {
        assertOnQueue(serialQueue)

        guard let lastOutcome = lastOutcomeMap[uuid] else {
            return true
        }

        let minElapsedSeconds: TimeInterval
        let elapsedSeconds = abs(lastOutcome.date.timeIntervalSinceNow)

        if DebugFlags.aggressiveProfileFetching.get() {
            minElapsedSeconds = 0
        } else {
            switch lastOutcome.outcome {
            case .networkFailure:
                minElapsedSeconds = 1 * kMinuteInterval
            case .retryLimit:
                minElapsedSeconds = 5 * kMinuteInterval
            case .throttled:
                minElapsedSeconds = 2 * kMinuteInterval
            case .noProfile:
                minElapsedSeconds = 6 * kHourInterval
            case .serviceError:
                minElapsedSeconds = 30 * kMinuteInterval
            case .success:
                minElapsedSeconds = 2 * kMinuteInterval
            case .invalid:
                minElapsedSeconds = 6 * kHourInterval
            }
        }

        return elapsedSeconds >= minElapsedSeconds
    }

    private func fetchMissingAndStaleProfiles() {
        guard !CurrentAppContext().isRunningTests else {
            return
        }
        guard CurrentAppContext().isMainApp else {
            return
        }
        guard tsAccountManager.isRegisteredAndReady else {
            return
        }

        databaseStorage.read(.promise) { (transaction: SDSAnyReadTransaction) -> [OWSUserProfile] in
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short

            var userProfiles = [OWSUserProfile]()
            let userProfileFinder = AnyUserProfileFinder()
            userProfileFinder.enumerateMissingAndStaleUserProfiles(transaction: transaction) { (userProfile: OWSUserProfile) in
                guard !userProfile.publicAddress.isLocalAddress else {
                    // Ignore the local user.
                    return
                }
                var lastFetchDateString = "nil"
                if let lastFetchDate = userProfile.lastFetchDate {
                    lastFetchDateString = formatter.string(from: lastFetchDate)
                }
                var lastMessagingDateString = "nil"
                if let lastMessagingDate = userProfile.lastMessagingDate {
                    lastMessagingDateString = formatter.string(from: lastMessagingDate)
                }
                Logger.verbose("Missing or stale profile: \(userProfile.address), lastFetchDate: \(lastFetchDateString), lastMessagingDate: \(lastMessagingDateString).")
                userProfiles.append(userProfile)
            }
            return userProfiles
        }.map(on: .global()) { (userProfiles: [OWSUserProfile]) -> Void in
            var addresses: [SignalServiceAddress] = userProfiles.map { $0.publicAddress }

            // Limit how many profiles we try to update on launch.
            let maxProfilesToUpdateCount: Int = 25
            if addresses.count > maxProfilesToUpdateCount {
                addresses.shuffle()
                addresses = Array(addresses.prefix(maxProfilesToUpdateCount))
            }

            if !addresses.isEmpty {
                Logger.verbose("Updating profiles: \(addresses.count)")
                self.fetchProfiles(addresses: addresses)
            }

            Logger.verbose("Complete.")
        }.catch(on: .global()) { (error: Error) -> Void in
            owsFailDebug("Error: \(error)")
        }
    }
}
