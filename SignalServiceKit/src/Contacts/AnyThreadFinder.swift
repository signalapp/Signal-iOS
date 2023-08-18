//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient

@objc
public class AnyContactThreadFinder: NSObject {
    fileprivate let grdbAdapter = GRDBContactThreadFinder()
}

// MARK: -

public extension AnyContactThreadFinder {
    @objc(contactThreadForAddress:transaction:)
    func contactThread(for address: SignalServiceAddress, transaction tx: SDSAnyReadTransaction) -> TSContactThread? {
        switch tx.readTransaction {
        case .grdbRead(let tx):
            return grdbAdapter.contactThread(for: address, tx: tx)
        }
    }

    func contactThreads(for serviceId: ServiceId, tx: SDSAnyReadTransaction) -> [TSContactThread] {
        switch tx.readTransaction {
        case .grdbRead(let tx):
            return grdbAdapter.contactThreads(for: serviceId, tx: tx)
        }
    }

    func contactThreads(for phoneNumber: String, tx: SDSAnyReadTransaction) -> [TSContactThread] {
        switch tx.readTransaction {
        case .grdbRead(let tx):
            return grdbAdapter.contactThreads(for: phoneNumber, tx: tx)
        }
    }
}

// MARK: -

@objc
class GRDBContactThreadFinder: NSObject {
    func contactThread(for address: SignalServiceAddress, tx: GRDBReadTransaction) -> TSContactThread? {
        if let serviceId = address.serviceId, let thread = contactThreads(for: serviceId, tx: tx).first {
            return thread
        }
        if let phoneNumber = address.phoneNumber, let thread = contactThreads(for: phoneNumber, tx: tx).first {
            return thread
        }
        return nil
    }

    fileprivate func contactThreads(for serviceId: ServiceId, tx: GRDBReadTransaction) -> [TSContactThread] {
        let serviceIdString = serviceId.serviceIdUppercaseString
        let sql = "SELECT * FROM \(ThreadRecord.databaseTableName) WHERE \(threadColumn: .contactUUID) = ?"
        return fetchContactThreads(sql: sql, arguments: [serviceIdString], tx: tx)
    }

    fileprivate func contactThreads(for phoneNumber: String, tx: GRDBReadTransaction) -> [TSContactThread] {
        let sql = "SELECT * FROM \(ThreadRecord.databaseTableName) WHERE \(threadColumn: .contactPhoneNumber) = ?"
        return fetchContactThreads(sql: sql, arguments: [phoneNumber], tx: tx)
    }

    private func fetchContactThreads(sql: String, arguments: StatementArguments, tx: GRDBReadTransaction) -> [TSContactThread] {
        do {
            let threads = try TSContactThread.grdbFetchCursor(sql: sql, arguments: arguments, transaction: tx).all()
            return threads.compactMap { $0 as? TSContactThread }
        } catch {
            return []
        }
    }
}
