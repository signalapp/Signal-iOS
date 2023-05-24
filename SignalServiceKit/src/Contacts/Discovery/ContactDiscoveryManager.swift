//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

/// A ContactDiscoveryManager coordinates CDS lookup requests.
///
/// It serves three main purposes:
///
/// - Ensuring there's only one stateful request in flight at any given
///   time. If there are multiple, we may corrupt the state associated with
///   our quota token. (There can be many concurrent stateless requests.)
///
/// - Ensuring CDS rate limits are respected.
///
/// - Ensuring we don't repeatedly look up the same phone numbers.
public protocol ContactDiscoveryManager {

    /// Performs a CDS lookup.
    ///
    /// Every request has a `mode` which controls its behavior. Requests are
    /// resolved in the order in which they are scheduled. If a stateful request
    /// is ready to start but there's another stateful request in progress, the
    /// former will wait until the latter finishes. Other than that case,
    /// requests are resolved immediately when they are scheduled -- they either
    /// start running or return a rate limit error.
    ///
    /// **A note about Rate Limits:** Large requests are more likely to run into
    /// rate limits than small requests. Even if contact intersection tries to
    /// look up 1,000 phone numbers and fails due to a rate limit, a small
    /// request for a single phone number might not fail. As a result, rate
    /// limits apply only to the current mode and any lower-priority modes. (By
    /// applying them to lower-priority modes, we mitigate a scenario where
    /// UUIDBackfillTask is waiting to run and a smaller contact intersection
    /// runs and further delays UUIDBackfillTask.)
    ///
    /// - Parameters:
    ///   - phoneNumbers: The set of phone numbers to discover.
    ///   - mode:
    ///       A mode that controls the priority of a request, when the request
    ///       is performed, and how it interacts with other requests.
    /// - Returns:
    ///     A set containing recipients that could be discovered. If a phone
    ///     number couldn't be discovered, it will be omitted from the set of
    ///     results. It's worthwhile noting that the discovery process has side
    ///     effects, so callers may choose to ignore the result type and fetch
    ///     updated state directly from the database.
    func lookUp(phoneNumbers: Set<String>, mode: ContactDiscoveryMode) -> Promise<Set<SignalRecipient>>
}

private enum Constant {
    /// In some places we try to discover phone numbers that are missing a UUID.
    /// If this lookup succeeds, we'll stop trying to discover the phone number
    /// because it's no longer missing a UUID. If the lookup doesn't return a
    /// result, the phone number will still be missing a UUID, so we may try to
    /// fetch it again, and again, and again. This timeout controls how long
    /// we'll cache these negative lookup results.
    static let undiscoverableCacheTimeout = 6 * kHourInterval
}

public enum ContactDiscoveryMode {
    /// Perform a lookup as quickly as possible.
    ///
    /// While smaller & faster, these requests are the most expensive, so they
    /// should be avoided unless latency is the top priority.
    ///
    /// As a general rule of thumb, these requests should be for a single phone
    /// number, and there shouldn't be any automatic retries. It should be
    /// obvious to the user that they're performing a lookup, and they should
    /// have to tap the screen each time you call `lookUp` with this mode.
    case oneOffUserRequest

    /// Used by UUIDBackfillTask.
    ///
    /// Notably, incoming messages are blocked until this lookup is complete, so
    /// it's of the utmost importance.
    case uuidBackfill

    /// Used to resolve recipients when sending a message.
    ///
    /// Notably, outgoing messages to specific people/chats are blocked until
    /// this lookup is complete.
    case outgoingMessage

    /// Used when manually migrating a group from v1 to v2.
    case groupMigration

    /// Used during contact intersection.
    case contactIntersection

    static let allCasesOrderedByRateLimitPriority: [ContactDiscoveryMode] = [
        .oneOffUserRequest,
        .uuidBackfill,
        .outgoingMessage,
        .groupMigration,
        .contactIntersection
    ]
}

public final class ContactDiscoveryManagerImpl: NSObject, ContactDiscoveryManager {

    /// Locks all internal state for this object.
    private var lock = UnfairLock()

    private let contactDiscoveryTaskQueue: ContactDiscoveryTaskQueue

    init(contactDiscoveryTaskQueue: ContactDiscoveryTaskQueue) {
        self.contactDiscoveryTaskQueue = contactDiscoveryTaskQueue
        super.init()
        SwiftSingletons.register(self)
    }

