//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import LibSignalClient

struct SessionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "Session"

    let id: Int64
    var recipientId: SignalRecipient.RowId
    let localIdentity: OWSIdentity
    let deviceId: DeviceId
    /// May be nil if there was a legacy session.
    var serializedRecord: Data?

    enum CodingKeys: String, CodingKey {
        case id
        case recipientId
        case localIdentity
        case deviceId
        case serializedRecord
    }

    enum Columns {
        static let recipientId = Column(CodingKeys.recipientId.rawValue)
        static let localIdentity = Column(CodingKeys.localIdentity.rawValue)
        static let deviceId = Column(CodingKeys.deviceId.rawValue)
        static let serializedRecord = Column(CodingKeys.serializedRecord.rawValue)
    }
}

struct SessionStore {
    func hasSessionRecords(
        forRecipientId recipientId: SignalRecipient.RowId,
        localIdentity: OWSIdentity,
        tx: DBReadTransaction,
    ) -> Bool {
        let sessionRecords = fetchSessionRecords(
            forRecipientId: recipientId,
            localIdentity: localIdentity,
            tx: tx,
        )
        return !sessionRecords.isEmpty
    }

    func mergeRecipientId(
        _ recipientId: SignalRecipient.RowId,
        into targetRecipientId: SignalRecipient.RowId,
        localIdentity: OWSIdentity,
        tx: DBWriteTransaction,
    ) {
        if hasSessionRecords(forRecipientId: targetRecipientId, localIdentity: localIdentity, tx: tx) {
            // There's already sessions -- prefers those instead of ours.
            deleteSessions(forRecipientId: recipientId, localIdentity: localIdentity, tx: tx)
        } else {
            // There's no sessions -- move ours and reuse them.
            let sessionRecords = fetchSessionRecords(
                forRecipientId: recipientId,
                localIdentity: localIdentity,
                tx: tx,
            )
            for var sessionRecord in sessionRecords {
                sessionRecord.recipientId = targetRecipientId
                failIfThrows { try sessionRecord.update(tx.database) }
            }
        }
    }

    private func buildQuery(
        recipientId: SignalRecipient.RowId,
        localIdentity: OWSIdentity,
        deviceId: DeviceId? = nil,
    ) -> QueryInterfaceRequest<SessionRecord> {
        var result = SessionRecord.filter(SessionRecord.Columns.recipientId == recipientId)
        result = result.filter(SessionRecord.Columns.localIdentity == localIdentity.rawValue)
        if let deviceId {
            result = result.filter(SessionRecord.Columns.deviceId == deviceId.rawValue)
        }
        return result
    }

    private func fetchSessionRecords(
        forRecipientId recipientId: SignalRecipient.RowId,
        localIdentity: OWSIdentity,
        deviceId: DeviceId? = nil,
        tx: DBReadTransaction,
    ) -> [SessionRecord] {
        return failIfThrows {
            return try buildQuery(
                recipientId: recipientId,
                localIdentity: localIdentity,
                deviceId: deviceId,
            ).fetchAll(tx.database)
        }
    }

    func fetchSession(
        forRecipientId recipientId: SignalRecipient.RowId,
        localIdentity: OWSIdentity,
        deviceId: DeviceId,
        tx: DBReadTransaction,
    ) throws -> LibSignalClient.SessionRecord? {
        return try (fetchSessionRecords(
            forRecipientId: recipientId,
            localIdentity: localIdentity,
            deviceId: deviceId,
            tx: tx,
        ).first?.serializedRecord).map(LibSignalClient.SessionRecord.init(bytes:))
    }

    func archiveSessions(
        forRecipientId recipientId: SignalRecipient.RowId,
        localIdentity: OWSIdentity,
        tx: DBWriteTransaction,
    ) {
        _archiveSessions(forRecipientId: recipientId, localIdentity: localIdentity, deviceId: nil, tx: tx)
    }

    fileprivate func _archiveSessions(
        forRecipientId recipientId: SignalRecipient.RowId,
        localIdentity: OWSIdentity,
        deviceId: DeviceId?,
        tx: DBWriteTransaction,
    ) {
        let sessionRecords = fetchSessionRecords(
            forRecipientId: recipientId,
            localIdentity: localIdentity,
            deviceId: deviceId,
            tx: tx,
        )
        for var sessionRecord in sessionRecords {
            guard let serializedRecord = sessionRecord.serializedRecord else {
                Logger.warn("couldn't decode legacy session to archive it; leaving it as-is")
                continue
            }
            let libSignalSessionRecord: LibSignalClient.SessionRecord
            do {
                libSignalSessionRecord = try LibSignalClient.SessionRecord(bytes: serializedRecord)
            } catch {
                owsFailDebug("couldn't decode session to archive it: \(error)")
                continue
            }
            libSignalSessionRecord.archiveCurrentState()
            sessionRecord.serializedRecord = libSignalSessionRecord.serialize()
            failIfThrows { try sessionRecord.update(tx.database) }
        }
    }

