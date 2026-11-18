//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class GroupDataDeletionManagerTests: SSKBaseTest {
    private var bulkDeleteInteractionJobQueue: BulkDeleteInteractionJobQueue!
    private var groupDataDeletionManager: GroupDataDeletionManagerImpl!
    private var groupUpdateInfoMessageInserter: GroupUpdateInfoMessageInserterImpl!

    override func setUp() {
        super.setUp()
        write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx,
            )
        }
        bulkDeleteInteractionJobQueue = BulkDeleteInteractionJobQueue(
            addressableMessageFinder: DeleteForMeAddressableMessageFinderImpl(),
            db: DependenciesBridge.shared.db,
            interactionDeleteManager: DependenciesBridge.shared.interactionDeleteManager,
            threadDeletionManager: DependenciesBridge.shared.threadDeletionManager,
            threadStore: ThreadStoreImpl(),
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
        )
        groupDataDeletionManager = GroupDataDeletionManagerImpl(
            bulkDeleteInteractionJobQueue: bulkDeleteInteractionJobQueue,
            threadDeletionManager: DependenciesBridge.shared.threadDeletionManager,
        )
        groupUpdateInfoMessageInserter = GroupUpdateInfoMessageInserterImpl(
            dateProvider: { Date() },
            groupDataDeletionManager: groupDataDeletionManager,
            groupUpdateItemBuilder: GroupUpdateItemBuilderImpl(
                contactsManager: SSKEnvironment.shared.contactManagerRef,
                recipientDatabaseTable: DependenciesBridge.shared.recipientDatabaseTable,
            ),
            isGroupDataDeletionEnabled: true,
            notificationPresenter: NoopNotificationPresenterImpl(),
        )
    }

    private func insertGroupThread(tx: DBWriteTransaction) -> TSGroupThread {
        return try! GroupManager.createGroupForTests(
            members: [LocalIdentifiers.forUnitTests.aciAddress],
            name: "Roommates",
            transaction: tx,
        )
    }

    private func insertInfoMessage(in groupThread: TSGroupThread, tx: DBWriteTransaction) -> TSInfoMessage {
        let infoMessage = TSInfoMessage(thread: groupThread, messageType: .typeGroupUpdate)
        infoMessage.anyInsert(transaction: tx)
        return infoMessage
    }

    private func bulkDeleteJobCount() -> Int {
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            try! Int.fetchOne(
                tx.database,
                sql: """
                    SELECT COUNT(*) FROM \(BulkDeleteInteractionJobRecord.databaseTableName)
                    WHERE "\(BulkDeleteInteractionJobRecord.columnName(.label))" = ?
                """,
                arguments: [BulkDeleteInteractionJobRecord.jobRecordType.jobRecordLabel],
            )!
        }
    }

    private func waitForBulkDeleteJobsToFinish() async throws {
        let deadline = Date().addingTimeInterval(10)
        while bulkDeleteJobCount() > 0 {
            guard Date() < deadline else {
                XCTFail("Bulk delete job didn't finish")
                return
            }
            try await Task.sleep(nanoseconds: 10 * NSEC_PER_MSEC)
        }
    }

    func testDeletesOnlyInteractionsBeforePreservedInteraction() async throws {
        let (groupThread, preservedMessage, laterMessage) = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            let groupThread = self.insertGroupThread(tx: tx)
            _ = self.insertInfoMessage(in: groupThread, tx: tx)
            _ = self.insertInfoMessage(in: groupThread, tx: tx)
            let preservedMessage = self.insertInfoMessage(in: groupThread, tx: tx)
            self.groupDataDeletionManager.deleteGroupData(
                groupThread: groupThread,
                preservedInteraction: preservedMessage,
                localIdentifiers: .forUnitTests,
                tx: tx,
            )
            let laterMessage = self.insertInfoMessage(in: groupThread, tx: tx)
            return (groupThread, preservedMessage, laterMessage)
        }

        bulkDeleteInteractionJobQueue.start(appContext: CurrentAppContext())
        try await waitForBulkDeleteJobsToFinish()

        let remainingUniqueIds = SSKEnvironment.shared.databaseStorageRef.read { tx in
            try! InteractionFinder(threadUniqueId: groupThread.uniqueId)
                .fetchAllInteractions(rowIdFilter: .newest, limit: 10, tx: tx)
                .map(\.uniqueId)
        }
        XCTAssertEqual(Set(remainingUniqueIds), [preservedMessage.uniqueId, laterMessage.uniqueId])
    }

    func testClearsDrafts() throws {
        let voiceMessageUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
        try Data(count: 16).write(to: voiceMessageUrl)

        let groupThread = write { tx in
            let groupThread = insertGroupThread(tx: tx)
            groupThread.anyUpdate(transaction: tx) { thread in
                thread.messageDraft = "Draft"
            }
            _ = VoiceMessageInterruptedDraftStore.saveDraft(
                audioFileUrl: voiceMessageUrl,
                threadUniqueId: groupThread.uniqueId,
                transaction: tx,
            )
            let preservedMessage = insertInfoMessage(in: groupThread, tx: tx)
            groupDataDeletionManager.deleteGroupData(
                groupThread: groupThread,
                preservedInteraction: preservedMessage,
                localIdentifiers: .forUnitTests,
                tx: tx,
            )
            return groupThread
        }

        let (messageDraft, hasVoiceMessageDraft) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            (
                TSThread.anyFetch(uniqueId: groupThread.uniqueId, transaction: tx)?.messageDraft,
                VoiceMessageInterruptedDraftStore.hasDraft(for: groupThread.uniqueId, transaction: tx),
            )
        }
        XCTAssertNil(messageDraft)
        XCTAssertFalse(hasVoiceMessageDraft)
    }

    // MARK: - Group update info messages

    private let adminAci = Aci.constantForTesting("00000000-0000-4000-8000-00000000000A")
    private let otherAci = Aci.constantForTesting("00000000-0000-4000-8000-00000000000B")

    private func insertGroupThreadWithMembers(tx: DBWriteTransaction) -> TSGroupThread {
        let groupThread = try! GroupManager.createGroupForTests(
            members: [LocalIdentifiers.forUnitTests.aciAddress],
            name: "Roommates",
            transaction: tx,
        )
        var membershipBuilder = GroupMembership.Builder()
        membershipBuilder.addFullMember(LocalIdentifiers.forUnitTests.aci, role: .administrator)
        membershipBuilder.addFullMember(adminAci, role: .administrator)
        membershipBuilder.addFullMember(otherAci, role: .normal)
        var modelBuilder = (groupThread.groupModel as! TSGroupModelV2).asBuilder
        modelBuilder.groupMembership = membershipBuilder.build()
        groupThread.update(with: try! modelBuilder.buildAsV2(), transaction: tx)
        return groupThread
    }

    private func insertUpdate(
        groupThread: TSGroupThread,
        removedAcis: [Aci] = [],
        isTerminating: Bool = false,
        groupUpdateSource: GroupUpdateSource,
        dataDeletionRequest: GroupDataDeletionRequest,
        tx: DBWriteTransaction,
    ) {
        let oldGroupModel = groupThread.groupModel as! TSGroupModelV2
        var membershipBuilder = oldGroupModel.groupMembership.asBuilder
        for removedAci in removedAcis {
            membershipBuilder.remove(removedAci)
        }
        var modelBuilder = oldGroupModel.asBuilder
        modelBuilder.groupMembership = membershipBuilder.build()
        modelBuilder.groupV2Revision = oldGroupModel.revision + 1
        modelBuilder.isTerminated = isTerminating
        groupUpdateInfoMessageInserter.insertGroupUpdateInfoMessage(
            localIdentifiers: .forUnitTests,
            spamReportingMetadata: .unreportable,
            groupThread: groupThread,
            oldGroupModel: oldGroupModel,
            newGroupModel: try! modelBuilder.buildAsV2(),
            oldDisappearingMessageToken: .disabledToken,
            newDisappearingMessageToken: .disabledToken,
            newlyLearnedPniToAciAssociations: [:],
            groupUpdateSource: groupUpdateSource,
            dataDeletionRequest: dataDeletionRequest,
            transaction: tx,
        )
    }

    private func remainingInfoMessages(groupThread: TSGroupThread) -> [TSInfoMessage] {
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            try! InteractionFinder(threadUniqueId: groupThread.uniqueId)
                .fetchAllInteractions(rowIdFilter: .newest, limit: 10, tx: tx)
                .map { $0 as! TSInfoMessage }
        }
    }

    private func updateItems(infoMessages: [TSInfoMessage]) -> [TSInfoMessage.PersistableGroupUpdateItem] {
        return infoMessages.flatMap { infoMessage in
            let wrapper = infoMessage.infoMessageUserInfo?[.groupUpdateItems] as? TSInfoMessage.PersistableGroupUpdateItemsWrapper
            return wrapper?.updateItems ?? []
        }
    }

    func testLocalUserRemovedWithDataDeletionKeepsOnlyRemovalEvent() async throws {
        let groupThread = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            let groupThread = self.insertGroupThreadWithMembers(tx: tx)
            _ = self.insertInfoMessage(in: groupThread, tx: tx)
            self.insertUpdate(
                groupThread: groupThread,
                removedAcis: [LocalIdentifiers.forUnitTests.aci, self.otherAci],
                groupUpdateSource: .aci(self.adminAci),
                dataDeletionRequest: .membersRemoved([LocalIdentifiers.forUnitTests.aci, self.otherAci]),
                tx: tx,
            )
            return groupThread
        }

        bulkDeleteInteractionJobQueue.start(appContext: CurrentAppContext())
        try await waitForBulkDeleteJobsToFinish()

        let remainingInfoMessages = remainingInfoMessages(groupThread: groupThread)
        XCTAssertEqual(remainingInfoMessages.count, 1)
        switch updateItems(infoMessages: remainingInfoMessages).first {
        case .localUserRemovedWithDataDeletion(let removerAci):
            XCTAssertEqual(removerAci.wrappedValue, adminAci)
        default:
            XCTFail("Expected a removal with data deletion.")
        }
    }

    func testGroupTerminatedWithDataDeletionKeepsOnlyTerminateEvent() async throws {
        let groupThread = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            let groupThread = self.insertGroupThreadWithMembers(tx: tx)
            _ = self.insertInfoMessage(in: groupThread, tx: tx)
            self.insertUpdate(
                groupThread: groupThread,
                isTerminating: true,
                groupUpdateSource: .aci(self.adminAci),
                dataDeletionRequest: .groupTerminated,
                tx: tx,
            )
            return groupThread
        }

        bulkDeleteInteractionJobQueue.start(appContext: CurrentAppContext())
        try await waitForBulkDeleteJobsToFinish()

        let remainingInfoMessages = remainingInfoMessages(groupThread: groupThread)
        XCTAssertEqual(remainingInfoMessages.count, 1)
        switch updateItems(infoMessages: remainingInfoMessages).first {
        case .groupTerminatedWithDataDeletionByOtherUser(let updaterAci):
            XCTAssertEqual(updaterAci.wrappedValue, adminAci)
        default:
            XCTFail("Expected a group termination with data deletion.")
        }
    }

    func testGroupTerminatedWithDataDeletionFromLinkedDeviceKeepsOnlyTerminateEvent() async throws {
        let groupThread = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            let groupThread = self.insertGroupThreadWithMembers(tx: tx)
            _ = self.insertInfoMessage(in: groupThread, tx: tx)
            self.insertUpdate(
                groupThread: groupThread,
                isTerminating: true,
                groupUpdateSource: .localUser(originalSource: .aci(LocalIdentifiers.forUnitTests.aci)),
                dataDeletionRequest: .groupTerminated,
                tx: tx,
            )
            return groupThread
        }

        bulkDeleteInteractionJobQueue.start(appContext: CurrentAppContext())
        try await waitForBulkDeleteJobsToFinish()

        let remainingInfoMessages = remainingInfoMessages(groupThread: groupThread)
        XCTAssertEqual(remainingInfoMessages.count, 1)
        switch updateItems(infoMessages: remainingInfoMessages).first {
        case .groupTerminatedWithDataDeletionByLocalUser:
            break
        default:
            XCTFail("Expected a group termination with data deletion by the local user.")
        }
    }

    func testOtherUserRemovedWithDataDeletionKeepsLocalData() {
        let groupThread = write { tx in
            let groupThread = insertGroupThreadWithMembers(tx: tx)
            _ = insertInfoMessage(in: groupThread, tx: tx)
            insertUpdate(
                groupThread: groupThread,
                removedAcis: [otherAci],
                groupUpdateSource: .aci(adminAci),
                dataDeletionRequest: .membersRemoved([otherAci]),
                tx: tx,
            )
            return groupThread
        }

        XCTAssertEqual(bulkDeleteJobCount(), 0)
        let remainingInfoMessages = remainingInfoMessages(groupThread: groupThread)
        XCTAssertEqual(remainingInfoMessages.count, 2)
        switch updateItems(infoMessages: remainingInfoMessages).first {
        case .otherUserRemovedWithDataDeletion(let removerAci, let userAci):
            XCTAssertEqual(removerAci.wrappedValue, adminAci)
            XCTAssertEqual(userAci.wrappedValue, otherAci)
        default:
            XCTFail("Expected another user's removal with data deletion.")
        }
    }

    func testOtherUserRemovedWithDataDeletionFromLinkedDeviceKeepsLocalData() {
        let groupThread = write { tx in
            let groupThread = insertGroupThreadWithMembers(tx: tx)
            _ = insertInfoMessage(in: groupThread, tx: tx)
            insertUpdate(
                groupThread: groupThread,
                removedAcis: [otherAci],
                groupUpdateSource: .localUser(originalSource: .aci(LocalIdentifiers.forUnitTests.aci)),
                dataDeletionRequest: .membersRemoved([otherAci]),
                tx: tx,
            )
            return groupThread
        }

        XCTAssertEqual(bulkDeleteJobCount(), 0)
        let remainingInfoMessages = remainingInfoMessages(groupThread: groupThread)
        XCTAssertEqual(remainingInfoMessages.count, 2)
        switch updateItems(infoMessages: remainingInfoMessages).first {
        case .otherUserRemovedWithDataDeletionByLocalUser(let userAci):
            XCTAssertEqual(userAci.wrappedValue, otherAci)
        default:
            XCTFail("Expected the local user's removal of another user with data deletion.")
        }
    }
}

