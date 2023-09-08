//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

enum UniqueRecipientObjectMerger {
    /// Helps merge database objects that have one instance per recipient.
    ///
    /// For example, we expect at most one thread per recipient and one user
    /// profile per recipient, so they use this class. We expect many messages
    /// and receipts for each recipient, so they don't use this method.
    ///
    /// This method will find and return all objects that belong to `recipient`.
    /// For example, if you have separate threads for a recipient's ACI and
    /// phone number, both will be returned. The caller should merge all the
    /// returned objects into a single object.
    ///
    /// This method should be called after adding a new identifier to
    /// `recipient` because there may be separate objects that should now be
    /// merged. However, it's safe to call this method (and run the merging
    /// logic) at any time in the case of bugs or other issues.
    ///
    /// Some objects that match one of `recipient`'s identifiers may not belong
    /// to `recipient`. For example, if an object has some other ACI but
    /// `recipient`'s phone number, it actually belongs to the ACI's recipient.
    /// In these cases, the identifier is removed from the object, and it's not
    /// returned from this method.
    static func fetchAndExpunge<T>(
        for recipient: SignalRecipient,
        serviceIdField: ReferenceWritableKeyPath<T, String?>,
        phoneNumberField: ReferenceWritableKeyPath<T, String?>,
        uniqueIdField: KeyPath<T, String>,
        fetchObjectsForServiceId: (ServiceId) -> [T],
        fetchObjectsForPhoneNumber: (E164) -> [T],
        updateObject: (T) -> Void
    ) -> [T] {
        var results = [T]()

        let aci: Aci? = recipient.aci
        let phoneNumber: E164? = E164(recipient.phoneNumber)
        let pni: Pni? = recipient.pni

        // Find any objects already associated with the ACI. These definitely
        // belong to this account, and we'll pick an arbitrary one to be the winner
        // if there's multiple matches.
        if let aci {
            results.append(contentsOf: fetchObjectsForServiceId(aci))
        }

        // Find objects associated with the phone number and merge or expunge them.
        if let phoneNumber {
            for object in fetchObjectsForPhoneNumber(phoneNumber) {
                let serviceId = object[keyPath: serviceIdField].flatMap({ try? ServiceId.parseFrom(serviceIdString: $0) })
                switch serviceId?.concreteType {
                case .aci(aci), .pni, .none:
                    // This object already matches the ACI, has *any* PNI, or has no ACI/PNI.
                    // In all of these cases, we can claim it based on the phone number match.
                    results.append(object)
                case .aci:
                    // This object is associated with some other ACI; expunge its phone number
                    // because we know it's out of date.
                    Logger.info("Expunging out-of-date phone number from \(type(of: object))")
                    object[keyPath: phoneNumberField] = nil
                    updateObject(object)
                }
            }
        }

        // Find any objects associated with the PNI and merge or expunge them.
        if let pni {
            for object in fetchObjectsForServiceId(pni) {
                switch object[keyPath: phoneNumberField] {
                case .some(phoneNumber?.stringValue), .none:
                    // This object matches the phone number or doesn't have one. We can claim
                    // it for this account.
                    results.append(object)
                case .some:
                    // This object is associated with some other phone number; expunge its PNI
                    // because we know it's out of date.
                    Logger.info("Expunging out-of-date PNI from \(type(of: object))")
                    object[keyPath: serviceIdField] = nil
                    updateObject(object)
                }
            }
        }

        return results.removingDuplicates(uniquingElementsBy: { $0[keyPath: uniqueIdField] })
    }
}
