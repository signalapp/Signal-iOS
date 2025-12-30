//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct ProfileFetchContext {
    /// If set, GSEs will be used as a fallback auth mechanism.
    var groupId: GroupIdentifier?

    /// If true, the fetch may be arbitrarily dropped if deemed non-critical.
    public var isOpportunistic: Bool

    /// If true, the fetch must try to fetch a new credential.
    public var mustFetchNewCredential: Bool

    public init(groupId: GroupIdentifier? = nil, isOpportunistic: Bool = false, mustFetchNewCredential: Bool = false) {
        self.groupId = groupId
        self.isOpportunistic = isOpportunistic
        self.mustFetchNewCredential = mustFetchNewCredential
    }
}

public protocol ProfileFetcher {
    func fetchProfileImpl(for serviceId: ServiceId, context: ProfileFetchContext, authedAccount: AuthedAccount) async throws -> FetchedProfile
    func fetchProfileSyncImpl(for serviceId: ServiceId, context: ProfileFetchContext, authedAccount: AuthedAccount) -> Task<FetchedProfile, Error>
    func waitForPendingFetches(for serviceId: ServiceId) async throws
}

extension ProfileFetcher {
    public func fetchProfile(
        for serviceId: ServiceId,
        context: ProfileFetchContext = ProfileFetchContext(),
        authedAccount: AuthedAccount = .implicit(),
    ) async throws -> FetchedProfile {
        return try await fetchProfileImpl(for: serviceId, context: context, authedAccount: authedAccount)
    }

    func fetchProfileSync(
        for serviceId: ServiceId,
        context: ProfileFetchContext = ProfileFetchContext(),
        authedAccount: AuthedAccount = .implicit(),
    ) -> Task<FetchedProfile, Error> {
        return fetchProfileSyncImpl(for: serviceId, context: context, authedAccount: authedAccount)
    }
}

public enum ProfileFetcherError: Error, IsRetryableProvider {
    case skippingOpportunisticFetch
    case couldNotFetchCredential

    public var isRetryableProvider: Bool {
        switch self {
        case .skippingOpportunisticFetch: false
        case .couldNotFetchCredential: false
        }
    }
}

