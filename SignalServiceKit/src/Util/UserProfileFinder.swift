//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class AnyUserProfileFinder: NSObject {
    let grdbAdapter = GRDBUserProfileFinder()
    let yapdbAdapter = YAPDBSignalServiceAddressIndex()
}

extension AnyUserProfileFinder {
    @objc(userProfileForAddress:transaction:)
    func userProfile(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.userProfile(for: address, transaction: transaction)
        case .yapRead(let transaction):
            return yapdbAdapter.fetchOne(for: address, transaction: transaction)
        }
    }
}

@objc
class GRDBUserProfileFinder: NSObject {
    func userProfile(for address: SignalServiceAddress, transaction: GRDBReadTransaction) -> OWSUserProfile? {
        if let userProfile = userProfileForUUID(address.uuid, transaction: transaction) {
            return userProfile
        } else if let userProfile = userProfileForPhoneNumber(address.phoneNumber, transaction: transaction) {
            return userProfile
        } else {
            return nil
        }
    }

    private func userProfileForUUID(_ uuid: UUID?, transaction: GRDBReadTransaction) -> OWSUserProfile? {
        guard let uuidString = uuid?.uuidString else { return nil }
        let sql = "SELECT * FROM \(UserProfileRecord.databaseTableName) WHERE \(userProfileColumn: .recipientUUID) = ?"
        return OWSUserProfile.grdbFetchOne(sql: sql, arguments: [uuidString], transaction: transaction)
    }

    private func userProfileForPhoneNumber(_ phoneNumber: String?, transaction: GRDBReadTransaction) -> OWSUserProfile? {
        guard let phoneNumber = phoneNumber else { return nil }
        let sql = "SELECT * FROM \(UserProfileRecord.databaseTableName) WHERE \(userProfileColumn: .recipientPhoneNumber) = ?"
        return OWSUserProfile.grdbFetchOne(sql: sql, arguments: [phoneNumber], transaction: transaction)
    }
}
