//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import SignalCoreKit

@objc
public class UserProfileFinder: NSObject {
    @objc(userProfileForAddress:transaction:)
    public func userProfile(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
        return userProfiles(for: [address], tx: transaction)[0]
    }

    /// Fetches user profiles for the provided `address`.
    ///
    /// If a profile on disk matches either the `serviceId` or `phoneNumber` of
    /// `address`, it'll be returned. It's the caller's responsibility to pick
    /// the correct candidate from the provided values.
    ///
    /// Unlike `userProfiles(for:tx:)`, this method will return duplicate
    /// profiles if they exist.
    func fetchUserProfiles(matchingAnyComponentOf address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> [OWSUserProfile] {
        var userProfiles = [OWSUserProfile]()
        if let serviceId = address.serviceId {
            userProfiles.append(contentsOf: userProfilesWhere(
                column: "\(userProfileColumn: .serviceIdString)",
                anyValueIn: [serviceId.serviceIdUppercaseString],
                tx: tx
            ))
        }
        if let phoneNumber = address.phoneNumber {
            userProfiles.append(contentsOf: userProfilesWhere(
                column: "\(userProfileColumn: .phoneNumber)",
                anyValueIn: [phoneNumber],
                tx: tx
            ))
        }
        let result = userProfiles.removingDuplicates(uniquingElementsBy: \.uniqueId)
        result.forEach { $0.loadBadgeContent(tx: tx) }
        return result
    }

    func userProfiles(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [OWSUserProfile?] {
        let userProfiles = Refinery<SignalServiceAddress, OWSUserProfile>(addresses).refine { addresses in
            return userProfilesFor(serviceIds: addresses.map { $0.serviceId }, tx: tx)
        }.refine { addresses in
            return userProfilesFor(phoneNumbers: addresses.map { $0.phoneNumber }, tx: tx)
        }.values

        userProfiles.forEach { $0?.loadBadgeContent(tx: tx) }
        return userProfiles
    }

    func fetchUserProfiles(serviceId: ServiceId, tx: SDSAnyReadTransaction) -> [OWSUserProfile] {
        let userProfiles = userProfilesWhere(
            column: "\(userProfileColumn: .serviceIdString)",
            anyValueIn: [serviceId.serviceIdUppercaseString],
            tx: tx
        )

        userProfiles.forEach { $0.loadBadgeContent(tx: tx) }
        return userProfiles
    }

    func fetchUserProfiles(phoneNumber: String, tx: SDSAnyReadTransaction) -> [OWSUserProfile] {
        let userProfiles = userProfilesWhere(
            column: "\(userProfileColumn: .phoneNumber)",
            anyValueIn: [phoneNumber],
            tx: tx
        )

        userProfiles.forEach { $0.loadBadgeContent(tx: tx) }
        return userProfiles
    }

    private func userProfilesFor(
        serviceIds optionalServiceIds: [ServiceId?],
        tx: SDSAnyReadTransaction
    ) -> [OWSUserProfile?] {
        return Refinery<ServiceId?, OWSUserProfile>(optionalServiceIds)
            .refineNonnilKeys { (serviceIds: AnySequence<ServiceId>) -> [OWSUserProfile?] in
                let profiles = userProfilesWhere(
                    column: "\(userProfileColumn: .serviceIdString)",
                    anyValueIn: Array(serviceIds.map { $0.serviceIdUppercaseString }),
                    tx: tx
                )

                let index = Dictionary(grouping: profiles) { $0?.serviceIdString }
                return serviceIds.map { serviceId in
                    let maybeArray = index[serviceId.serviceIdUppercaseString]
                    return maybeArray?[0]
                }
            }.values
    }

    private func userProfilesFor(
        phoneNumbers optionalPhoneNumbers: [String?],
        tx: SDSAnyReadTransaction
    ) -> [OWSUserProfile?] {
        return Refinery<String?, OWSUserProfile>(optionalPhoneNumbers)
            .refineNonnilKeys { (phoneNumbers: AnySequence<String>) -> [OWSUserProfile?] in
                let profiles = userProfilesWhere(
                    column: "\(userProfileColumn: .phoneNumber)",
                    anyValueIn: Array(phoneNumbers),
                    tx: tx
                )

                let index = Dictionary(grouping: profiles) { $0?.phoneNumber }
                return phoneNumbers.map { phoneNumber in
                    let maybeArray = index[phoneNumber]
                    return maybeArray?[0]
                }
            }.values
    }

    private func userProfilesWhere(
        column: String,
        anyValueIn values: [String],
        tx: SDSAnyReadTransaction
    ) -> [OWSUserProfile] {
        let qms = Array(repeating: "?", count: values.count).joined(separator: ", ")
        let sql = "SELECT * FROM \(OWSUserProfile.databaseTableName) WHERE \(column) in (\(qms))"
        var userProfiles = [OWSUserProfile]()
        OWSUserProfile.anyEnumerate(transaction: tx, sql: sql, arguments: StatementArguments(values)) { userProfile, _ in
            userProfiles.append(userProfile)
        }
        return userProfiles
    }

    func fetchAcisWithSharedPhoneNumbers(tx: SDSAnyReadTransaction) throws -> [Aci] {
        let sql: String
        if OWSUserProfile.isPhoneNumberSharedByDefault {
            sql = """
                SELECT \(userProfileColumn: .serviceIdString) FROM \(OWSUserProfile.databaseTableName)
                WHERE \(userProfileColumn: .isPhoneNumberShared) IS NOT FALSE
            """
        } else {
            sql = """
                SELECT \(userProfileColumn: .serviceIdString) FROM \(OWSUserProfile.databaseTableName)
                WHERE \(userProfileColumn: .isPhoneNumberShared) IS TRUE
            """
        }
        do {
            let serviceIdStrings = try String?.fetchAll(tx.unwrapGrdbRead.database, sql: sql)
            return serviceIdStrings.compactMap(Aci.parseFrom(aciString:))
        } catch {
            throw error.grdbErrorForLogging
        }
    }
}