// MARK: -

final class GroupDataDeletionRequestTests: SSKBaseTest {
    private static let adminAci = Aci.constantForTesting("00000000-0000-4000-8000-00000000000A")
    private static let memberAci = Aci.constantForTesting("00000000-0000-4000-8000-00000000000B")
    private static let otherAci = Aci.constantForTesting("00000000-0000-4000-8000-00000000000C")

    private var groupMembership: GroupMembership {
        var builder = GroupMembership.Builder()
        builder.addFullMember(Self.adminAci, role: .administrator)
        builder.addFullMember(Self.memberAci, role: .normal)
        builder.addFullMember(Self.otherAci, role: .normal)
        return builder.build()
    }

    private func makeDeleteData(memberAcis: [Aci] = [], terminate: Bool = false) -> SSKProtoGroupContextV2DeleteData {
        let deleteData = SSKProtoGroupContextV2DeleteData.builder()
        deleteData.setMemberAcis(memberAcis.map(\.serviceIdBinary))
        deleteData.setTerminate(terminate)
        return deleteData.buildInfallibly()
    }

    private func makeRequest(
        memberAcis: [Aci] = [],
        terminate: Bool = false,
        senderAci: Aci = GroupDataDeletionRequestTests.adminAci,
        changeAuthorAci: Aci? = GroupDataDeletionRequestTests.adminAci,
        removedAcis: Set<Aci> = [],
        terminatesGroup: Bool = false,
    ) -> GroupDataDeletionRequest? {
        return GroupDataDeletionRequest(
            received: ReceivedGroupDataDeletionRequest(
                deleteData: makeDeleteData(memberAcis: memberAcis, terminate: terminate),
                senderAci: senderAci,
            ),
            changeAuthorAci: changeAuthorAci,
            oldGroupMembership: groupMembership,
            removedAcis: removedAcis,
            terminatesGroup: terminatesGroup,
        )
    }

