//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit

/// Manages state for banners that might be hidden.
private class BannerHiding {
    private static func hiddenStateKey(forThreadId threadId: String) -> String {
        "hiddenState_\(threadId)"
    }

    /// Encapsulates state for a hidden banner.
    private struct HiddenState: Codable {
        private enum CodingKeys: String, CodingKey {
            case lastHiddenDate
            case numberOfTimesHidden
        }

        /// The last time this banner was hidden.
        let lastHiddenDate: Date

        /// How many times this banner has been hidden.
        let numberOfTimesHidden: UInt
    }

    let bannerHidingStore: SDSKeyValueStore

    private let hideDuration: TimeInterval
    private let hideForeverAfterNumberOfHides: UInt?

    /// - Parameter identifier: an identifier for the banner whose hides we are tracking
    /// - Parameter hideDuration: how long to hide the banner for, after a hide is recorded
    /// - Parameter hideForeverAfterNumberOfHides: after this many manual hides, the banner will be hidden forever. If `nil`, the banner is never hidden forever.
    init(
        identifier: String,
        hideDuration: TimeInterval,
        hideForeverAfterNumberOfHides: UInt? = nil
    ) {
        bannerHidingStore = SDSKeyValueStore(collection: identifier)

        self.hideDuration = hideDuration
        self.hideForeverAfterNumberOfHides = hideForeverAfterNumberOfHides
    }

    func isHidden(threadUniqueId threadId: String, transaction: SDSAnyReadTransaction) -> Bool {
        guard let hiddenState = getHiddenState(forThreadId: threadId, transaction: transaction) else {
            // We've never hidden this banner before, so no reason to hide it now.
            return false
        }

        if
            let hideForeverAfterNumberOfHides = hideForeverAfterNumberOfHides,
            hiddenState.numberOfTimesHidden >= hideForeverAfterNumberOfHides
        {
            // This banner was hidden too many times, and is now hidden forever.
            return true
        }

        let timeIntervalSinceLastHidden = Date().timeIntervalSince(hiddenState.lastHiddenDate)
        if timeIntervalSinceLastHidden < hideDuration {
            // It has not been sufficiently long since we last hid this banner.
            return true
        }

        return false
    }

    func hide(threadUniqueId threadId: String, transaction: SDSAnyWriteTransaction) {
        let stateToWrite: HiddenState

        if let existingHiddenState = getHiddenState(forThreadId: threadId, transaction: transaction) {
            stateToWrite = HiddenState(
                lastHiddenDate: Date(),
                numberOfTimesHidden: existingHiddenState.numberOfTimesHidden + 1
            )
        } else {
            stateToWrite = HiddenState(lastHiddenDate: Date(), numberOfTimesHidden: 1)
        }

        do {
            try bannerHidingStore.setCodable(
                stateToWrite,
                key: Self.hiddenStateKey(forThreadId: threadId),
                transaction: transaction
            )
        } catch let error {
            owsFailDebug("Caught error while encoding banner hiding state: \(error)!")
        }
    }

    private func getHiddenState(forThreadId threadId: String, transaction: SDSAnyReadTransaction) -> HiddenState? {
        do {
            return try bannerHidingStore.getCodableValue(
                forKey: Self.hiddenStateKey(forThreadId: threadId),
                transaction: transaction
            )
        } catch let error {
            owsFailDebug("Caught error while getting banner hiding state: \(error)!")
            return nil
        }
    }
}

/// Manages state for the "pending member requests" banner.
private class PendingMemberRequestsBannerHiding: BannerHiding {
    private struct RequestingMembersState: Codable {
        let requestingMemberAcis: Set<AciUuid>

        enum CodingKeys: String, CodingKey {
            case requestingMemberAcis = "requestingMemberUuids"
        }
    }

    private static func requestingMembersStateKey(forThreadId threadId: String) -> String {
        "requestingMembersState_\(threadId)"
    }

