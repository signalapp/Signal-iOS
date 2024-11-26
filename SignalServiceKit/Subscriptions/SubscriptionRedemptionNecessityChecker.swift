//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

protocol SubscriptionRedemptionNecessityCheckerStore {
    func subscriberId(tx: DBReadTransaction) -> Data?

    func getLastRedemptionNecessaryCheck(tx: DBReadTransaction) -> Date?
    func setLastRedemptionNecessaryCheck(_ now: Date, tx: DBWriteTransaction)

    func getLastSubscriptionRenewalDate(tx: DBReadTransaction) -> Date?
    func setLastSubscriptionRenewalDate(_ renewalDate: Date, tx: DBWriteTransaction)
}

struct SubscriptionRedemptionNecessityChecker {
    typealias EnqueueRedemptionBlock = (
        _ subscriberId: Data,
        _ subscription: Subscription
    ) async -> Void

    private enum Constants {
        static let intervalBetweenChecks: TimeInterval = 3 * kDayInterval
    }

    private let checkerStore: SubscriptionRedemptionNecessityCheckerStore
    private let dateProvider: DateProvider
    private let db: any DB
    private let logger: PrefixedLogger
    private let networkManager: NetworkManager
    private let tsAccountManager: TSAccountManager

    init(
        checkerStore: SubscriptionRedemptionNecessityCheckerStore,
        dateProvider: @escaping DateProvider,
        db: any DB,
        logger: PrefixedLogger,
        networkManager: NetworkManager,
        tsAccountManager: TSAccountManager
    ) {
        self.checkerStore = checkerStore
        self.dateProvider = dateProvider
        self.db = db
        self.logger = logger
        self.networkManager = networkManager
        self.tsAccountManager = tsAccountManager
    }

    func enqueueRedemptionIfNecessary(enqueueRedemptionBlock: EnqueueRedemptionBlock) async throws {
        let (
            registrationState,
            subscriberId,
            lastRedemptionNecessaryCheck,
            lastSubscriptionRenewalDate
        ): (
            TSRegistrationState,
            Data?,
            Date?,
            Date?
        ) = db.read { tx in
            return (
                tsAccountManager.registrationState(tx: tx),
                checkerStore.subscriberId(tx: tx),
                checkerStore.getLastRedemptionNecessaryCheck(tx: tx),
                checkerStore.getLastSubscriptionRenewalDate(tx: tx)
            )
        }

        guard let subscriberId else {
            /// If we don't have a subscriber ID, there's nothing to do.
            return
        }

        guard registrationState.isRegisteredPrimaryDevice else {
            /// Only primaries manage subscriptions!
            return
        }

        if
            let lastRedemptionNecessaryCheck,
            dateProvider().timeIntervalSince(lastRedemptionNecessaryCheck) < Constants.intervalBetweenChecks
        {
            /// Not necessary to check, we did so recently!
            return
        }

        logger.info("Checking if subscription should be redeemed.")

        /// This "heartbeat" is important to do regularly, as the server will
        /// take cleanup steps on subscriber IDs that haven't had a client
        /// perform a "keep-alive" in a long time (such as canceling the
        /// associated subscription, if possible).
        try await performSubscriberIdHeartbeat(subscriberId)

        let subscription = try await DonationSubscriptionManager.getCurrentSubscriptionStatus(
            for: subscriberId,
            networkManager: networkManager
        ).awaitable()

        /// Record that we attempted redemption, optionally reusing the same
        /// transaction to persist additional state.
        func recordRedemptionAttempt(additionalTxBlock: ((DBWriteTransaction) -> Void)? = nil) async {
            await db.awaitableWrite { tx in
                checkerStore.setLastRedemptionNecessaryCheck(dateProvider(), tx: tx)
                additionalTxBlock?(tx)
            }
        }

        guard let subscription else {
            logger.warn("No subscription for this subscriber ID!")

            await recordRedemptionAttempt()
            return
        }

        let currentSubscriptionRenewalDate = Date(timeIntervalSince1970: subscription.endOfCurrentPeriod)

        if
            let lastSubscriptionRenewalDate,
            lastSubscriptionRenewalDate == currentSubscriptionRenewalDate
        {
            logger.info("Renewal date has not changed since last redemption; bailing out.")
            await recordRedemptionAttempt()
        } else if
            case .pastDue = subscription.status
        {
            /// For some payment methods (e.g., cards), the payment processors
            /// will automatically retry a subscription-renewal payment failure.
            /// While that's happening, the subscription will be "past due".
            ///
            /// Retries will occur on the scale of days, for a period of weeks.
            /// We don't want to attempt badge redemption during this time since
            /// we don't expect to succeed now, but failure doesn't yet mean
            /// much as we may succeed in the future if the payment recovers.
            logger.warn("Subscription failed to renew, but payment processor is retrying. Not yet attempting receipt credential redemption for this period.")
            await recordRedemptionAttempt()
        } else {
            /// When a subscription renews (i.e., there's a new payment to be
            /// redeemed) the "end of period" changes to reflect a later date.
            /// We can use that as signal to know we should go try and redeem
            /// that new payment.
            if let lastSubscriptionRenewalDate {
                logger.info("Attempting to redeem subscription renewal. Last renewal \(lastSubscriptionRenewalDate), current renewal \(currentSubscriptionRenewalDate)")
            } else {
                logger.info("Attempting to redeem subscription renewal. No last renewal, current renewal \(currentSubscriptionRenewalDate)")
            }

            await enqueueRedemptionBlock(subscriberId, subscription)

            /// Save the new renewal date so we can tell when it *next* renews.
            await recordRedemptionAttempt { tx in
                checkerStore.setLastSubscriptionRenewalDate(currentSubscriptionRenewalDate, tx: tx)
            }
        }
    }

    /// Let the server know that a client still cares about this subscriberId.
    private func performSubscriberIdHeartbeat(_ subscriberId: Data) async throws {
        let registerSubscriberIdResponse = try await networkManager.makePromise(
            request: OWSRequestFactory.setSubscriberID(subscriberId)
        ).awaitable()

        guard registerSubscriberIdResponse.responseStatusCode == 200 else {
            throw OWSAssertionError(
                "Unexpected status code registering new Backup subscriber ID! \(registerSubscriberIdResponse.responseStatusCode)",
                logger: logger
            )
        }
    }
}
