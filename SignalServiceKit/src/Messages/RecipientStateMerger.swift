//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

final class RecipientStateMerger {
    private let recipientStore: RecipientDataStore
    private let signalServiceAddressCache: SignalServiceAddressCache

    init(
        recipientStore: RecipientDataStore,
        signalServiceAddressCache: SignalServiceAddressCache
    ) {
        self.recipientStore = recipientStore
        self.signalServiceAddressCache = signalServiceAddressCache
    }

    func normalize(_ recipientStates: inout [SignalServiceAddress: TSOutgoingMessageRecipientState]?, tx: DBReadTransaction) {
        guard let oldRecipientStates = recipientStates else {
            return
        }
        var existingValues = [(SignalServiceAddress, TSOutgoingMessageRecipientState)]()
        // If we convert a Pni to an Aci, it's possible the Aci is already in
        // recipientStates. If that's the case, we want to throw away the Pni and
        // defer to the Aci. We do this by handling Pnis after everything else.
        var updatedValues = [(SignalServiceAddress, TSOutgoingMessageRecipientState)]()
        for (oldAddress, recipientState) in oldRecipientStates {
            if let normalizedAddress = normalizedAddressIfNeeded(for: oldAddress, tx: tx) {
                updatedValues.append((normalizedAddress, recipientState))
            } else {
                existingValues.append((oldAddress, recipientState))
            }
        }
        recipientStates = Dictionary(existingValues + updatedValues, uniquingKeysWith: { lhs, _ in lhs })
    }

    func normalizedAddressIfNeeded(for oldAddress: SignalServiceAddress, tx: DBReadTransaction) -> SignalServiceAddress? {
        switch oldAddress.serviceId?.concreteType {
        case .none, .aci:
            return nil
        case .pni(let pni):
            guard let aci = recipientStore.fetchRecipient(serviceId: pni, transaction: tx)?.aci else {
                return nil
            }
            return SignalServiceAddress(
                serviceId: aci,
                phoneNumber: nil,
                cache: signalServiceAddressCache,
                cachePolicy: .preferCachedPhoneNumberAndListenForUpdates
            )
        }
    }
}
