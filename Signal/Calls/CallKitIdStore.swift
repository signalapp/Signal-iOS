//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit
import SignalUI

class CallKitIdStore {
    private static let phoneNumberStore = SDSKeyValueStore(collection: "TSStorageManagerCallKitIdToPhoneNumberCollection")
    private static let serviceIdStore = SDSKeyValueStore(collection: "TSStorageManagerCallKitIdToUUIDCollection")
    private static let groupIdStore = SDSKeyValueStore(collection: "TSStorageManagerCallKitIdToGroupId")
    private static let callLinkStore = SDSKeyValueStore(collection: "CallKitIdToCallLink")

    static func setGroupThread(_ thread: TSGroupThread, forCallKitId callKitId: String) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            // Make sure it doesn't exist, but only in DEBUG builds.
            assert(!phoneNumberStore.hasValue(forKey: callKitId, transaction: tx))
            assert(!serviceIdStore.hasValue(forKey: callKitId, transaction: tx))
            assert(!groupIdStore.hasValue(forKey: callKitId, transaction: tx))
            assert(!callLinkStore.hasValue(forKey: callKitId, transaction: tx))

            groupIdStore.setData(thread.groupModel.groupId, key: callKitId, transaction: tx)
        }
    }

    static func setContactThread(_ thread: TSContactThread, forCallKitId callKitId: String) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            // Make sure it doesn't exist, but only in DEBUG builds.
            assert(!phoneNumberStore.hasValue(forKey: callKitId, transaction: tx))
            assert(!serviceIdStore.hasValue(forKey: callKitId, transaction: tx))
            assert(!groupIdStore.hasValue(forKey: callKitId, transaction: tx))
            assert(!callLinkStore.hasValue(forKey: callKitId, transaction: tx))

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
            assert(!phoneNumberStore.hasValue(forKey: callKitId, transaction: tx))
            assert(!serviceIdStore.hasValue(forKey: callKitId, transaction: tx))
            assert(!groupIdStore.hasValue(forKey: callKitId, transaction: tx))
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
            if let groupId = groupIdStore.getData(callKitId, transaction: tx) {
                return TSGroupThread.fetch(groupId: groupId, transaction: tx).map { .groupThread($0) }
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