public actor ProfileFetcherImpl: ProfileFetcher {
    private let jobCreator: (ServiceId, GroupIdentifier?, _ mustFetchNewCredential: Bool, AuthedAccount) -> ProfileFetcherJob
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

    private nonisolated let inProgressFetches = AtomicValue<[ServiceId: [FetchState]]>([:], lock: .init())

    private class FetchState {
        var waiterContinuations = [CancellableContinuation<Void>]()
    }

    private var rateLimitExpirationDate: MonotonicDate?
    private var scheduledOpportunisticDate: MonotonicDate?

    init(
        accountChecker: AccountChecker,
        db: any DB,
        disappearingMessagesConfigurationStore: any DisappearingMessagesConfigurationStore,
        identityManager: any OWSIdentityManager,
        paymentsHelper: any PaymentsHelper,
        profileManager: any ProfileManager,
        reachabilityManager: any SSKReachabilityManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        syncManager: any SyncManagerProtocol,
        tsAccountManager: any TSAccountManager,
        udManager: any OWSUDManager,
        versionedProfiles: any VersionedProfiles,
    ) {
        self.reachabilityManager = reachabilityManager
        self.tsAccountManager = tsAccountManager
        self.jobCreator = { serviceId, groupIdContext, mustFetchNewCredential, authedAccount in
            return ProfileFetcherJob(
                serviceId: serviceId,
                groupIdContext: groupIdContext,
                mustFetchNewCredential: mustFetchNewCredential,
                authedAccount: authedAccount,
                accountChecker: accountChecker,
                db: db,
                disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
                identityManager: identityManager,
                paymentsHelper: paymentsHelper,
                profileManager: profileManager,
                recipientDatabaseTable: recipientDatabaseTable,
                syncManager: syncManager,
                tsAccountManager: tsAccountManager,
                udManager: udManager,
                versionedProfiles: versionedProfiles,
            )
        }
        SwiftSingletons.register(self)
    }

    private nonisolated func insertFetchState(serviceId: ServiceId) -> FetchState {
        let fetchState = FetchState()
        self.inProgressFetches.update {
            $0[serviceId, default: []].append(fetchState)
        }
        return fetchState
    }

    private nonisolated func finalizeFetchState(
        serviceId: ServiceId,
        fetchState: FetchState,
    ) {
        self.inProgressFetches.update {
            $0[serviceId, default: []].removeAll(where: { $0 === fetchState })
        }
        for waiter in fetchState.waiterContinuations {
            waiter.resume(with: .success(()))
        }
    }

    public nonisolated func fetchProfileSyncImpl(
        for serviceId: ServiceId,
        context: ProfileFetchContext,
        authedAccount: AuthedAccount,
    ) -> Task<FetchedProfile, Error> {
        // Insert this before starting the Task to ensure we've denoted the pending
        // fetch before returning control to the caller.
        let fetchState = insertFetchState(serviceId: serviceId)
        return Task {
            return try await self.fetchProfileWithOptionsAndFinalize(
                serviceId: serviceId,
                fetchState: fetchState,
                context: context,
                authedAccount: authedAccount,
            )
        }
    }

    public func fetchProfileImpl(
        for serviceId: ServiceId,
        context: ProfileFetchContext,
        authedAccount: AuthedAccount,
    ) async throws -> FetchedProfile {
        // We're already running concurrently with other code, so no new race
        // conditions are introduced by calling `insertFetchState` inline.
        return try await fetchProfileWithOptionsAndFinalize(
            serviceId: serviceId,
            fetchState: insertFetchState(serviceId: serviceId),
            context: context,
            authedAccount: authedAccount,
        )
    }

    private func fetchProfileWithOptionsAndFinalize(
        serviceId: ServiceId,
        fetchState: FetchState,
        context: ProfileFetchContext,
        authedAccount: AuthedAccount,
    ) async throws -> FetchedProfile {
        let result = await Result {
            try await fetchProfileWithOptions(
                serviceId: serviceId,
                context: context,
                authedAccount: authedAccount,
            )
        }
        finalizeFetchState(serviceId: serviceId, fetchState: fetchState)
        return try result.get()
    }

    private func fetchProfileWithOptions(
        serviceId: ServiceId,
        context: ProfileFetchContext,
        authedAccount: AuthedAccount,
    ) async throws -> FetchedProfile {
        if context.isOpportunistic {
            if !CurrentAppContext().isMainApp {
                throw ProfileFetcherError.skippingOpportunisticFetch
            }
            return try await fetchProfileOpportunistically(serviceId: serviceId, context: context, authedAccount: authedAccount)
        }
        return try await fetchProfileUrgently(serviceId: serviceId, context: context, authedAccount: authedAccount)
    }

    private func fetchProfileOpportunistically(
        serviceId: ServiceId,
        context: ProfileFetchContext,
        authedAccount: AuthedAccount,
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
        return try await fetchProfileUrgently(serviceId: serviceId, context: context, authedAccount: authedAccount)
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
        context: ProfileFetchContext,
        authedAccount: AuthedAccount,
    ) async throws -> FetchedProfile {
        let result = await Result { try await jobCreator(serviceId, context.groupId, context.mustFetchNewCredential, authedAccount).run() }
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
            self.rateLimitExpirationDate = now.adding(5 * .minute)
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
        if let rateLimitExpirationDate, now < rateLimitExpirationDate {
            minimumDelay = 20
        } else {
            minimumDelay = 0.1
        }

        let minimumDate = self.scheduledOpportunisticDate?.adding(minimumDelay)
        self.scheduledOpportunisticDate = [now, minimumDate].compacted().max()!

        if let minimumDate, now < minimumDate {
            try await Task.sleep(nanoseconds: (minimumDate - now).nanoseconds)
        }
    }

    private func shouldOpportunisticallyFetch(serviceId: ServiceId) -> Bool {
        guard let fetchResult = self.recentFetchResults[serviceId] else {
            return true
        }

        let retryDelay: TimeInterval
        switch fetchResult.outcome {
        case .success:
            retryDelay = 5 * .minute
        case .networkFailure:
            retryDelay = 1 * .minute
        case .requestFailure(.notAuthorized):
            retryDelay = 30 * .minute
        case .requestFailure(.notFound):
            retryDelay = 6 * .hour
        case .requestFailure(.rateLimit):
            retryDelay = 5 * .minute
        case .otherFailure:
            retryDelay = 30 * .minute
        }

        return MonotonicDate() > fetchResult.completionDate.adding(retryDelay)
    }

    // MARK: - Waiting

    public func waitForPendingFetches(for serviceId: ServiceId) async throws {
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            let cancellableContinuations = self.inProgressFetches.update {
                // There might be multiple profile fetches queued up for a single
                // serviceId. We add a CancellableContinuation for *each* of those because
                // we want to wait for whichever takes the longest.
                return $0[serviceId, default: []].map { fetchState in
                    let result = CancellableContinuation<Void>()
                    fetchState.waiterContinuations.append(result)
                    return result
                }
            }
            for cancellableContinuation in cancellableContinuations {
                taskGroup.addTask { try await cancellableContinuation.wait() }
            }
            try await taskGroup.waitForAll()
        }
    }
}
