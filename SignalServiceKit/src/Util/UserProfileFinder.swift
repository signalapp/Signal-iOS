//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

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

    @objc(userProfileForUUID:transaction:)
    func userProfileForUUID(_ uuid: UUID, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.userProfileForUUID(uuid, transaction: transaction)
        case .yapRead:
            owsFailDebug("Invalid transaction.")
            return nil
        }
    }

    @objc(userProfileForPhoneNumber:transaction:)
    func userProfileForPhoneNumber(_ phoneNumber: String, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.userProfileForPhoneNumber(phoneNumber, transaction: transaction)
        case .yapRead:
            owsFailDebug("Invalid transaction.")
            return nil
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

    @objc
    func enumerateMissingAndStaleUserProfiles(transaction: SDSAnyReadTransaction, block: @escaping (OWSUserProfile) -> Void) {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            grdbAdapter.enumerateMissingAndStaleUserProfiles(transaction: transaction, block: block)
        case .yapRead:
            owsFail("Invalid database.")
        }
    }
}

// MARK: -

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

    fileprivate func userProfileForUUID(_ uuid: UUID?, transaction: GRDBReadTransaction) -> OWSUserProfile? {
        guard let uuidString = uuid?.uuidString else { return nil }
        let sql = "SELECT * FROM \(UserProfileRecord.databaseTableName) WHERE \(userProfileColumn: .recipientUUID) = ?"
        return OWSUserProfile.grdbFetchOne(sql: sql, arguments: [uuidString], transaction: transaction)
    }

    fileprivate func userProfileForPhoneNumber(_ phoneNumber: String?, transaction: GRDBReadTransaction) -> OWSUserProfile? {
        guard let phoneNumber = phoneNumber else { return nil }
        let sql = "SELECT * FROM \(UserProfileRecord.databaseTableName) WHERE \(userProfileColumn: .recipientPhoneNumber) = ?"
        return OWSUserProfile.grdbFetchOne(sql: sql, arguments: [phoneNumber], transaction: transaction)
    }

    func userProfile(forUsername username: String, transaction: GRDBReadTransaction) -> OWSUserProfile? {
        let sql = "SELECT * FROM \(UserProfileRecord.databaseTableName) WHERE \(userProfileColumn: .username) = ? LIMIT 1"
        return OWSUserProfile.grdbFetchOne(sql: sql, arguments: [username], transaction: transaction)
    }

    func enumerateMissingAndStaleUserProfiles(transaction: GRDBReadTransaction, block: @escaping (OWSUserProfile) -> Void) {
        // We are only interested in active users, e.g. users
        // which the local user has sent or received a message
        // from in the last N days.
        let activeTimestamp = NSDate.ows_millisecondTimeStamp() - (30 * kDayInMs)
        let activeDate = NSDate.ows_date(withMillisecondsSince1970: activeTimestamp)

        // We are only interested in stale profiles, e.g. profiles
        // that have never been fetched or haven't been fetched
        // in the last N days.
        let staleTimestamp = NSDate.ows_millisecondTimeStamp() - (1 * kDayInMs)
        let staleDate = NSDate.ows_date(withMillisecondsSince1970: staleTimestamp)

        // TODO: Skip if no profile key?

        // SQLite treats NULL as less than any other value for the purposes of ordering, so:
        //
        // * ".lastFetchDate ASC" will correct order rows without .lastFetchDate first.
        //
        // But SQLite date comparison clauses will be false if a date is NULL, so:
        //
        // * ".lastMessagingDate > activeDate" will correctly filter out rows without .lastMessagingDate.
        // * ".lastFetchDate < staleDate" will _NOT_ correctly include rows without .lastFetchDate;
        //   we need to explicitly test for NULL.
        let sql = """
        SELECT *
        FROM \(UserProfileRecord.databaseTableName)
        WHERE \(userProfileColumn: .lastMessagingDate) > ?
        AND (
        \(userProfileColumn: .lastFetchDate) < ? OR
        \(userProfileColumn: .lastFetchDate) IS NULL
        )
        ORDER BY \(userProfileColumn: .lastFetchDate) ASC
        LIMIT 50
        """
        let arguments: StatementArguments = [convertDateForGrdb(activeDate), convertDateForGrdb(staleDate)]
        let cursor = OWSUserProfile.grdbFetchCursor(sql: sql, arguments: arguments, transaction: transaction)

        do {
            while let userProfile = try cursor.next() {
                block(userProfile)
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }
    }
}

// MARK: -

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
