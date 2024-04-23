//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public struct ProfileFetchOptions: OptionSet {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let opportunistic: Self = .init(rawValue: 1 << 0)
    public static let mainAppOnly: Self = .init(rawValue: 1 << 1)
}

public protocol ProfileFetcher {
    func fetchProfileImpl(for serviceId: ServiceId, options: ProfileFetchOptions, authedAccount: AuthedAccount) async throws -> FetchedProfile
    func fetchProfileSyncImpl(for serviceId: ServiceId, options: ProfileFetchOptions, authedAccount: AuthedAccount) -> Task<FetchedProfile, Error>
}

extension ProfileFetcher {
    public func fetchProfile(
        for serviceId: ServiceId,
        options: ProfileFetchOptions = [],
        authedAccount: AuthedAccount = .implicit()
    ) async throws -> FetchedProfile {
        return try await fetchProfileImpl(for: serviceId, options: options, authedAccount: authedAccount)
    }

    func fetchProfileSync(
        for serviceId: ServiceId,
        options: ProfileFetchOptions = [],
        authedAccount: AuthedAccount = .implicit()
    ) -> Task<FetchedProfile, Error> {
        return fetchProfileSyncImpl(for: serviceId, options: options, authedAccount: authedAccount)
    }
}

public actor ProfileFetcherImpl: ProfileFetcher {

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

    private let jobCreator: (ServiceId, AuthedAccount) -> ProfileFetcherJob
    private let reachabilityManager: any SSKReachabilityManager
    private let tsAccountManager: any TSAccountManager

    public init(
        db: any DB,
        identityManager: any OWSIdentityManager,
        paymentsHelper: any PaymentsHelper,
        profileManager: any ProfileManager,
        reachabilityManager: any SSKReachabilityManager,
        recipientDatabaseTable: any RecipientDatabaseTable,
        recipientManager: any SignalRecipientManager,
        recipientMerger: any RecipientMerger,
        tsAccountManager: any TSAccountManager,
        udManager: any OWSUDManager,
        versionedProfiles: any VersionedProfilesSwift
    ) {
        self.reachabilityManager = reachabilityManager
        self.tsAccountManager = tsAccountManager
        self.jobCreator = { serviceId, authedAccount in
            return ProfileFetcherJob(
                serviceId: serviceId,
                authedAccount: authedAccount,
                db: db,
                identityManager: identityManager,
                paymentsHelper: paymentsHelper,
                profileManager: profileManager,
                recipientDatabaseTable: recipientDatabaseTable,
                recipientManager: recipientManager,
                recipientMerger: recipientMerger,
                tsAccountManager: tsAccountManager,
                udManager: udManager,
                versionedProfiles: versionedProfiles
            )
        }

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            Task {
                await self.registerObservers()
                await self.process()
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

    public nonisolated func fetchProfileSyncImpl(
        for serviceId: ServiceId,
        options: ProfileFetchOptions,
        authedAccount: AuthedAccount
    ) -> Task<FetchedProfile, Error> {
        return Task {
            return try await self.fetchProfileImpl(
                for: serviceId,
                options: options,
                authedAccount: authedAccount
            )
        }
    }

    public func fetchProfileImpl(
        for serviceId: ServiceId,
        options: ProfileFetchOptions,
        authedAccount: AuthedAccount
    ) async throws -> FetchedProfile {
        if options.contains(.opportunistic) {
            await self._fetchProfiles(serviceIds: [serviceId])
            // TODO: Clean up this type so that we can pass back real results.
            throw OWSGenericError("Detaching profile fetch because it's opportunistic.")
        }
        // We usually only refresh profiles in the MainApp to decrease the
        // chance of missed SN notifications in the AppExtension for our users
        // who choose not to verify contacts.
        if options.contains(.mainAppOnly), !CurrentAppContext().isMainApp {
            throw OWSGenericError("Skipping profile fetch because we're not the main app.")
        }
        return try await jobCreator(serviceId, authedAccount).run()
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
            _ = try await fetchProfile(for: serviceId)
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
}