    public convenience init(
        db: DB,
        recipientFetcher: RecipientFetcher,
        recipientMerger: RecipientMerger,
        tsAccountManager: TSAccountManager,
        websocketFactory: WebSocketFactory
    ) {
        self.init(
            contactDiscoveryTaskQueue: ContactDiscoveryTaskQueueImpl(
                db: db,
                recipientFetcher: recipientFetcher,
                recipientMerger: recipientMerger,
                tsAccountManager: tsAccountManager,
                websocketFactory: websocketFactory
            )
        )
    }

    public func lookUp(phoneNumbers: Set<String>, mode: ContactDiscoveryMode) -> Promise<Set<SignalRecipient>> {
        let (promise, future) = Promise<Set<SignalRecipient>>.pending()
        let pendingRequest = PendingRequest(mode: mode, phoneNumbers: phoneNumbers, future: future)
        lock.withLock {
            pendingRequests.append(pendingRequest)
            processPendingRequests()
        }
        return promise
    }

    // MARK: - Sending Requests

    private var hasActiveStatefulRequest = false

    /// Requests that are waiting to be sent. Most requests will be removed
    /// almost immediately after they're added.
    private var pendingRequests = [PendingRequest]()

    private struct PendingRequest {
        let mode: ContactDiscoveryMode
        let phoneNumbers: Set<String>
        let future: Future<Set<SignalRecipient>>
    }

    /// Handles any pending requests.
    ///
    /// This should be called whenever a new request is added and whenever a
    /// stateful request completes.
    ///
    /// It's safe to call as frequently as you want -- you could always call it
    /// twice back-to-back, and the behavior would remain correct.
    ///
    /// Any requests subject to an active rate limit will have their Promise
    /// rejected. Any remaining stateless requests will be started. The first
    /// stateful request will also be started if there isn't one in progress.
    private func processPendingRequests() {
        lock.assertOwner()

        // Collect any requests we can't resolve during this pass.
        var remainingRequests = [PendingRequest]()

        // Figure out which retry date should apply to each mode.
        let retryDates = pruneAndResolveRetryDates()

        for pendingRequest in pendingRequests {
            // If this request is being rate limited, throw an error.
            if let retryDate = retryDates[pendingRequest.mode] {
                pendingRequest.future.reject(ContactDiscoveryError(
                    kind: .rateLimit,
                    debugDescription: "cached rate limit",
                    retryable: true,
                    retryAfterDate: retryDate
                ))
                continue
            }

            // If this is a stateless request, start it immediately.
            if pendingRequest.mode == .oneOffUserRequest {
                sendRequest(pendingRequest)
                continue
            }

            // If there's already a stateful request, re-add this to the pending queue.
            if hasActiveStatefulRequest {
                remainingRequests.append(pendingRequest)
                continue
            }

            // If there's not a stateful request, start this one.
            hasActiveStatefulRequest = true
            sendRequest(pendingRequest) {
                self.lock.withLock {
                    self.hasActiveStatefulRequest = false
                    self.processPendingRequests()
                }
            }
        }

        pendingRequests = remainingRequests
    }

    private func sendRequest(_ request: PendingRequest, completion: (() -> Void)? = nil) {
        DispatchQueue.global().async {
            self._sendRequest(request) {
                if let completion {
                    DispatchQueue.global().async(execute: completion)
                }
            }
        }
    }

    private func _sendRequest(_ request: PendingRequest, completion: @escaping () -> Void) {
        lock.assertNotOwner()

        let fetchedPhoneNumbers = undiscoverableCache.phoneNumbersToFetch(for: request)
        firstly {
            contactDiscoveryTaskQueue.perform(for: fetchedPhoneNumbers, mode: request.mode)
        }.recover(on: DispatchQueue.global()) { error -> Promise<Set<SignalRecipient>> in
            self.handleRateLimitErrorIfNeeded(error: error, request: request)
            throw error
        }.done(on: DispatchQueue.global()) { signalRecipients in
            request.future.resolve(signalRecipients)
            self.undiscoverableCache.processResults(signalRecipients, requestedPhoneNumbers: fetchedPhoneNumbers)
            completion()
        }.catch(on: DispatchQueue.global()) { error in
            request.future.reject(error)
            completion()
        }
    }

    // MARK: - Rate Limits

    private var rawRetryDates = [ContactDiscoveryMode: Date]()

