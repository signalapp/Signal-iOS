//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public typealias AccountId = String

@objc
public class OWSAccountIdFinder: NSObject {

    let uuidMap = SDSKeyValueStore(collection: "account_identifiers_uuids")
    let phoneNumberMap = SDSKeyValueStore(collection: "account_identifiers_phone_numbers")

    @objc
    public func accountId(forAddress address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> AccountId? {
        guard FeatureFlags.allowUUIDOnlyContacts else {
            return address.transitional_phoneNumber
        }

        if let uuid = address.uuid {
            if let accountIdentifier = uuidMap.getString(uuid.uuidString, transaction: transaction) {
                return accountIdentifier
            }
        }

        if let phoneNumber = address.phoneNumber {
            if let accountIdentifier = phoneNumberMap.getString(phoneNumber, transaction: transaction) {
                return accountIdentifier
            }
        }

        return nil
    }

    @objc
    public func ensureAccountId(forAddress address: SignalServiceAddress, transaction: SDSAnyWriteTransaction) -> AccountId {
        guard FeatureFlags.allowUUIDOnlyContacts else {
            return address.transitional_phoneNumber
        }

        if let uuid = address.uuid {
            if let accountIdentifier = uuidMap.getString(uuid.uuidString, transaction: transaction) {
                if let phoneNumber = address.phoneNumber {
                    ensure(phoneNumber: phoneNumber, hasIdentifier: accountIdentifier, transaction: transaction)
                }
                return accountIdentifier
            }
        }

        if let phoneNumber = address.phoneNumber {
            if let accountIdentifier = phoneNumberMap.getString(phoneNumber, transaction: transaction) {
                if let uuid = address.uuid {
                    ensure(uuid: uuid, hasIdentifier: accountIdentifier, transaction: transaction)
                }
                return accountIdentifier
            }
        }

        // Nothing pre-existing, generate a new one.
        let accountIdentifier = UUID().uuidString

        if let uuid = address.uuid {
            uuidMap.setString(accountIdentifier, key: uuid.uuidString, transaction: transaction)
        }

        if let phoneNumber = address.phoneNumber {
            phoneNumberMap.setString(accountIdentifier, key: phoneNumber, transaction: transaction)
        }

        assert(address.phoneNumber != nil || address.uuid != nil)

        return accountIdentifier
    }

    private func ensure(phoneNumber: String, hasIdentifier identifier: AccountId, transaction: SDSAnyWriteTransaction) {
        guard let storedIdentifier = phoneNumberMap.getString(phoneNumber, transaction: transaction) else {
            phoneNumberMap.setString(identifier, key: phoneNumber, transaction: transaction)
            return
        }

        guard storedIdentifier == identifier else {
            owsFailDebug("mismatched identifiers")
            phoneNumberMap.setString(identifier, key: phoneNumber, transaction: transaction)
            return
        }

        return
    }

    private func ensure(uuid: UUID, hasIdentifier identifier: AccountId, transaction: SDSAnyWriteTransaction) {
        let uuidString = uuid.uuidString

        guard let storedIdentifier = uuidMap.getString(uuidString, transaction: transaction) else {
            uuidMap.setString(identifier, key: uuidString, transaction: transaction)
            return
        }

        guard storedIdentifier == identifier else {
            owsFailDebug("mismatched identifiers")
            uuidMap.setString(identifier, key: uuidString, transaction: transaction)
            return
        }

        return
    }
}
