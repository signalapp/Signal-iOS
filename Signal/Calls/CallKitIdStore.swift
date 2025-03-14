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
    private static let phoneNumberStore = KeyValueStore(collection: "TSStorageManagerCallKitIdToPhoneNumberCollection")
    private static let serviceIdStore = KeyValueStore(collection: "TSStorageManagerCallKitIdToUUIDCollection")
    private static let groupIdStore = KeyValueStore(collection: "TSStorageManagerCallKitIdToGroupId")
    private static let callLinkStore = KeyValueStore(collection: "CallKitIdToCallLink")

    static func setGroupId(_ groupId: GroupIdentifier, forCallKitId callKitId: String) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            // Make sure it doesn't exist, but only in DEBUG builds.
            assert(!phoneNumberStore.hasValue(callKitId, transaction: tx))
            assert(!serviceIdStore.hasValue(callKitId, transaction: tx))
            assert(!groupIdStore.hasValue(callKitId, transaction: tx))
            assert(!callLinkStore.hasValue(callKitId, transaction: tx))

            groupIdStore.setData(groupId.serialize().asData, key: callKitId, transaction: tx)
        }
    }

    static func setContactThread(_ thread: TSContactThread, forCallKitId callKitId: String) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            // Make sure it doesn't exist, but only in DEBUG builds.
            assert(!phoneNumberStore.hasValue(callKitId, transaction: tx))
            assert(!serviceIdStore.hasValue(callKitId, transaction: tx))
            assert(!groupIdStore.hasValue(callKitId, transaction: tx))
            assert(!callLinkStore.hasValue(callKitId, transaction: tx))

            let address = thread.contactAddress
            if let serviceIdString = address.serviceIdUppercaseString {
                serviceIdStore.setString(serviceIdString, key: callKitId, transaction: tx)
            } else if let phoneNumber = address.phoneNumber {
                owsFailDebug("making a call to an address with no UUID")
                phoneNumberStore.setString(phoneNumber, key: callKitId, transaction: tx)
            } else {
                owsFailDebug("making a call to an address with no phone number or uuid")
            }
        }
    }

    static func setCallLink(_ callLink: CallLink, forCallKitId callKitId: String) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            // Make sure it doesn't exist, but only in DEBUG builds.
            assert(!phoneNumberStore.hasValue(callKitId, transaction: tx))
            assert(!serviceIdStore.hasValue(callKitId, transaction: tx))
            assert(!groupIdStore.hasValue(callKitId, transaction: tx))
            // Call Links may be stored multiple times...

            callLinkStore.setData(callLink.rootKey.bytes, key: callKitId, transaction: tx)
        }
    }

    static func callTarget(forCallKitId callKitId: String) -> CallTarget? {
        return SSKEnvironment.shared.databaseStorageRef.read { tx -> CallTarget? in
            // Most likely: modern 1:1 calls
            if let serviceIdString = serviceIdStore.getString(callKitId, transaction: tx) {
                let address = SignalServiceAddress(serviceIdString: serviceIdString)
                return TSContactThread.getWithContactAddress(address, transaction: tx).map { .individual($0) }
            }

            // Next try group calls
            if
                let groupIdData = groupIdStore.getData(callKitId, transaction: tx),
                let groupId = try? GroupIdentifier(contents: [UInt8](groupIdData))
            {
                return .groupThread(groupId)
            }

            // Check the phone number store, for very old 1:1 calls.
            if let phoneNumber = phoneNumberStore.getString(callKitId, transaction: tx) {
                let address = SignalServiceAddress.legacyAddress(serviceIdString: nil, phoneNumber: phoneNumber)
                return TSContactThread.getWithContactAddress(address, transaction: tx).map { .individual($0) }
            }

            if let rootKeyBytes = callLinkStore.getData(callKitId, transaction: tx) {
                return (try? CallLinkRootKey(rootKeyBytes)).map { .callLink(CallLink(rootKey: $0)) }
            }

            return nil
        }
    }
}