    func isHidden(
        currentRequestingMemberAcis: [Aci],
        threadUniqueId threadId: String,
        transaction: SDSAnyReadTransaction
    ) -> Bool {
        guard isHidden(threadUniqueId: threadId, transaction: transaction) else {
            return false
        }

        // We may want to show the banner, even if it is hidden, if we have
        // pending member requests we didn't know about last time we snoozed.

        let persistedMemberRequestAcis: [Aci] = getRequestingMembersState(
            forThreadId: threadId,
            transaction: transaction
        )?.requestingMemberAcis.map({ $0.wrappedValue }) ?? []

        return Set(currentRequestingMemberAcis).subtracting(persistedMemberRequestAcis).isEmpty
    }

    func hide(
        currentPendingMemberRequestAcis: [Aci],
        threadUniqueId threadId: String,
        transaction: SDSAnyWriteTransaction
    ) {
        super.hide(threadUniqueId: threadId, transaction: transaction)

        do {
            let newPendingMemberRequestState = RequestingMembersState(
                requestingMemberAcis: Set(currentPendingMemberRequestAcis.map { $0.codableUuid })
            )

            try bannerHidingStore.setCodable(
                newPendingMemberRequestState,
                key: Self.requestingMembersStateKey(forThreadId: threadId),
                transaction: transaction
            )
        } catch let error {
            owsFailDebug("Caught error while encoding banner hiding state: \(error)!")
        }
    }

    private func getRequestingMembersState(
        forThreadId threadId: String,
        transaction: SDSAnyReadTransaction
    ) -> RequestingMembersState? {
        do {
            return try bannerHidingStore.getCodableValue(
                forKey: Self.requestingMembersStateKey(forThreadId: threadId),
                transaction: transaction
            )
        } catch let error {
            owsFailDebug("Caught error while getting banner hiding state: \(error)!")
            return nil
        }
    }
}

public extension CVViewState {

    /// This banner will snooze for 1 week after each hiding, and is
    /// responsive to changes in pending member request state.
    private static let isPendingMemberRequestsBannerHiding = PendingMemberRequestsBannerHiding(
        identifier: "BannerHiding_pendingMemberRequests",
        hideDuration: kWeekInterval
    )

    /// This banner will snooze for only 1 hour after each hiding, since this
    /// is a potential safety concern (and only appears in message requests).
    private static let isMessageRequestNameCollisionBannerHiding = BannerHiding(
        identifier: "BannerHiding_messageRequestNameCollision",
        hideDuration: kHourInterval
    )

    func shouldShowPendingMemberRequestsBanner(
        currentPendingMembers: some Sequence<SignalServiceAddress>,
        transaction: SDSAnyReadTransaction
    ) -> Bool {
        let currentPendingMemberAcis = currentPendingMembers.compactMap { $0.serviceId as? Aci }

        return !Self.isPendingMemberRequestsBannerHiding.isHidden(
            currentRequestingMemberAcis: currentPendingMemberAcis,
            threadUniqueId: threadUniqueId,
            transaction: transaction
        )
    }

    func hidePendingMemberRequestsBanner(
        currentPendingMembers: some Sequence<SignalServiceAddress>,
        transaction: SDSAnyWriteTransaction
    ) {
        let currentPendingMemberAcis = currentPendingMembers.compactMap { $0.serviceId as? Aci }

        Self.isPendingMemberRequestsBannerHiding.hide(
            currentPendingMemberRequestAcis: currentPendingMemberAcis,
            threadUniqueId: threadUniqueId,
            transaction: transaction
        )
    }

    func shouldShowMessageRequestNameCollisionBanner(transaction: SDSAnyReadTransaction) -> Bool {
        !Self.isMessageRequestNameCollisionBannerHiding.isHidden(threadUniqueId: threadUniqueId, transaction: transaction)
    }

    func hideMessageRequestNameCollisionBanner(transaction: SDSAnyWriteTransaction) {
        Self.isMessageRequestNameCollisionBannerHiding.hide(threadUniqueId: threadUniqueId, transaction: transaction)
    }
}
