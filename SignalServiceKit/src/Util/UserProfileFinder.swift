//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class AnyUserProfileFinder: NSObject {
    let grdbAdapter = GRDBUserProfileFinder()
    let yapdbAdapter = YAPDBSignalServiceAddressIndex()
    let yapdbUsernameAdapter = YAPDBUserProfileFinder()
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

    @objc
    func userProfile(forUsername username: String, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.userProfile(forUsername: username.lowercased(), transaction: transaction)
        case .yapRead(let transaction):
            return yapdbUsernameAdapter.userProfile(forUsername: username.lowercased(), transaction: transaction)
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

    func userProfile(forUsername username: String, transaction: GRDBReadTransaction) -> OWSUserProfile? {
        let sql = "SELECT * FROM \(UserProfileRecord.databaseTableName) WHERE \(userProfileColumn: .username) = ? LIMIT 1"
        return OWSUserProfile.grdbFetchOne(sql: sql, arguments: [username], transaction: transaction)
    }
}

@objc
public class YAPDBUserProfileFinder: NSObject {
    public static let extensionName = "index_on_username"
    private static let usernameKey = "usernameKey"

    @objc
    public static func asyncRegisterDatabaseExtensions(_ storage: OWSStorage) {
        storage.asyncRegister(extensionConfig(), withName: extensionName)
    }

    static func extensionConfig() -> YapDatabaseSecondaryIndex {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(usernameKey, with: .text)

        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock { _, dict, _, _, object in
            guard let userProfile = object as? OWSUserProfile else { return }
            dict[usernameKey] = userProfile.username
        }

        return YapDatabaseSecondaryIndex.init(setup: setup, handler: handler, versionTag: "1")
    }

    func userProfile(forUsername username: String, transaction: YapDatabaseReadTransaction) -> OWSUserProfile? {
        guard let ext = transaction.safeSecondaryIndexTransaction(YAPDBUserProfileFinder.extensionName) else {
            owsFailDebug("missing extension")
            return nil
        }

        let queryFormat = String(format: "WHERE %@ = \"%@\"", YAPDBUserProfileFinder.usernameKey, username)
        let query = YapDatabaseQuery(string: queryFormat, parameters: [])

        var matchedProfile: OWSUserProfile?

        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stop in
            guard let userProfile = object as? OWSUserProfile else {
                owsFailDebug("Unexpected object type")
                return
            }
            matchedProfile = userProfile
            stop.pointee = true
        }

        return matchedProfile
    }
}