    func testAcceptsRemovedMembers() {
        XCTAssertEqual(
            makeRequest(memberAcis: [Self.memberAci], removedAcis: [Self.memberAci, Self.otherAci]),
            .membersRemoved([Self.memberAci]),
        )
    }

    func testAcceptsTermination() {
        XCTAssertEqual(makeRequest(terminate: true, terminatesGroup: true), .groupTerminated)
    }

    func testRejectsSenderWhoIsNotTheAuthor() {
        XCTAssertNil(makeRequest(memberAcis: [Self.memberAci], senderAci: Self.otherAci, removedAcis: [Self.memberAci]))
    }

    func testRejectsChangeWithoutAciAuthor() {
        XCTAssertNil(makeRequest(memberAcis: [Self.memberAci], changeAuthorAci: nil, removedAcis: [Self.memberAci]))
    }

    func testRejectsAuthorWhoIsNotAnAdmin() {
        XCTAssertNil(makeRequest(
            memberAcis: [Self.memberAci],
            senderAci: Self.otherAci,
            changeAuthorAci: Self.otherAci,
            removedAcis: [Self.memberAci],
        ))
    }

    func testRejectsMemberTheChangeDoesNotRemove() {
        XCTAssertNil(makeRequest(memberAcis: [Self.memberAci, Self.otherAci], removedAcis: [Self.memberAci]))
    }

