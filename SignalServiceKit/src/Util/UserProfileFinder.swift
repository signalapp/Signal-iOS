//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

@objc
public class AnyUserProfileFinder: NSObject {
    let grdbAdapter = GRDBUserProfileFinder()
}

public extension AnyUserProfileFinder {
    @objc(userProfileForAddress:transaction:)
    func userProfile(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
        return userProfiles(for: [address], transaction: transaction)[0]
    }

    @objc(userProfileForUUID:transaction:)
    func userProfileForUUID(_ uuid: UUID, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
        let profile: OWSUserProfile?
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            profile = grdbAdapter.userProfileForUUID(uuid, transaction: transaction)
        }
        profile?.loadBadgeContent(with: transaction)
        return profile
    }

    func fetchUserProfiles(for serviceId: UntypedServiceId, tx: SDSAnyReadTransaction) -> [OWSUserProfile] {
        let userProfiles = grdbAdapter.fetchUserProfiles(for: serviceId, tx: tx.unwrapGrdbRead)
        userProfiles.forEach { $0.loadBadgeContent(with: tx) }
        return userProfiles
    }

    @objc(userProfileForPhoneNumber:transaction:)
    func userProfileForPhoneNumber(_ phoneNumber: String, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
        let profile: OWSUserProfile?
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            profile = grdbAdapter.userProfileForPhoneNumber(phoneNumber, transaction: transaction)
        }
        profile?.loadBadgeContent(with: transaction)
        return profile
    }

    func fetchUserProfiles(for phoneNumber: String, tx: SDSAnyReadTransaction) -> [OWSUserProfile] {
        let userProfiles = grdbAdapter.fetchUserProfiles(for: phoneNumber, tx: tx.unwrapGrdbRead)
        userProfiles.forEach { $0.loadBadgeContent(with: tx) }
        return userProfiles
    }

    @objc
    func enumerateMissingAndStaleUserProfiles(transaction: SDSAnyReadTransaction, block: @escaping (OWSUserProfile) -> Void) {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            grdbAdapter.enumerateMissingAndStaleUserProfiles(transaction: transaction, block: block)
        }
    }

    func userProfiles(for addresses: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> [OWSUserProfile?] {
        let profiles: [OWSUserProfile?]
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            profiles = grdbAdapter.userProfiles(for: addresses, transaction: transaction)
        }
        for profile in profiles {
            profile?.loadBadgeContent(with: transaction)
        }
        return profiles
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

    func userProfiles(for addresses: [SignalServiceAddress], transaction: GRDBReadTransaction) -> [OWSUserProfile?] {
        return Refinery<SignalServiceAddress, OWSUserProfile>(addresses).refine { addresses in
            return userProfilesForUUIDs(addresses.map { $0.uuid }, transaction: transaction)
        }.refine { addresses in
            return userProfilesForPhoneNumbers(addresses.map { $0.phoneNumber }, transaction: transaction)
        }.values
    }

    fileprivate func userProfileForUUID(_ uuid: UUID?, transaction: GRDBReadTransaction) -> OWSUserProfile? {
        return userProfilesForUUIDs([uuid], transaction: transaction)[0]
    }

    fileprivate func fetchUserProfiles(for serviceId: UntypedServiceId, tx: GRDBReadTransaction) -> [OWSUserProfile] {
        return userProfilesWhere(
            column: "\(userProfileColumn: .recipientUUID)",
            anyValueIn: [serviceId.uuidValue.uuidString],
            transaction: tx
        )
    }

    fileprivate func userProfileForPhoneNumber(_ phoneNumber: String?, transaction: GRDBReadTransaction) -> OWSUserProfile? {
        return userProfilesForPhoneNumbers([phoneNumber], transaction: transaction)[0]
    }

    fileprivate func fetchUserProfiles(for phoneNumber: String, tx: GRDBReadTransaction) -> [OWSUserProfile] {
        return userProfilesWhere(
            column: "\(userProfileColumn: .recipientPhoneNumber)",
            anyValueIn: [phoneNumber],
            transaction: tx
        )
    }

    private func userProfilesWhere(column: String, anyValueIn values: [String], transaction: GRDBReadTransaction) -> [OWSUserProfile] {
        let qms = Array(repeating: "?", count: values.count).joined(separator: ", ")
        let sql = "SELECT * FROM \(UserProfileRecord.databaseTableName) WHERE \(column) in (\(qms))"
        do {
            return try OWSUserProfile.grdbFetchCursor(sql: sql,
                                                      arguments: StatementArguments(values),
                                                      transaction: transaction).all()
        } catch {
            owsFailDebug("Error fetching profiles where \(column) in \(values): \(error)")
            return []
        }
    }

    fileprivate func userProfilesForUUIDs(_ optionalUUIDs: [UUID?], transaction: GRDBReadTransaction) -> [OWSUserProfile?] {
        return Refinery<UUID?, OWSUserProfile>(optionalUUIDs).refineNonnilKeys { (uuidSequence: AnySequence<UUID>) -> [OWSUserProfile?] in
            let profiles = userProfilesWhere(column: "\(userProfileColumn: .recipientUUID)",
                                             anyValueIn: Array(uuidSequence.map { $0.uuidString }),
                                             transaction: transaction)
            let index = Dictionary(grouping: profiles) { $0?.recipientUUID }
            return uuidSequence.map { uuid in
                let maybeArray = index[uuid.uuidString]
                return maybeArray?[0]
            }
        }.values
    }

    fileprivate func userProfilesForPhoneNumbers(_ phoneNumbers: [String?], transaction: GRDBReadTransaction) -> [OWSUserProfile?] {
        return Refinery<String?, OWSUserProfile>(phoneNumbers).refineNonnilKeys { (phoneNumberSequence: AnySequence<String>) -> [OWSUserProfile?] in
            let profiles = userProfilesWhere(column: "\(userProfileColumn: .recipientPhoneNumber)",
                                             anyValueIn: Array(phoneNumberSequence),
                                             transaction: transaction)
            let index = Dictionary(grouping: profiles) { $0?.recipientPhoneNumber }
            return phoneNumberSequence.map { phoneNumber in
                let maybeArray = index[phoneNumber]
                return maybeArray?[0]
            }
        }.values
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
