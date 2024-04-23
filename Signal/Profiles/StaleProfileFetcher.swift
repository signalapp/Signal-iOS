//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient
import SignalServiceKit

class StaleProfileFetcher {
    private let db: any DB
    private let profileFetcher: any ProfileFetcher
    private let tsAccountManager: any TSAccountManager

    init(
        db: any DB,
        profileFetcher: any ProfileFetcher,
        tsAccountManager: any TSAccountManager
    ) {
        self.db = db
        self.profileFetcher = profileFetcher
        self.tsAccountManager = tsAccountManager
    }

    func scheduleProfileFetches() {
        let staleServiceIds = db.read { tx -> [ServiceId] in
            guard tsAccountManager.registrationState(tx: tx).isRegistered else {
                return []
            }
            var staleServiceIds = [ServiceId]()
            Self.enumerateMissingAndStaleUserProfiles(now: Date(), tx: SDSDB.shimOnlyBridge(tx)) { userProfile in
                switch userProfile.internalAddress {
                case .localUser:
                    // Ignore the local user.
                    return
                case .otherUser(let address):
                    if let serviceId = address.serviceId {
                        staleServiceIds.append(serviceId)
                    }
                }
            }
            return staleServiceIds
        }
        Task { [profileFetcher] in
            for serviceId in staleServiceIds.shuffled() {
                _ = try? await profileFetcher.fetchProfile(for: serviceId, options: [.opportunistic])
            }
        }
    }

    static func enumerateMissingAndStaleUserProfiles(now: Date, tx: SDSAnyReadTransaction, block: (OWSUserProfile) -> Void) {
        // We are only interested in active users, e.g. users which the local user
        // has sent or received a message from in the last N days.
        let activeTimestamp = now.timeIntervalSince1970 - 30*kDayInterval

        // We are only interested in stale profiles, e.g. profiles that have never
        // been fetched or haven't been fetched in the last N days.
        let staleTimestamp = now.timeIntervalSince1970 - 1*kDayInterval

        // TODO: Skip if no profile key?

        // SQLite treats NULL as less than any other value for the purposes of
        // ordering, so:
        //
        // * ".lastFetchDate ASC" will correct order rows without .lastFetchDate
        // first.
        //
        // But SQLite date comparison clauses will be false if a date is NULL, so:
        //
        // * ".lastMessagingDate > activeTimestamp" will correctly filter out rows
        // without .lastMessagingDate.
        //
        // * ".lastFetchDate < staleTimestamp" will _NOT_ correctly include rows
        // without .lastFetchDate; we need to explicitly test for NULL.
        let sql = """
        SELECT *
        FROM \(OWSUserProfile.databaseTableName)
        WHERE \(userProfileColumn: .lastMessagingDate) > ?
        AND (
            \(userProfileColumn: .lastFetchDate) < ? OR
            \(userProfileColumn: .lastFetchDate) IS NULL
        )
        ORDER BY \(userProfileColumn: .lastFetchDate) ASC
        LIMIT 25
        """
        let arguments: StatementArguments = [activeTimestamp, staleTimestamp]
        OWSUserProfile.anyEnumerate(transaction: tx, sql: sql, arguments: arguments) { userProfile, _ in
            block(userProfile)
        }
    }
}
