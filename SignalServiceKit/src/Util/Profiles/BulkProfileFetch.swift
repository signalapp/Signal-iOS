//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public actor BulkProfileFetch {

    private var serviceIdQueue = OrderedSet<ServiceId>()

    private var isUpdateInFlight = false

    private struct UpdateOutcome {
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

    private var lastOutcomeMap = LRUCache<ServiceId, UpdateOutcome>(maxSize: 16 * 1000, nseMaxSize: 4 * 1000)

    private var lastRateLimitErrorDate: Date?

    private var observers = [NSObjectProtocol]()

    private let databaseStorage: SDSDatabaseStorage
    private let reachabilityManager: SSKReachabilityManager
    private let tsAccountManager: TSAccountManager

    public init(
        databaseStorage: SDSDatabaseStorage,
        reachabilityManager: SSKReachabilityManager,
        tsAccountManager: TSAccountManager
    ) {
        self.databaseStorage = databaseStorage
        self.reachabilityManager = reachabilityManager
        self.tsAccountManager = tsAccountManager

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            Task {
                await self.registerObservers()
                await self.process()
                // Try to update missing & stale profiles on launch.
                await self.fetchMissingAndStaleProfiles()
            }
        }
    }

    private func registerObservers() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(
            forName: SSKReachability.owsReachabilityDidChange,
            object: nil,
            queue: nil,
            using: { _ in Task { await self.process() } }
        ))
        observers.append(nc.addObserver(
            forName: .registrationStateDidChange,
            object: nil,
            queue: nil,
            using: { _ in Task { await self.process() } }
        ))
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // This should be used for non-urgent profile updates.
    public nonisolated func fetchProfiles(thread: TSThread) {
        var addresses = Set(thread.recipientAddressesWithSneakyTransaction)
        if let groupThread = thread as? TSGroupThread, let groupModel = groupThread.groupModel as? TSGroupModelV2 {
            addresses.formUnion(groupModel.droppedMembers)
        }
        fetchProfiles(addresses: Array(addresses))
    }

    // This should be used for non-urgent profile updates.
    public nonisolated func fetchProfile(address: SignalServiceAddress) {
        fetchProfiles(addresses: [address])
    }

    // This should be used for non-urgent profile updates.
    public nonisolated func fetchProfiles(addresses: [SignalServiceAddress]) {
        let serviceIds = addresses.compactMap { $0.serviceId }
        fetchProfiles(serviceIds: serviceIds)
    }

    // This should be used for non-urgent profile updates.
    public nonisolated func fetchProfile(serviceId: ServiceId) {
        fetchProfiles(serviceIds: [serviceId])
    }

    // This should be used for non-urgent profile updates.
    public nonisolated func fetchProfiles(serviceIds: [ServiceId]) {
        Task {
            await self._fetchProfiles(serviceIds: serviceIds)
        }
    }

    private func _fetchProfiles(serviceIds: [ServiceId]) async {
        guard tsAccountManager.isRegisteredAndReady else {
            return
        }
        guard let localIdentifiers = tsAccountManager.localIdentifiers else {
            owsFailDebug("missing localIdentifiers")
            return
        }
        for serviceId in serviceIds {
            if localIdentifiers.contains(serviceId: serviceId) {
                continue
            }
            if serviceIdQueue.contains(serviceId) {
                continue
            }
            serviceIdQueue.append(serviceId)
        }
        await process()
    }

    private func dequeueServiceIdToUpdate() -> ServiceId? {
        while true {
            // Dequeue.
            guard let serviceId = serviceIdQueue.first else {
                return nil
            }
            serviceIdQueue.remove(serviceId)

            // De-bounce.
            guard shouldUpdateServiceId(serviceId) else {
                continue
            }

            return serviceId
        }
    }

    private func process() async {
        // Only one update in flight at a time.
        guard !isUpdateInFlight else {
            return
        }

        guard
            CurrentAppContext().isMainApp,
            reachabilityManager.isReachable,
            tsAccountManager.isRegisteredAndReady,
            !DebugFlags.reduceLogChatter
        else {
            return
        }

        guard let serviceId = dequeueServiceIdToUpdate() else {
            return
        }

        isUpdateInFlight = true

        defer {
            Task {
                // We need to throttle these jobs.
                //
                // The profile fetch rate limit is a bucket size of 4320, which refills at
                // a rate of 3 per minute.
                //
                // This class handles the "bulk" profile fetches which are common but not
                // urgent. The app also does other "blocking" profile fetches which are
                // urgent but not common. To help ensure that "blocking" profile fetches
                // succeed, the "bulk" profile fetches are cautious. This takes two forms:
                //
                // * Rate-limiting bulk profiles faster than the service's rate limit.
                // * Backing off aggressively if we hit the rate limit.
                try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
                self.isUpdateInFlight = false
                await self.process()
            }
        }

        // Wait before updating if we've recently hit the rate limit.
        // This will give the rate limit bucket time to refill.
        if let lastRateLimitErrorDate, -lastRateLimitErrorDate.timeIntervalSinceNow < 5*kMinuteInterval {
            try? await Task.sleep(nanoseconds: 20 * NSEC_PER_SEC)
        }

        do {
            try await ProfileFetcherJob.fetchProfilePromise(serviceId: serviceId).asVoid().awaitable()
            lastOutcomeMap[serviceId] = UpdateOutcome(.success)
        } catch ProfileFetchError.missing {
            lastOutcomeMap[serviceId] = UpdateOutcome(.noProfile)
        } catch ProfileFetchError.throttled {
            lastOutcomeMap[serviceId] = UpdateOutcome(.throttled)
        } catch ProfileFetchError.rateLimit {
            Logger.error("Rate limit error")
            lastOutcomeMap[serviceId] = UpdateOutcome(.retryLimit)
            lastRateLimitErrorDate = Date()
        } catch SignalServiceProfile.ValidationError.invalidIdentityKey {
            // There will be invalid identity keys on staging that can be safely ignored.
            owsFailDebug("Invalid identity key")
            lastOutcomeMap[serviceId] = UpdateOutcome(.invalid)
        } catch {
            if error.isNetworkFailureOrTimeout {
                Logger.warn("Error: \(error)")
                lastOutcomeMap[serviceId] = UpdateOutcome(.networkFailure)
            } else if error.httpStatusCode == 413 || error.httpStatusCode == 429 {
                Logger.error("Error: \(error)")
                lastOutcomeMap[serviceId] = UpdateOutcome(.retryLimit)
                lastRateLimitErrorDate = Date()
            } else if error.httpStatusCode == 404 {
                Logger.error("Error: \(error)")
                lastOutcomeMap[serviceId] = UpdateOutcome(.noProfile)
            } else {
                // TODO: We may need to handle more status codes.
                if tsAccountManager.isRegisteredAndReady {
                    owsFailDebug("Error: \(error)")
                } else {
                    Logger.warn("Error: \(error)")
                }
                lastOutcomeMap[serviceId] = UpdateOutcome(.serviceError)
            }
        }
    }

    private func shouldUpdateServiceId(_ serviceId: ServiceId) -> Bool {
        guard let lastOutcome = lastOutcomeMap[serviceId] else {
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
        guard CurrentAppContext().isMainApp else {
            return
        }
        guard tsAccountManager.isRegisteredAndReady else {
            return
        }

        let userProfiles = databaseStorage.read { tx in
            var userProfiles = [OWSUserProfile]()
            UserProfileFinder().enumerateMissingAndStaleUserProfiles(transaction: tx) { userProfile in
                guard !userProfile.publicAddress.isLocalAddress else {
                    // Ignore the local user.
                    return
                }
                userProfiles.append(userProfile)
            }
            return userProfiles
        }

        // Limit how many profiles we try to update on launch.
        let limit: Int = 25
        fetchProfiles(addresses: Array(userProfiles.lazy.map({ $0.publicAddress }).shuffled().prefix(limit)))
    }
}
