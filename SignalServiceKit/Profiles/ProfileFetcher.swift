//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct ProfileFetchOptions: OptionSet {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let opportunistic: Self = .init(rawValue: 1 << 0)
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

public enum ProfileFetcherError: Error {
    case skippingOpportunisticFetch
}

public actor ProfileFetcherImpl: ProfileFetcher {
    private let jobCreator: (ServiceId, AuthedAccount) -> ProfileFetcherJob
    private let reachabilityManager: any SSKReachabilityManager
    private let tsAccountManager: any TSAccountManager

    private let recentFetchResults = LRUCache<ServiceId, FetchResult>(maxSize: 16000, nseMaxSize: 4000)

    private struct FetchResult {
        let outcome: Outcome
        enum Outcome {
            case success
            case networkFailure
            case requestFailure(ProfileRequestError)
            case otherFailure
        }
        let completionDate: MonotonicDate

        init(outcome: Outcome, completionDate: MonotonicDate) {
            self.outcome = outcome
            self.completionDate = completionDate
        }
    }

    private var rateLimitExpirationDate: MonotonicDate = .distantPast
    private var scheduledOpportunisticDate: MonotonicDate = .distantPast

    public init(
        db: any DB,
        disappearingMessagesConfigurationStore: any DisappearingMessagesConfigurationStore,
        identityManager: any OWSIdentityManager,
        paymentsHelper: any PaymentsHelper,
        profileManager: any ProfileManager,
        reachabilityManager: any SSKReachabilityManager,
        recipientDatabaseTable: any RecipientDatabaseTable,
        recipientManager: any SignalRecipientManager,
        recipientMerger: any RecipientMerger,
        storageServiceRecordIkmCapabilityStore: any StorageServiceRecordIkmCapabilityStore,
        storageServiceRecordIkmMigrator: any StorageServiceRecordIkmMigrator,
        syncManager: any SyncManagerProtocol,
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
                disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
                identityManager: identityManager,
                paymentsHelper: paymentsHelper,
                profileManager: profileManager,
                recipientDatabaseTable: recipientDatabaseTable,
                recipientManager: recipientManager,
                recipientMerger: recipientMerger,
                storageServiceRecordIkmCapabilityStore: storageServiceRecordIkmCapabilityStore,
                storageServiceRecordIkmMigrator: storageServiceRecordIkmMigrator,
                syncManager: syncManager,
                tsAccountManager: tsAccountManager,
                udManager: udManager,
                versionedProfiles: versionedProfiles
            )
        }
        SwiftSingletons.register(self)
    }

    public nonisolated func fetchProfileSyncImpl(
        for serviceId: ServiceId,
        options: ProfileFetchOptions,
        authedAccount: AuthedAccount
    ) -> Task<FetchedProfile, Error> {
        return Task {
            return try await self.fetchProfileWithOptions(
                serviceId: serviceId,
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
        return try await fetchProfileWithOptions(
            serviceId: serviceId,
            options: options,
            authedAccount: authedAccount
        )
    }

    private func fetchProfileWithOptions(
        serviceId: ServiceId,
        options: ProfileFetchOptions,
        authedAccount: AuthedAccount
    ) async throws -> FetchedProfile {
        if options.contains(.opportunistic) {
            if !CurrentAppContext().isMainApp {
                throw ProfileFetcherError.skippingOpportunisticFetch
            }
            return try await fetchProfileOpportunistically(serviceId: serviceId, authedAccount: authedAccount)
        }
        return try await fetchProfileUrgently(serviceId: serviceId, authedAccount: authedAccount)
    }

    private func fetchProfileOpportunistically(
        serviceId: ServiceId,
        authedAccount: AuthedAccount
    ) async throws -> FetchedProfile {
        if CurrentAppContext().isRunningTests {
            throw ProfileFetcherError.skippingOpportunisticFetch
        }
        guard shouldOpportunisticallyFetch(serviceId: serviceId) else {
            throw ProfileFetcherError.skippingOpportunisticFetch
        }
        guard isRegisteredOrExplicitlyAuthenticated(authedAccount: authedAccount) else {
            throw ProfileFetcherError.skippingOpportunisticFetch
        }
        // We don't need opportunistic fetches for ourself.
        let localIdentifiers = try tsAccountManager.localIdentifiersWithMaybeSneakyTransaction(authedAccount: authedAccount)
        guard !localIdentifiers.contains(serviceId: serviceId) else {
            throw ProfileFetcherError.skippingOpportunisticFetch
        }
        try await waitIfNecessary()
        // Check again since we might have fetched while waiting.
        guard shouldOpportunisticallyFetch(serviceId: serviceId) else {
            throw ProfileFetcherError.skippingOpportunisticFetch
        }
        return try await fetchProfileUrgently(serviceId: serviceId, authedAccount: authedAccount)
    }

    private func isRegisteredOrExplicitlyAuthenticated(authedAccount: AuthedAccount) -> Bool {
        switch authedAccount.info {
        case .implicit:
            return tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
        case .explicit:
            return true
        }
    }

    private func fetchProfileUrgently(
        serviceId: ServiceId,
        authedAccount: AuthedAccount
    ) async throws -> FetchedProfile {
        let result = await Result { try await jobCreator(serviceId, authedAccount).run() }
        let outcome: FetchResult.Outcome
        do {
            _ = try result.get()
            outcome = .success
        } catch let error as ProfileRequestError {
            outcome = .requestFailure(error)
        } catch where error.isNetworkFailureOrTimeout {
            outcome = .networkFailure
        } catch {
            outcome = .otherFailure
        }
        let now = MonotonicDate()
        if case .failure(ProfileRequestError.rateLimit) = result {
            self.rateLimitExpirationDate = now.adding(5*kMinuteInterval)
        }
        self.recentFetchResults[serviceId] = FetchResult(outcome: outcome, completionDate: now)
        return try result.get()
    }

    private func waitIfNecessary() async throws {
        let now = MonotonicDate()

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

        let minimumDelay: TimeInterval
        if now < rateLimitExpirationDate {
            minimumDelay = 20
        } else {
            minimumDelay = 0.1
        }

        let minimumDate = self.scheduledOpportunisticDate.adding(minimumDelay)
        self.scheduledOpportunisticDate = max(now, minimumDate)

        if now < minimumDate {
            try await Task.sleep(nanoseconds: minimumDate - now)
        }
    }

    private func shouldOpportunisticallyFetch(serviceId: ServiceId) -> Bool {
        guard let fetchResult = self.recentFetchResults[serviceId] else {
            return true
        }

        let retryDelay: TimeInterval
        if DebugFlags.aggressiveProfileFetching.get() {
            retryDelay = 0
        } else {
            switch fetchResult.outcome {
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

        return MonotonicDate() > fetchResult.completionDate.adding(retryDelay)
    }
}