    func deleteSessions(
        forRecipientId recipientId: SignalRecipient.RowId,
        localIdentity: OWSIdentity,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            _ = try buildQuery(
                recipientId: recipientId,
                localIdentity: localIdentity,
                deviceId: nil,
            ).deleteAll(tx.database)
        }
    }

    func upsertSession(
        forRecipientId recipientId: SignalRecipient.RowId,
        deviceId: DeviceId,
        localIdentity: OWSIdentity,
        recordData: Data,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try tx.database.execute(
                sql: """
                INSERT OR REPLACE INTO \(SessionRecord.databaseTableName) (
                    \(SessionRecord.Columns.recipientId.name),
                    \(SessionRecord.Columns.deviceId.name),
                    \(SessionRecord.Columns.localIdentity.name),
                    \(SessionRecord.Columns.serializedRecord.name)
                ) VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    recipientId,
                    deviceId.rawValue,
                    localIdentity.rawValue,
                    recordData,
                ],
            )
        }
    }

    func deleteAllSessions(tx: DBWriteTransaction) {
        failIfThrows { _ = try SessionRecord.deleteAll(tx.database) }
    }
}

public class SessionManagerForIdentity: LibSignalClient.SessionStore {
    private let identity: OWSIdentity
    private let recipientIdFinder: RecipientIdFinder
    private let sessionStore: SessionStore

    init(
        identity: OWSIdentity,
        recipientIdFinder: RecipientIdFinder,
        sessionStore: SessionStore,
    ) {
        self.identity = identity
        self.recipientIdFinder = recipientIdFinder
        self.sessionStore = sessionStore
    }

    func archiveSession(forServiceId serviceId: ServiceId, deviceId: DeviceId, tx: DBWriteTransaction) {
        Logger.info("archiving session for \(serviceId).\(deviceId)")
        self._archiveSessions(
            recipientIdResult: self.recipientIdFinder.recipientId(for: serviceId, tx: tx),
            deviceId: deviceId,
            tx: tx,
        )
    }

    public func archiveSessions(forServiceId serviceId: ServiceId, tx: DBWriteTransaction) {
        Logger.info("archiving all sessions for \(serviceId)")
        self._archiveSessions(
            recipientIdResult: self.recipientIdFinder.recipientId(for: serviceId, tx: tx),
            deviceId: nil,
            tx: tx,
        )
    }

    func archiveSessions(forAddress address: SignalServiceAddress, tx: DBWriteTransaction) {
        Logger.info("archiving all sessions for \(address)")
        self._archiveSessions(
            recipientIdResult: self.recipientIdFinder.recipientId(for: address, tx: tx),
            deviceId: nil,
            tx: tx,
        )
    }

    private func _archiveSessions(
        recipientIdResult: Result<SignalRecipient.RowId, RecipientIdError>?,
        deviceId: DeviceId?,
        tx: DBWriteTransaction,
    ) {
        switch recipientIdResult {
        case .none, .some(.failure(.mustNotUsePniBecauseAciExists)):
            // There can't possibly be any sessions that need to be archived.
            return
        case .some(.success(let recipientId)):
            self.sessionStore._archiveSessions(
                forRecipientId: recipientId,
                localIdentity: self.identity,
                deviceId: deviceId,
                tx: tx,
            )
        }
    }

    public func deleteSessions(forServiceId serviceId: ServiceId, tx: DBWriteTransaction) {
        switch self.recipientIdFinder.recipientId(for: serviceId, tx: tx) {
        case .none, .some(.failure(.mustNotUsePniBecauseAciExists)):
            // There can't possibly be any sessions that need to be deleted.
            return
        case .some(.success(let recipientId)):
            self.sessionStore.deleteSessions(forRecipientId: recipientId, localIdentity: self.identity, tx: tx)
        }
    }

    func loadSession(
        forServiceId serviceId: ServiceId,
        deviceId: DeviceId,
        tx: DBReadTransaction,
    ) throws -> LibSignalClient.SessionRecord? {
        switch self.recipientIdFinder.recipientId(for: serviceId, tx: tx) {
        case .none:
            return nil
        case .some(.success(let recipientId)):
            return try self.sessionStore.fetchSession(
                forRecipientId: recipientId,
                localIdentity: self.identity,
                deviceId: deviceId,
                tx: tx,
            )
        case .some(.failure(let error)):
            switch error {
            case .mustNotUsePniBecauseAciExists:
                throw error
            }
        }
    }

    public func loadSession(
        for address: LibSignalClient.ProtocolAddress,
        context: any LibSignalClient.StoreContext,
    ) throws -> LibSignalClient.SessionRecord? {
        return try loadSession(
            forServiceId: address.serviceId,
            deviceId: address.deviceIdObj,
            tx: context.asTransaction,
        )
    }

    public func loadExistingSessions(
        for addresses: [LibSignalClient.ProtocolAddress],
        context: any LibSignalClient.StoreContext,
    ) throws -> [LibSignalClient.SessionRecord] {
        return try addresses.map { address in
            guard let session = try loadSession(for: address, context: context) else {
                throw SignalError.sessionNotFound("\(address)")
            }
            return session
        }
    }

    public func storeSession(
        _ record: LibSignalClient.SessionRecord,
        for address: LibSignalClient.ProtocolAddress,
        context: any LibSignalClient.StoreContext,
    ) throws {
        switch recipientIdFinder.ensureRecipientId(for: address.serviceId, tx: context.asTransaction) {
        case .success(let recipientId):
            self.sessionStore.upsertSession(
                forRecipientId: recipientId,
                deviceId: address.deviceIdObj,
                localIdentity: self.identity,
                recordData: record.serialize(),
                tx: context.asTransaction,
            )
        case .failure(let error):
            switch error {
            case .mustNotUsePniBecauseAciExists:
                throw error
            }
        }
    }
}
