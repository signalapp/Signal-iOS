//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalUI
import XCTest

@testable import Signal
@testable import SignalServiceKit

final class GroupViewHelperTests: SignalBaseTest {
    private let localAci = LocalIdentifiers.forUnitTests.aci

    private func makeGroupViewHelper(
        membersAccess: GroupV2Access,
        localRole: TSGroupMemberRole?,
        isBlocked: Bool = false,
    ) throws -> GroupViewHelper {
        let secretParams = try GroupSecretParams.generate()

        var membershipBuilder = GroupMembership.Builder()
        membershipBuilder.addFullMember(Aci.randomForTesting(), role: .administrator)
        if let localRole {
            membershipBuilder.addFullMember(localAci, role: localRole)
        }

        var modelBuilder = TSGroupModelBuilder(secretParams: secretParams)
        modelBuilder.groupMembership = membershipBuilder.build()
        modelBuilder.groupAccess = GroupAccess(
            members: membersAccess,
            attributes: .member,
            addFromInviteLink: .unsatisfiable,
            memberLabels: .member,
        )
        let groupModel = try modelBuilder.buildAsV2()

        let thread = write { tx in
            let thread = TSGroupThread(groupModel: groupModel)
            thread.anyInsert(transaction: tx)
            _ = GroupRecord.insertRecord(
                groupId: groupModel.groupId,
                threadId: thread.sqliteRowId!,
                masterKey: try! secretParams.getMasterKey(),
                refreshedAt: .distantPast,
                status: isBlocked ? .blocked : .unspecified,
                tx: tx,
            )
            return thread
        }

        let threadViewModel = read { tx in
            ThreadViewModel(thread: thread, forChatList: false, transaction: tx)
        }
        return GroupViewHelper(threadViewModel: threadViewModel, memberLabelCoordinator: nil)
    }

    func testMemberCanEditMembershipWhenMembersCanAdd() throws {
        let groupViewHelper = try makeGroupViewHelper(membersAccess: .member, localRole: .normal)

        XCTAssertTrue(groupViewHelper.canEditConversationMembership(localAci: localAci))
    }

    func testMemberCannotEditMembershipWhenOnlyAdminsCanAdd() throws {
        let groupViewHelper = try makeGroupViewHelper(membersAccess: .administrator, localRole: .normal)

        XCTAssertFalse(groupViewHelper.canEditConversationMembership(localAci: localAci))
    }

    func testAdminCanEditMembershipWhenOnlyAdminsCanAdd() throws {
        let groupViewHelper = try makeGroupViewHelper(membersAccess: .administrator, localRole: .administrator)

        XCTAssertTrue(groupViewHelper.canEditConversationMembership(localAci: localAci))
    }

    func testNonMemberCannotEditMembership() throws {
        let groupViewHelper = try makeGroupViewHelper(membersAccess: .member, localRole: nil)

        XCTAssertFalse(groupViewHelper.canEditConversationMembership(localAci: localAci))
    }

    func testMemberCannotEditMembershipOfBlockedGroup() throws {
        let groupViewHelper = try makeGroupViewHelper(membersAccess: .member, localRole: .normal, isBlocked: true)

        XCTAssertFalse(groupViewHelper.canEditConversationMembership(localAci: localAci))
    }

    func testPropertyUsesLocalAci() throws {
        write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx,
            )
        }
        let adminHelper = try makeGroupViewHelper(membersAccess: .administrator, localRole: .administrator)
        let memberHelper = try makeGroupViewHelper(membersAccess: .administrator, localRole: .normal)

        XCTAssertTrue(adminHelper.canEditConversationMembership)
        XCTAssertFalse(memberHelper.canEditConversationMembership)
    }
}
