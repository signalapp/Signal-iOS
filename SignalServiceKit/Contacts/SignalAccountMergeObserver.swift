//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

final class SignalAccountMergeObserver: RecipientMergeObserver {
    func willBreakAssociation(for recipient: SignalRecipient, mightReplaceNonnilPhoneNumber: Bool, tx: DBWriteTransaction) {}

    func didLearnAssociation(mergedRecipient: MergedRecipient, tx: DBWriteTransaction) {
        // SignalAccounts are "merged" differently than most other types because
        // the source of truth is phone number. The source of truth is the phone
        // number because a SignalAccount can be thought of as "a system contact
        // who is registered". If a phone number moves from one Signal account (not
        // SignalAccount) to another, then from the perspective of the system
        // contacts, a contact that was registered may no longer be registered, and
        // a system contact may refer to a different Signal account.
        //
        // For example, assume you have Alice (+0100) and Bob (+0199) in your
        // system contacts. Assume that Alice and Bob are both registered, where
        // Alice has ACI_A and Bob has ACI_B. When this method starts executing,
        // we'd expect to have two SignalAccounts. Assume also that Alice has just
        // changed to Bob's phone number.
        //
        // Input: (serviceId: ACI_A, oldPhoneNumber: +0100, newPhoneNumber: +0199)
        //
        // When we merge the SignalRecipient objects (the caller does this before
        // invoking this method), we'll do the following:
        //
        //   SR1: (ACI_A, +0100 -> +0199)
        //   SR2: (ACI_B, +0199 ->  nil )
        //
        // This means that Alice's account now has Bob's phone number and Bob's
        // account has no phone number. (Presumably Bob's account does have a phone
        // number; we just don't know it yet. It may also be the case that Bob's
        // account is now orphaned/deleted.)
        //
        // If we try to merge the SignalAccount objects in the same way, we'll end
        // up with the following:
        //
        //   SA1: (ACI_A, +0100 -> +0199, "Alice's Contact object")
        //   SA2: (ACI_B,      nil      , "Bob's Contact object")
        //
        // This may seem reasonable at first glance, but it's wrong from the
        // perspective of the system contacts. We should no longer have any system
        // contact associated with ACI_B because we don't know what phone number is
        // associated with ACI_B. Similarly, it's actually Bob's system contact
        // (which has the +0199 phone number in it) that's associated with ACI_A,
        // not Alice's system contact. (It is a bit strange to see the wrong name
        // associated with an account, but that's how it works when a phone number
        // moves from one person to another.) Both of these problems would be fixed
        // the next time we call buildSignalAccounts, but we also need to fix them
        // now to ensure we don't keep around stale system contact references.

        let tx = SDSDB.shimOnlyBridge(tx)

        let oldPhoneNumber = mergedRecipient.oldRecipient?.phoneNumber?.stringValue
        let newPhoneNumber = mergedRecipient.newRecipient.phoneNumber?.stringValue

        // The oldPhoneNumber is now associated with nothing. We should delete the
        // SignalAccount if it exists because we no longer have a ServiceId for
        // that phone number, and so we won't believe anyone is registered at that
        // phone number. If someone still is registered, we'll learn about it
        // during the next contact intersection, at which point we'll create a new
        // SignalAccount. In the above example, we are deleting SA1 entirely.
        if let oldPhoneNumber, oldPhoneNumber != newPhoneNumber, let orphanedAccount = fetch(for: oldPhoneNumber, tx: tx) {
            orphanedAccount.anyRemove(transaction: tx)
        }

        // The newPhoneNumber is now associated with ACI_A but it used to be
        // associated with ACI_B. We should update the SignalAccount to ACI_A since
        // that's the ServiceId that's now associated with that system contact. In
        // the above example, we are replacing the ServiceId for SA2.
        if let newPhoneNumber, let claimedAccount = fetch(for: newPhoneNumber, tx: tx) {
            // We prefer to use ACIs instead of PNIs. If we're processing an update
            // that adds a PNI to a SignalRecipient whose ACI we already know, that ACI
            // should be on the SignalAccount, and there's no reason to change it.
            //
            // If for some reason the ServiceId on the SignalAccount is wrong
            // (unexpectedly an ACI, the wrong PNI, etc.), `newServiceId` will contain
            // the correct value (the one that `buildSignalAccounts` uses).
            //
            // If this is an E164-only recipient that we split from an ACI recipient,
            // then we'll have no ServiceId and must delete the SignalAccount because
            // its current ServiceId is wrong.
            switch mergedRecipient.newRecipient.aci ?? mergedRecipient.newRecipient.pni {
            case .some(let newServiceId) where newServiceId == claimedAccount.recipientServiceId:
                // It already matches. Great!
                break
            case .some(let newServiceId):
                claimedAccount.updateServiceId(newServiceId, tx: tx)
            case .none:
                claimedAccount.anyRemove(transaction: tx)
            }
        }
    }

    private func fetch(for phoneNumber: String, tx: DBReadTransaction) -> SignalAccount? {
        return SignalAccountFinder().signalAccount(for: phoneNumber, tx: tx)
    }
}
