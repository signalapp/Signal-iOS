//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
public import SignalServiceKit

/// Manages state for banners that might be hidden.
private class BannerHiding {
    private let hiddenStateStore: BannerHidingStore

    /// Encapsulates state for a hidden banner.
    private struct HiddenState: Codable {
        private enum CodingKeys: String, CodingKey {
            case lastHiddenDate
        }

        /// The last time this banner was hidden.
        let lastHiddenDate: Date
    }

    private let hideDuration: TimeInterval

    /// - Parameter hideDuration: how long to hide the banner for, after a hide is recorded
    init(
        hiddenStateStore: BannerHidingStore,
        hideDuration: TimeInterval,
    ) {
        self.hiddenStateStore = hiddenStateStore
        self.hideDuration = hideDuration
    }

    func isHidden(threadUniqueId: String, transaction: DBReadTransaction) -> Bool {
        guard let hiddenState = getHiddenState(forThreadUniqueId: threadUniqueId, transaction: transaction) else {
            // We've never hidden this banner before, so no reason to hide it now.
            return false
        }

        let timeIntervalSinceLastHidden = Date().timeIntervalSince(hiddenState.lastHiddenDate)
        if timeIntervalSinceLastHidden < hideDuration {
            // It has not been sufficiently long since we last hid this banner.
            return true
        }

        return false
    }

    func hide(threadUniqueId: String, transaction: DBWriteTransaction) {
        let stateToWrite = HiddenState(lastHiddenDate: Date())
        hiddenStateStore.writeValueAsJSON(stateToWrite, forThreadUniqueId: threadUniqueId, tx: transaction)
    }

    private func getHiddenState(forThreadUniqueId threadUniqueId: String, transaction: DBReadTransaction) -> HiddenState? {
        do {
            return try hiddenStateStore.fetchJSONAsValue(HiddenState.self, forThreadUniqueId: threadUniqueId, tx: transaction)
        } catch let error {
            owsFailDebug("couldn't fetch banner hiding state: \(error)")
            return nil
        }
    }
}

/// Manages state for the "pending member requests" banner.
private class PendingMemberRequestsBannerHiding: BannerHiding {
    private let requestingMembersStateStore: BannerHidingStore

    init(
        hiddenStateStore: BannerHidingStore,
        requestingMembersStateStore: BannerHidingStore,
        hideDuration: TimeInterval,
    ) {
        self.requestingMembersStateStore = requestingMembersStateStore
        super.init(
            hiddenStateStore: hiddenStateStore,
            hideDuration: hideDuration,
        )
    }

    private struct RequestingMembersState: Codable {
        let requestingMemberAcis: Set<AciUuid>

        enum CodingKeys: String, CodingKey {
            case requestingMemberAcis = "requestingMemberUuids"
        }
    }

    func isHidden(
        currentRequestingMemberAcis: [Aci],
        threadUniqueId: String,
        transaction: DBReadTransaction,
    ) -> Bool {
        guard isHidden(threadUniqueId: threadUniqueId, transaction: transaction) else {
            return false
        }

        // We may want to show the banner, even if it is hidden, if we have
        // pending member requests we didn't know about last time we snoozed.

        let persistedMemberRequestAcis: [Aci] = getRequestingMembersState(
            forThreadUniqueId: threadUniqueId,
            transaction: transaction,
        )?.requestingMemberAcis.map({ $0.wrappedValue }) ?? []

        return Set(currentRequestingMemberAcis).subtracting(persistedMemberRequestAcis).isEmpty
    }

    func hide(
        currentPendingMemberRequestAcis: [Aci],
        threadUniqueId: String,
        transaction: DBWriteTransaction,
    ) {
        super.hide(threadUniqueId: threadUniqueId, transaction: transaction)

        let newPendingMemberRequestState = RequestingMembersState(
            requestingMemberAcis: Set(currentPendingMemberRequestAcis.map { $0.codableUuid }),
        )

        requestingMembersStateStore.writeValueAsJSON(newPendingMemberRequestState, forThreadUniqueId: threadUniqueId, tx: transaction)
    }

    private func getRequestingMembersState(
        forThreadUniqueId threadUniqueId: String,
        transaction: DBReadTransaction,
    ) -> RequestingMembersState? {
        do {
            return try requestingMembersStateStore.fetchJSONAsValue(
                RequestingMembersState.self,
                forThreadUniqueId: threadUniqueId,
                tx: transaction,
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
        hiddenStateStore: .joinRequestHiddenStore,
        requestingMembersStateStore: .joinRequestMembersStore,
        hideDuration: .week,
    )

    /// This banner will snooze for only 1 hour after each hiding, since this
    /// is a potential safety concern (and only appears in message requests).
    private static let isMessageRequestNameCollisionBannerHiding = BannerHiding(
        hiddenStateStore: .nameCollisionHiddenStore,
        hideDuration: .hour,
    )

    func shouldShowPendingMemberRequestsBanner(
        currentPendingMembers: some Sequence<SignalServiceAddress>,
        transaction: DBReadTransaction,
    ) -> Bool {
        let currentPendingMemberAcis = currentPendingMembers.compactMap { $0.serviceId as? Aci }

        return !Self.isPendingMemberRequestsBannerHiding.isHidden(
            currentRequestingMemberAcis: currentPendingMemberAcis,
            threadUniqueId: threadUniqueId,
            transaction: transaction,
        )
    }

    func hidePendingMemberRequestsBanner(
        currentPendingMembers: some Sequence<SignalServiceAddress>,
        transaction: DBWriteTransaction,
    ) {
        let currentPendingMemberAcis = currentPendingMembers.compactMap { $0.serviceId as? Aci }

        Self.isPendingMemberRequestsBannerHiding.hide(
            currentPendingMemberRequestAcis: currentPendingMemberAcis,
            threadUniqueId: threadUniqueId,
            transaction: transaction,
        )
    }

    func shouldShowMessageRequestNameCollisionBanner(transaction: DBReadTransaction) -> Bool {
        !Self.isMessageRequestNameCollisionBannerHiding.isHidden(threadUniqueId: threadUniqueId, transaction: transaction)
    }

    func hideMessageRequestNameCollisionBanner(transaction: DBWriteTransaction) {
        Self.isMessageRequestNameCollisionBannerHiding.hide(threadUniqueId: threadUniqueId, transaction: transaction)
    }
}
