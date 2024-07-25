//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient

@objc
public class UserProfileFinder: NSObject {
    public func userProfile(for address: OWSUserProfile.Address, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
        return userProfiles(for: [address], tx: transaction)[0]
    }

    func userProfiles(for addresses: [OWSUserProfile.Address], tx: SDSAnyReadTransaction) -> [OWSUserProfile?] {
        let userProfiles = Refinery<OWSUserProfile.Address, OWSUserProfile>(addresses).refine { addresses in
            let serviceIds = addresses.map { address -> ServiceId? in
                switch address {
                case .localUser:
                    return nil
                case .otherUser(let address):
                    return address.serviceId
                }
            }
            return userProfilesFor(serviceIds: serviceIds, tx: tx)
        }.refine { addresses in
            let phoneNumbers = addresses.map { address -> String? in
                switch address {
                case .localUser:
                    return OWSUserProfile.Constants.localProfilePhoneNumber
                case .otherUser(let address):
                    return address.phoneNumber
                }
            }
            return userProfilesFor(phoneNumbers: phoneNumbers, tx: tx)
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

    func fetchAcisWithHiddenPhoneNumbers(tx: SDSAnyReadTransaction) throws -> [Aci] {
        let sql = """
        SELECT \(userProfileColumn: .serviceIdString) FROM \(OWSUserProfile.databaseTableName)
        WHERE \(userProfileColumn: .isPhoneNumberShared) IS FALSE
        OR (\(userProfileColumn: .isPhoneNumberShared) IS NULL AND \(userProfileColumn: .givenName) IS NOT NULL)
        """
        do {
            let serviceIdStrings = try String?.fetchAll(tx.unwrapGrdbRead.database, sql: sql)
            return serviceIdStrings.compactMap(Aci.parseFrom(aciString:))
        } catch {
            throw error.grdbErrorForLogging
        }
    }
}
