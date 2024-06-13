//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class CallKitIdStore {
    private static let phoneNumberStore = SDSKeyValueStore(collection: "TSStorageManagerCallKitIdToPhoneNumberCollection")
    private static let serviceIdStore = SDSKeyValueStore(collection: "TSStorageManagerCallKitIdToUUIDCollection")
    private static let groupIdStore = SDSKeyValueStore(collection: "TSStorageManagerCallKitIdToGroupId")

    static func setThread(_ thread: TSThread, forCallKitId callKitId: String) {
        NSObject.databaseStorage.write { tx in
            if let groupModel = thread.groupModelIfGroupThread {
                groupIdStore.setData(groupModel.groupId, key: callKitId, transaction: tx)
                // This is probably overkill since we currently generate these IDs randomly,
                // but better futureproof than sorry.
                serviceIdStore.removeValue(forKey: callKitId, transaction: tx)
                phoneNumberStore.removeValue(forKey: callKitId, transaction: tx)
            } else if let contactThread = thread as? TSContactThread {
                let address = contactThread.contactAddress
                if let serviceIdString = address.serviceIdUppercaseString {
                    serviceIdStore.setString(serviceIdString, key: callKitId, transaction: tx)
                    phoneNumberStore.removeValue(forKey: callKitId, transaction: tx)
                } else if let phoneNumber = address.phoneNumber {
                    owsFailDebug("making a call to an address with no UUID")
                    phoneNumberStore.setString(phoneNumber, key: callKitId, transaction: tx)
                    serviceIdStore.removeValue(forKey: callKitId, transaction: tx)
                } else {
                    owsFailDebug("making a call to an address with no phone number or uuid")
                }
                groupIdStore.removeValue(forKey: callKitId, transaction: tx)
            } else {
                owsFailDebug("Unexpected type of thread: \(type(of: thread))")
            }
        }
    }

    static func thread(forCallKitId callKitId: String) -> TSThread? {
        return NSObject.databaseStorage.read { tx in
            // Most likely: modern 1:1 calls
            if let serviceIdString = serviceIdStore.getString(callKitId, transaction: tx) {
                let address = SignalServiceAddress(serviceIdString: serviceIdString)
                return TSContactThread.getWithContactAddress(address, transaction: tx)
            }

            // Next try group calls
            if let groupId = groupIdStore.getData(callKitId, transaction: tx) {
                return TSGroupThread.fetch(groupId: groupId, transaction: tx)
            }

            // Finally check the phone number store, for very old 1:1 calls.
            if let phoneNumber = phoneNumberStore.getString(callKitId, transaction: tx) {
                let address = SignalServiceAddress.legacyAddress(serviceIdString: nil, phoneNumber: phoneNumber)
                return TSContactThread.getWithContactAddress(address, transaction: tx)
            }

            return nil
        }
    }
}
