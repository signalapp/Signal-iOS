//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient

@objc
public class ContactThreadFinder: NSObject {
    @objc(contactThreadForAddress:transaction:)
    public func contactThread(for address: SignalServiceAddress, tx: DBReadTransaction) -> TSContactThread? {
        if let serviceId = address.serviceId, let thread = contactThreads(for: serviceId, tx: tx).first {
            return thread
        }
        if let phoneNumber = address.phoneNumber, let thread = contactThreads(for: phoneNumber, tx: tx).first {
            return thread
        }
        return nil
    }

    func contactThreads(for serviceId: ServiceId, tx: DBReadTransaction) -> [TSContactThread] {
        let serviceIdString = serviceId.serviceIdUppercaseString
        let sql = "SELECT * FROM \(TSThread.databaseTableName) WHERE \(contactThreadColumn: .contactUUID) = ?"
        return fetchContactThreads(sql: sql, arguments: [serviceIdString], tx: tx)
    }

    func contactThreads(for phoneNumber: String, tx: DBReadTransaction) -> [TSContactThread] {
        let sql = "SELECT * FROM \(TSThread.databaseTableName) WHERE \(contactThreadColumn: .contactPhoneNumber) = ?"
        return fetchContactThreads(sql: sql, arguments: [phoneNumber], tx: tx)
    }

    private func fetchContactThreads(sql: String, arguments: StatementArguments, tx: DBReadTransaction) -> [TSContactThread] {
        var threads = [TSThread]()
        TSThread.anyEnumerate(
            transaction: tx,
            sql: sql,
            arguments: arguments,
            block: { thread, _ in threads.append(thread) },
        )
        return threads.compactMap { $0 as? TSContactThread }
    }
}
