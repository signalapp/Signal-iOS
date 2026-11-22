//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalRingRTC
import SignalServiceKit
import SignalUI

class CallKitIdStore {
    private static let phoneNumberStore = NewKeyValueStore(collection: "TSStorageManagerCallKitIdToPhoneNumberCollection")
    private static let serviceIdStore = NewKeyValueStore(collection: "TSStorageManagerCallKitIdToUUIDCollection")
    private static let groupIdStore = NewKeyValueStore(collection: "TSStorageManagerCallKitIdToGroupId")
    private static let callLinkStore = NewKeyValueStore(collection: "CallKitIdToCallLink")

    static func setGroupId(_ groupId: GroupIdentifier, forCallKitId callKitId: String) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            // Make sure it doesn't exist, but only in DEBUG builds.
            assert(phoneNumberStore.fetchValue(String.self, forKey: callKitId, tx: tx) == nil)
            assert(serviceIdStore.fetchValue(String.self, forKey: callKitId, tx: tx) == nil)
            assert(groupIdStore.fetchValue(Data.self, forKey: callKitId, tx: tx) == nil)
            assert(callLinkStore.fetchValue(Data.self, forKey: callKitId, tx: tx) == nil)

            groupIdStore.writeValue(groupId.serialize(), forKey: callKitId, tx: tx)
        }
    }

    static func setContactThread(_ thread: TSContactThread, forCallKitId callKitId: String) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            // Make sure it doesn't exist, but only in DEBUG builds.
            assert(phoneNumberStore.fetchValue(String.self, forKey: callKitId, tx: tx) == nil)
            assert(serviceIdStore.fetchValue(String.self, forKey: callKitId, tx: tx) == nil)
            assert(groupIdStore.fetchValue(Data.self, forKey: callKitId, tx: tx) == nil)
            assert(callLinkStore.fetchValue(Data.self, forKey: callKitId, tx: tx) == nil)

            let address = thread.contactAddress
            if let serviceIdString = address.serviceIdUppercaseString {
                serviceIdStore.writeValue(serviceIdString, forKey: callKitId, tx: tx)
            } else if let phoneNumber = address.phoneNumber {
                owsFailDebug("making a call to an address with no UUID")
                phoneNumberStore.writeValue(phoneNumber, forKey: callKitId, tx: tx)
            } else {
                owsFailDebug("making a call to an address with no phone number or uuid")
            }
        }
    }

    static func setCallLink(_ callLink: CallLink, forCallKitId callKitId: String) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            // Make sure it doesn't exist, but only in DEBUG builds.
            assert(phoneNumberStore.fetchValue(String.self, forKey: callKitId, tx: tx) == nil)
            assert(serviceIdStore.fetchValue(String.self, forKey: callKitId, tx: tx) == nil)
            assert(groupIdStore.fetchValue(Data.self, forKey: callKitId, tx: tx) == nil)
            // Call Links may be stored multiple times...

            callLinkStore.writeValue(callLink.rootKey.bytes, forKey: callKitId, tx: tx)
        }
    }

    static func callTarget(forCallKitId callKitId: String) -> CallTarget? {
        return SSKEnvironment.shared.databaseStorageRef.read { tx -> CallTarget? in
            // Most likely: modern 1:1 calls
            if let serviceIdString = serviceIdStore.fetchValue(String.self, forKey: callKitId, tx: tx) {
                let address = SignalServiceAddress(serviceIdString: serviceIdString)
                return TSContactThread.getWithContactAddress(address, transaction: tx).map { .individual($0) }
            }

            // Next try group calls
            if
                let groupIdData = groupIdStore.fetchValue(Data.self, forKey: callKitId, tx: tx),
                let groupId = try? GroupIdentifier(contents: groupIdData)
            {
                return .groupThread(groupId)
            }

            // Check the phone number store, for very old 1:1 calls.
            if let phoneNumber = phoneNumberStore.fetchValue(String.self, forKey: callKitId, tx: tx) {
                let address = SignalServiceAddress.legacyAddress(serviceIdString: nil, phoneNumber: phoneNumber)
                return TSContactThread.getWithContactAddress(address, transaction: tx).map { .individual($0) }
            }

            if let rootKeyBytes = callLinkStore.fetchValue(Data.self, forKey: callKitId, tx: tx) {
                return (try? CallLinkRootKey(rootKeyBytes)).map { .callLink(CallLink(rootKey: $0)) }
            }

            return nil
        }
    }
}
