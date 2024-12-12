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
    private let db: any DB
    private let reachabilityManager: SSKReachabilityManager
    private let store: TaskStore
    private let taskQueue: TaskQueueLoader<TaskRunner>
    private let tsAccountManager: TSAccountManager

    public init(
        appReadiness: AppReadiness,
        dateProvider: @escaping DateProvider,
        db: any DB,
        groupsV2: GroupsV2,
        profileFetcher: ProfileFetcher,
        reachabilityManager: SSKReachabilityManager,
        threadStore: ThreadStore,
        tsAccountManager: TSAccountManager
    ) {
        self.appReadiness = appReadiness
        self.db = db
        self.reachabilityManager = reachabilityManager
        self.tsAccountManager = tsAccountManager
        let store = TaskStore()
        self.store = store
        self.taskQueue = TaskQueueLoader(
            maxConcurrentTasks: 3,
            dateProvider: dateProvider,
            db: db,
            runner: TaskRunner(
                dateProvider: dateProvider,
                db: db,
                groupsV2: groupsV2,
                profileFetcher: profileFetcher,
                reachabilityManager: reachabilityManager,
                store: store,
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

    internal func enqueueFetchOfGroupAvatar(
        _ thread: TSGroupThread,
        currentTimestamp: UInt64,
        lastVisibleInteractionRowIdInGroupThread: Int64?,
        tx: DBWriteTransaction
    ) throws {
        guard let avatarUrl = (thread.groupModel as? TSGroupModelV2)?.avatarUrlPath else {
            return
        }
        var record = Record.forGroupAvatar(
            groupThread: thread,
            avatarUrl: avatarUrl,
            currentTimestamp: currentTimestamp,
            lastVisibleInteractionRowIdInGroupThread: lastVisibleInteractionRowIdInGroupThread
        )
        try record?.insert(tx.databaseConnection)
    }

    internal func enqueueFetchOfUserProfile(
        serviceId: ServiceId,
        currentTimestamp: UInt64,
        lastVisibleInteractionRowIdInContactThread: Int64?,
        tx: DBWriteTransaction
    ) throws {
        var record = Record.forUserProfile(
            serviceId: serviceId,
            currentTimestamp: currentTimestamp,
            lastVisibleInteractionRowIdInContactThread: lastVisibleInteractionRowIdInContactThread
        )
        try record.insert(tx.databaseConnection)
    }

    public func runIfNeeded() async throws {
        guard FeatureFlags.messageBackupFileAlpha || FeatureFlags.linkAndSync else {
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reachabililityDidChange),
            name: SSKReachability.owsReachabilityDidChange,
            object: nil
        )
    }

    @objc
    private func didUpdateRegistrationState() {
        Task {
            try await runIfNeeded()
        }
    }

    @objc
    private func reachabililityDidChange() {
        Task {
            try await runIfNeeded()
        }
    }

    // MARK: - TaskRunner

    private final class TaskRunner: TaskRecordRunner {
        let dateProvider: DateProvider
        let db: any DB
        let groupsV2: GroupsV2
        let profileFetcher: ProfileFetcher
        let reachabilityManager: SSKReachabilityManager
        let store: TaskStore
        let threadStore: ThreadStore
        let tsAccountManager: TSAccountManager

        init(
            dateProvider: @escaping DateProvider,
            db: any DB,
            groupsV2: GroupsV2,
            profileFetcher: ProfileFetcher,
            reachabilityManager: SSKReachabilityManager,
            store: TaskStore,
            threadStore: ThreadStore,
            tsAccountManager: TSAccountManager
        ) {
            self.dateProvider = dateProvider
            self.db = db
            self.groupsV2 = groupsV2
            self.profileFetcher = profileFetcher
            self.reachabilityManager = reachabilityManager
            self.store = store
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
                    let profile = try db.read { tx in
                        return try OWSUserProfile
                            .filter(Column(OWSUserProfile.CodingKeys.serviceIdString) == serviceId.serviceIdUppercaseString)
                            .fetchOne(tx.databaseConnection)
                    }
                    if profile?.avatarFileName != nil {
                        // We already have an avatar for this profile;
                        // no need to fetch anything.
                        return .cancelled
                    }
                } catch {
                    return .unretryableError(error)
                }

                do {
                    _ = try await profileFetcher.fetchProfileImpl(
                        for: serviceId,
                        options: .opportunistic,
                        authedAccount: .implicit()
                    )
                    return .success
                } catch {
                    // If we failed and think we aren't reachable,
                    // stop trying future tasks.
                    if !reachabilityManager.isReachable {
                        try? await loader.stop()
                    }
                    if record.retryDelay() != nil {
                        return .retryableError(error)
                    } else {
                        return .unretryableError(error)
                    }
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
                    // If we failed and think we aren't reachable,
                    // stop trying future tasks.
                    if !reachabilityManager.isReachable {
                        try? await loader.stop()
                    }
                    if record.retryDelay() != nil {
                        return .retryableError(error)
                    } else {
                        return .unretryableError(error)
                    }
                }
            } else {
                return .cancelled
            }
        }

        func didSucceed(record: Record, tx: DBWriteTransaction) throws {}

        func didFail(record: Record, error: any Error, isRetryable: Bool, tx: DBWriteTransaction) throws {
            guard isRetryable, let retryDelay = record.retryDelay() else {
                return
            }
            var record = record
            record.nextRetryTimestamp = dateProvider().addingTimeInterval(retryDelay).ows_millisecondsSince1970
            record.numRetries += 1
            try record.update(tx.databaseConnection)
        }

        func didCancel(record: Record, tx: DBWriteTransaction) throws {}
    }

    // MARK: - TaskStore

    private class TaskStore: TaskRecordStore {
        typealias Record = MessageBackupAvatarFetcher.Record

        init() {}

        func peek(count: UInt, tx: DBReadTransaction) throws -> [Record] {
            return try Record
                .order(Column(Record.CodingKeys.nextRetryTimestamp).asc)
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

        var nextRetryTimestamp: UInt64
        var numRetries: Int

        private init(
            groupThreadRowId: Int64?,
            groupAvatarUrl: String?,
            serviceId: ServiceId?,
            currentTimestamp: UInt64,
            lastVisibleInteractionRowIdInThread: Int64?
        ) {
            self._id = nil
            self.groupThreadRowId = groupThreadRowId
            self.groupAvatarUrl = groupAvatarUrl
            self.serviceId = serviceId
            self.numRetries = 0

            // We initialize the next retry timestamp in the past (or present),
            // but use a trick for ordering. Since we pop off the queue in
            // nextRetryTimestamp ordering ascending, we initialize the timestamp
            // to a _smaller_ value if the related thread has a more recent message.
            if
                let lastVisibleInteractionRowIdInThread = lastVisibleInteractionRowIdInThread
                    .map({ UInt64(exactly: $0 ) }) ?? nil
            {
                if lastVisibleInteractionRowIdInThread < currentTimestamp {
                    nextRetryTimestamp = currentTimestamp - lastVisibleInteractionRowIdInThread
                } else {
                    nextRetryTimestamp = 0
                }
            } else {
                // If there are no messages, put the row last in the queue,
                // at the current time so its still eligible for download.
                nextRetryTimestamp = currentTimestamp
            }
        }

        static func forGroupAvatar(
            groupThread: TSGroupThread,
            avatarUrl: String,
            currentTimestamp: UInt64,
            lastVisibleInteractionRowIdInGroupThread: Int64?
        ) -> Self? {
            guard let rowId = groupThread.sqliteRowId else { return nil }
            return .init(
                groupThreadRowId: rowId,
                groupAvatarUrl: avatarUrl,
                serviceId: nil,
                currentTimestamp: currentTimestamp,
                lastVisibleInteractionRowIdInThread: lastVisibleInteractionRowIdInGroupThread
            )
        }

        static func forUserProfile(
            serviceId: ServiceId,
            currentTimestamp: UInt64,
            lastVisibleInteractionRowIdInContactThread: Int64?
        ) -> Self {
            return .init(
                groupThreadRowId: nil,
                groupAvatarUrl: nil,
                serviceId: serviceId,
                currentTimestamp: currentTimestamp,
                lastVisibleInteractionRowIdInThread: lastVisibleInteractionRowIdInContactThread
            )
        }

        /// Returns nil if it should not retry.
        func retryDelay() -> TimeInterval? {
            switch numRetries {
            case 0:
                // We can afford to use a high delay;
                // the job run itself has in-memory retries.
                return 60 * 2
            case 1:
                return 60 * 60
            case 2:
                return 60 * 60 * 24
            default:
                return nil
            }
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
            case nextRetryTimestamp
            case numRetries
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self._id = try container.decode(Int64.self, forKey: .id)
            self.groupThreadRowId = try container.decodeIfPresent(Int64.self, forKey: .groupThreadRowId)
            self.groupAvatarUrl = try container.decodeIfPresent(String.self, forKey: .groupAvatarUrl)
            self.serviceId = try container
                .decodeIfPresent(Data.self, forKey: .serviceId)
                .map(ServiceId.parseFrom(serviceIdBinary:))
            self.nextRetryTimestamp = try container.decode(UInt64.self, forKey: .nextRetryTimestamp)
            self.numRetries = try container.decode(Int.self, forKey: .numRetries)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(_id, forKey: .id)
            try container.encodeIfPresent(groupThreadRowId, forKey: .groupThreadRowId)
            try container.encodeIfPresent(groupAvatarUrl, forKey: .groupAvatarUrl)
            try container.encodeIfPresent(serviceId?.serviceIdBinary.asData, forKey: .serviceId)
            try container.encode(nextRetryTimestamp, forKey: .nextRetryTimestamp)
            try container.encode(numRetries, forKey: .numRetries)
        }
    }
}