    func testRejectsTerminationWithoutTerminateAction() {
        XCTAssertNil(makeRequest(terminate: true, terminatesGroup: false))
    }

    func testRejectsEmptyRequest() {
        XCTAssertNil(makeRequest(removedAcis: [Self.memberAci]))
    }

    func testAppliedRemovalCarriesValidatedRequest() throws {
        let changedGroupModel = try applyAdminChange(deleteData: makeDeleteData(memberAcis: [Self.memberAci])) { changeActions, groupV2Params in
            var deleteMember = GroupsProtoGroupChangeActionsDeleteMemberAction.builder()
            deleteMember.setDeletedUserID(try groupV2Params.userId(for: Self.memberAci))
            changeActions.addDeleteMembers(deleteMember.buildInfallibly())
        }

        XCTAssertEqual(changedGroupModel.dataDeletionRequest, .membersRemoved([Self.memberAci]))
    }

    func testAppliedTerminationCarriesValidatedRequest() throws {
        let changedGroupModel = try applyAdminChange(deleteData: makeDeleteData(terminate: true)) { changeActions, _ in
            changeActions.setTerminateGroup(GroupsProtoGroupChangeActionsTerminateGroupAction.builder().buildInfallibly())
        }

        XCTAssertEqual(changedGroupModel.dataDeletionRequest, .groupTerminated)
    }

