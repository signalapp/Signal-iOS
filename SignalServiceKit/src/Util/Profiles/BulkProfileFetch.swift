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
            case success
            case networkFailure
            case requestFailure(ProfileRequestError)
            case otherFailure
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
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }
        guard let localIdentifiers = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
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
            tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered,
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
        } catch ProfileRequestError.rateLimit {
            lastRateLimitErrorDate = Date()
            lastOutcomeMap[serviceId] = UpdateOutcome(.requestFailure(.rateLimit))
        } catch let error as ProfileRequestError {
            lastOutcomeMap[serviceId] = UpdateOutcome(.requestFailure(error))
        } catch where error.isNetworkFailureOrTimeout {
            lastOutcomeMap[serviceId] = UpdateOutcome(.networkFailure)
        } catch {
            lastOutcomeMap[serviceId] = UpdateOutcome(.otherFailure)
        }
    }

    private func shouldUpdateServiceId(_ serviceId: ServiceId) -> Bool {
        guard let lastOutcome = lastOutcomeMap[serviceId] else {
            return true
        }

        let retryDelay: TimeInterval
        if DebugFlags.aggressiveProfileFetching.get() {
            retryDelay = 0
        } else {
            switch lastOutcome.outcome {
            case .success:
                retryDelay = 2 * kMinuteInterval
            case .networkFailure:
                retryDelay = 1 * kMinuteInterval
            case .requestFailure(.notAuthorized):
                retryDelay = 30 * kMinuteInterval
            case .requestFailure(.notFound):
                retryDelay = 6 * kHourInterval
            case .requestFailure(.rateLimit):
                retryDelay = 5 * kMinuteInterval
            case .otherFailure:
                retryDelay = 30 * kMinuteInterval
            }
        }

        return -lastOutcome.date.timeIntervalSinceNow >= retryDelay
    }

    private func fetchMissingAndStaleProfiles() {
        guard CurrentAppContext().isMainApp else {
            return
        }
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
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