    /// Computes the Retry Date that should be used for each mode.
    ///
    /// Every mode will consider its own retry date and the retry date for all
    /// higher-priority modes. It will select the maximum value (ie, the date
    /// that's furthest in the future).
    ///
    /// - Returns:
    ///     A Dictionary with not-yet-expired retry dates for each mode. In
    ///     general, retry dates should be in the future, but callers should use
    ///     a comparison against `nil` to check for active rate limits rather
    ///     than comparing against the current time.
    private func pruneAndResolveRetryDates() -> [ContactDiscoveryMode: Date] {
        lock.assertOwner()

        // First, eliminate any Retry-After values that have expired.
        let now = Date()
        rawRetryDates = rawRetryDates.filter { $0.value > now }
        // Next, determine the date that should be used for each mode. A higher
        // priority mode will always have a shorter Retry-After than a lower
        // priority mode. This ensures rate limits for opportunistic modes (such as
        // contact intersection) don't disable user-interactive lookups.
        var priorRetryDate: Date?
        return ContactDiscoveryMode.allCasesOrderedByRateLimitPriority.reduce(into: [:]) { partialResult, mode in
            let currentRetryDate = [priorRetryDate, rawRetryDates[mode]].compacted().max()
            partialResult[mode] = currentRetryDate
            priorRetryDate = currentRetryDate
        }
    }

    private func handleRateLimitErrorIfNeeded(error: Error, request: PendingRequest) {
        guard let newRetryDate = (error as? ContactDiscoveryError)?.retryAfterDate else {
            return
        }
        lock.withLock {
            let mode = request.mode
            rawRetryDates[mode] = [rawRetryDates[mode], newRetryDate].compacted().max()
        }
    }

    // MARK: - Undiscoverable Phone Number Cache

    private var undiscoverableCache = UndiscoverableCache()

    private struct UndiscoverableCache {
        /// Maps undiscoverable phone numbers to the time we most recently fetched them.
        private var phoneNumberFetchDates = LRUCache<String, Date>(maxSize: 1024)

        func phoneNumbersToFetch(for request: PendingRequest) -> Set<String> {
            // Because of how CDSv2 operates, there's no additional cost to re-fetching
            // numbers in the cache if we're going to send a request. If we've already
            // fetched the numbers once, they'll be part of “previous E164s”.
            //
            // Consider the following example:
            //
            // (1) Perform a lookup for PN1 & PN2. We learn PN2 isn’t discoverable, so
            //     we add it to the cache. We store previousE164s = [PN1, PN2].
            //
            // (2) Perform a lookup for PN2 & PN3.
            //
            //     (a) If we only try to fetch PN3, we'll send previousE164s = [PN1,
            //         PN2] and newE164s = [PN3] to the server, and we'll get back
            //         results for all three numbers.
            //
            //     (b) If we try to fetch PN2 & PN3, we'll send previousE164s = [PN1,
            //         PN2] and newE164s = [PN3] to the server, and we'll get back
            //         results for all three numbers.
            //
            //     In both cases, we send the same request & get the same response.
            //
            // Given this, the cache only provides a benefit in the case where every
            // number we're fetching was recently undiscoverable. Even given this
            // restriction, the cache is useful in practice since there are many cases
            // where we'll try to fetch the same set of phone numbers multiple times.
            return shouldFetchAnyPhoneNumber(for: request) ? request.phoneNumbers : []
        }

        private func shouldFetchAnyPhoneNumber(for request: PendingRequest) -> Bool {
            switch request.mode {
            case .oneOffUserRequest, .uuidBackfill, .contactIntersection:
                // These always perform a fetch -- no need to consult the cache.
                return true
            case .outgoingMessage, .groupMigration:
                // Fall through to check the cache before initiating the request.
                break
            }

            for phoneNumber in request.phoneNumbers {
                guard let fetchDate = phoneNumberFetchDates[phoneNumber] else {
                    // We haven't fetched it yet, so send a request.
                    return true
                }
                guard -fetchDate.timeIntervalSinceNow < Constant.undiscoverableCacheTimeout else {
                    // We haven't fetched it in the past six hours, so send a request.
                    return true
                }
            }
            // Every number was fetched recently, so no need to send a request.
            return false
        }

        func processResults(
            _ signalRecipients: Set<SignalRecipient>,
            requestedPhoneNumbers: Set<String>
        ) {
            let now = Date()
            let missingPhoneNumbers = requestedPhoneNumbers
                .subtracting(signalRecipients.lazy.compactMap { $0.phoneNumber })
            for missingPhoneNumber in missingPhoneNumbers {
                phoneNumberFetchDates[missingPhoneNumber] = now
            }
        }
    }
}
