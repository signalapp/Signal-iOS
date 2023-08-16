//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient

@objc
public class AnyUserProfileFinder: NSObject {
    let grdbAdapter = GRDBUserProfileFinder()
}

public extension AnyUserProfileFinder {
    @objc(userProfileForAddress:transaction:)
    func userProfile(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
        return userProfiles(for: [address], tx: transaction)[0]
    }

    func userProfiles(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [OWSUserProfile?] {
        let userProfiles = grdbAdapter.userProfiles(for: addresses, transaction: tx.unwrapGrdbRead)
        userProfiles.forEach { $0?.loadBadgeContent(with: tx) }
        return userProfiles
    }

    func fetchUserProfiles(for serviceId: ServiceId, tx: SDSAnyReadTransaction) -> [OWSUserProfile] {
        let userProfiles = grdbAdapter.fetchUserProfiles(for: serviceId, tx: tx.unwrapGrdbRead)
        userProfiles.forEach { $0.loadBadgeContent(with: tx) }
        return userProfiles
    }

    func fetchUserProfiles(for phoneNumber: String, tx: SDSAnyReadTransaction) -> [OWSUserProfile] {
        let userProfiles = grdbAdapter.fetchUserProfiles(for: phoneNumber, tx: tx.unwrapGrdbRead)
        userProfiles.forEach { $0.loadBadgeContent(with: tx) }
        return userProfiles
    }

    func enumerateMissingAndStaleUserProfiles(transaction: SDSAnyReadTransaction, block: @escaping (OWSUserProfile) -> Void) {
        grdbAdapter.enumerateMissingAndStaleUserProfiles(
            transaction: transaction.unwrapGrdbRead,
            block: block
        )
    }
}

// MARK: -

@objc
class GRDBUserProfileFinder: NSObject {
    func userProfiles(for addresses: [SignalServiceAddress], transaction: GRDBReadTransaction) -> [OWSUserProfile?] {
        return Refinery<SignalServiceAddress, OWSUserProfile>(addresses).refine { addresses in
            return userProfilesForServiceIds(addresses.map { $0.serviceId }, transaction: transaction)
        }.refine { addresses in
            return userProfilesForPhoneNumbers(addresses.map { $0.phoneNumber }, transaction: transaction)
        }.values
    }

    fileprivate func fetchUserProfiles(for serviceId: ServiceId, tx: GRDBReadTransaction) -> [OWSUserProfile] {
        return userProfilesWhere(
            column: "\(userProfileColumn: .recipientUUID)",
            anyValueIn: [serviceId.serviceIdUppercaseString],
            transaction: tx
        )
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

    fileprivate func userProfilesForServiceIds(
        _ optionalServiceIds: [ServiceId?],
        transaction: GRDBReadTransaction
    ) -> [OWSUserProfile?] {
        return Refinery<ServiceId?, OWSUserProfile>(optionalServiceIds)
            .refineNonnilKeys { (serviceIds: AnySequence<ServiceId>) -> [OWSUserProfile?] in
                let profiles = userProfilesWhere(
                    column: "\(userProfileColumn: .recipientUUID)",
                    anyValueIn: Array(serviceIds.map { $0.serviceIdUppercaseString }),
                    transaction: transaction
                )

                let index = Dictionary(grouping: profiles) { $0?.recipientUUID }
                return serviceIds.map { serviceId in
                    let maybeArray = index[serviceId.serviceIdUppercaseString]
                    return maybeArray?[0]
                }
            }.values
    }

    fileprivate func userProfilesForPhoneNumbers(
        _ phoneNumbers: [String?],
        transaction: GRDBReadTransaction
    ) -> [OWSUserProfile?] {
        return Refinery<String?, OWSUserProfile>(phoneNumbers)
            .refineNonnilKeys { (phoneNumberSequence: AnySequence<String>) -> [OWSUserProfile?] in
                let profiles = userProfilesWhere(
                    column: "\(userProfileColumn: .recipientPhoneNumber)",
                    anyValueIn: Array(phoneNumberSequence),
                    transaction: transaction
                )

                let index = Dictionary(grouping: profiles) { $0?.recipientPhoneNumber }
                return phoneNumberSequence.map { phoneNumber in
                    let maybeArray = index[phoneNumber]
                    return maybeArray?[0]
                }
            }.values
    }

    func enumerateMissingAndStaleUserProfiles(
        transaction: GRDBReadTransaction,
        block: @escaping (OWSUserProfile) -> Void
    ) {
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
