//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient

/// In charge of fetching avatars for groups as well as avatars and updated profiles
/// for contacts we restore from a backup.
public class MessageBackupAvatarFetcher {

    private let appReadiness: AppReadiness
    private let taskQueue: TaskQueueLoader<TaskRunner>
    private let tsAccountManager: TSAccountManager

    public init(
        appReadiness: AppReadiness,
        db: any DB,
        groupsV2: GroupsV2,
        profileFetcher: ProfileFetcher,
        threadStore: ThreadStore,
        tsAccountManager: TSAccountManager
    ) {
        self.appReadiness = appReadiness
        self.tsAccountManager = tsAccountManager
        self.taskQueue = TaskQueueLoader(
            maxConcurrentTasks: 3,
            db: db,
            runner: TaskRunner(
                db: db,
                groupsV2: groupsV2,
                profileFetcher: profileFetcher,
                threadStore: threadStore,
                tsAccountManager: tsAccountManager
            )
        )
        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            Task { [weak self] in
                try await self?.runIfNeeded()
            }
            self?.startObserving()
        }
    }

    internal func enqueueFetchOfGroupAvatar(_ thread: TSGroupThread, tx: DBWriteTransaction) throws {
        guard let avatarUrl = (thread.groupModel as? TSGroupModelV2)?.avatarUrlPath else {
            return
        }
        var record = Record.forGroupAvatar(groupThread: thread, avatarUrl: avatarUrl)
        try record?.insert(tx.databaseConnection)
    }

    internal func enqueueFetchOfUserProfile(serviceId: ServiceId, tx: DBWriteTransaction) throws {
        var record = Record.forUserProfile(serviceId: serviceId)
        try record.insert(tx.databaseConnection)
    }

    public func runIfNeeded() async throws {
        guard FeatureFlags.messageBackupFileAlpha || FeatureFlags.linkAndSyncSecondary else {
            return
        }
        guard appReadiness.isAppReady else {
            return
        }
        guard tsAccountManager.localIdentifiersWithMaybeSneakyTransaction != nil else {
            return
        }

        try await taskQueue.loadAndRunTasks()
    }

    private func startObserving() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didUpdateRegistrationState),
            name: .registrationStateDidChange,
            object: nil
        )
    }

    @objc
    private func didUpdateRegistrationState() {
        Task {
            try await runIfNeeded()
        }
    }

    // MARK: - TaskRunner

    private final class TaskRunner: TaskRecordRunner {
        let db: any DB
        let groupsV2: GroupsV2
        let profileFetcher: ProfileFetcher
        let store: TaskStore
        let threadStore: ThreadStore
        let tsAccountManager: TSAccountManager

        init(
            db: any DB,
            groupsV2: GroupsV2,
            profileFetcher: ProfileFetcher,
            threadStore: ThreadStore,
            tsAccountManager: TSAccountManager
        ) {
            self.db = db
            self.groupsV2 = groupsV2
            self.profileFetcher = profileFetcher
            self.store = TaskStore()
            self.threadStore = threadStore
            self.tsAccountManager = tsAccountManager
        }

        func runTask(
            record: Record,
            loader: TaskQueueLoader<TaskRunner>
        ) async -> TaskRecordResult {
            guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
                try? await loader.stop()
                return .cancelled
            }

            if let serviceId = record.serviceId {
                do {
                    _ = try await profileFetcher.fetchProfileImpl(
                        for: serviceId,
                        options: .opportunistic,
                        authedAccount: .implicit()
                    )
                    return .success
                } catch {
                    // Don't bother retrying; we'll fetch profiles
                    // throughout the app.
                    return .unretryableError(error)
                }
            } else if let threadRowId = record.groupThreadRowId {
                let thread = db.read { threadStore.fetchThread(rowId: threadRowId, tx: $0) }
                guard
                    let groupThread = thread as? TSGroupThread,
                    let groupModel = groupThread.groupModel as? TSGroupModelV2,
                    let avatarUrlPath = groupModel.avatarUrlPath
                else {
                    return .cancelled
                }

                // Ensure we haven't since updated the group pointing to a new avatar.
                guard avatarUrlPath == record.groupAvatarUrl else {
                    return .cancelled
                }

                do {
                    let avatarData = try await groupsV2.fetchGroupAvatarRestoredFromBackup(
                        groupModel: groupModel,
                        avatarUrlPath: avatarUrlPath
                    )
                    try groupModel.persistAvatarData(avatarData)
                    let avatarHash = groupModel.avatarHash
                    await db.awaitableWrite { tx in
                        // Refetch the group thread and apply again.
                        guard
                            let refetchedGroupThread = threadStore.fetchThread(rowId: threadRowId, tx: tx) as? TSGroupThread,
                            let refetchedGroupModel = refetchedGroupThread.groupModel as? TSGroupModelV2,
                            refetchedGroupModel.avatarUrlPath == record.groupAvatarUrl
                        else {
                            return
                        }
                        refetchedGroupModel.avatarHash = avatarHash
                        threadStore.update(
                            groupThread: refetchedGroupThread,
                            with: refetchedGroupModel,
                            tx: tx
                        )
                    }
                    return .success
                } catch {
                    // Don't bother retrying; we'll eventually fetch a group
                    // snapshot and get the avatar.
                    return .unretryableError(error)
                }
            } else {
                return .cancelled
            }
        }

        func didSucceed(record: Record, tx: DBWriteTransaction) throws {}
        func didFail(record: Record, error: any Error, isRetryable: Bool, tx: DBWriteTransaction) throws {}
        func didCancel(record: Record, tx: DBWriteTransaction) throws {}
    }

    // MARK: - TaskStore

    private class TaskStore: TaskRecordStore {
        typealias Record = MessageBackupAvatarFetcher.Record

        init() {}

        func peek(count: UInt, tx: DBReadTransaction) throws -> [Record] {
            return try Record
                .limit(Int(count))
                .fetchAll(tx.databaseConnection)
        }

        func removeRecord(_ record: Record, tx: DBWriteTransaction) throws {
            try record.delete(tx.databaseConnection)
        }
    }

    // MARK: - Record

    private struct Record: Codable, FetchableRecord, MutablePersistableRecord, TaskRecord {
        typealias IDType = Int64

        var id: IDType { _id! }

        private(set) var _id: IDType?

        // Either both of these are set (for restoring group avatars)
        let groupThreadRowId: Int64?
        let groupAvatarUrl: String?

        // Or this is set (for fetching the profile for a user)
        let serviceId: ServiceId?

        private init(groupThreadRowId: Int64?, groupAvatarUrl: String?, serviceId: ServiceId?) {
            self._id = nil
            self.groupThreadRowId = groupThreadRowId
            self.groupAvatarUrl = groupAvatarUrl
            self.serviceId = serviceId
        }

        static func forGroupAvatar(groupThread: TSGroupThread, avatarUrl: String) -> Self? {
            guard let rowId = groupThread.sqliteRowId else { return nil }
            return .init(groupThreadRowId: rowId, groupAvatarUrl: avatarUrl, serviceId: nil)
        }

        static func forUserProfile(serviceId: ServiceId) -> Self {
            return .init(groupThreadRowId: nil, groupAvatarUrl: nil, serviceId: serviceId)
        }

        // MARK: FetchableRecord

        static var databaseTableName: String { "MessageBackupAvatarFetchQueue" }

        // MARK: MutablePersistableRecord

        mutating func didInsert(with rowID: Int64, for column: String?) {
            self._id = rowID
        }

        // MARK: Codable

        enum CodingKeys: String, CodingKey {
            case id
            case groupThreadRowId
            case groupAvatarUrl
            case serviceId
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self._id = try container.decode(Int64.self, forKey: .id)
            self.groupThreadRowId = try container.decodeIfPresent(Int64.self, forKey: .groupThreadRowId)
            self.groupAvatarUrl = try container.decodeIfPresent(String.self, forKey: .groupAvatarUrl)
            self.serviceId = try container
                .decodeIfPresent(Data.self, forKey: .serviceId)
                .map(ServiceId.parseFrom(serviceIdBinary:))
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(_id, forKey: .id)
            try container.encodeIfPresent(groupThreadRowId, forKey: .groupThreadRowId)
            try container.encodeIfPresent(groupAvatarUrl, forKey: .groupAvatarUrl)
            try container.encodeIfPresent(serviceId?.serviceIdBinary.asData, forKey: .serviceId)
        }
    }
}