    private func applyAdminChange(
        deleteData: SSKProtoGroupContextV2DeleteData,
        addActions: (inout GroupsProtoGroupChangeActionsBuilder, GroupV2Params) throws -> Void,
    ) throws -> ChangedGroupModel {
        return try write { tx -> ChangedGroupModel in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx,
            )
            let groupThread = try GroupManager.createGroupForTests(
                members: [LocalIdentifiers.forUnitTests.aciAddress],
                transaction: tx,
            )

            var membershipBuilder = GroupMembership.Builder()
            membershipBuilder.addFullMember(LocalIdentifiers.forUnitTests.aci, role: .normal)
            membershipBuilder.addFullMember(Self.adminAci, role: .administrator)
            membershipBuilder.addFullMember(Self.memberAci, role: .normal)
            var modelBuilder = (groupThread.groupModel as! TSGroupModelV2).asBuilder
            modelBuilder.groupMembership = membershipBuilder.build()
            let oldGroupModel = try modelBuilder.buildAsV2()
            groupThread.update(with: oldGroupModel, transaction: tx)

            let groupV2Params = try oldGroupModel.groupV2Params()
            var changeActions = GroupsProtoGroupChangeActions.builder()
            changeActions.setSourceUserID(try groupV2Params.userId(for: Self.adminAci))
            changeActions.setRevision(oldGroupModel.revision + 1)
            try addActions(&changeActions, groupV2Params)

            return try GroupsV2IncomingChanges.applyChangesToGroupModel(
                groupThread: groupThread,
                localIdentifiers: .forUnitTests,
                changeActionsProto: changeActions.buildInfallibly(),
                downloadedAvatars: GroupAvatarStateMap(),
                options: [],
                receivedDataDeletionRequest: ReceivedGroupDataDeletionRequest(
                    deleteData: deleteData,
                    senderAci: Self.adminAci,
                ),
            )
        }
    }
}
