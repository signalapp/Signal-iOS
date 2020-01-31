//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public enum GroupsV2Error: Error {
    // By the time we tried to apply the change, it was irrelevant.
    //
    // GroupsV2 TODO: We must handle this.  Not try to retry.
    case redundantChange
    // GroupsV2 TODO: We must handle this.  We've probably been removed from the group.
    case unauthorized
    case shouldRetry
    case shouldDiscard
    case groupNotInDatabase
}

@objc
public protocol GroupsV2: AnyObject {

    func createNewGroupOnServiceObjc(groupModel: TSGroupModel) -> AnyPromise

    func generateGroupSecretParamsData() throws -> Data

    func groupId(forGroupSecretParamsData groupSecretParamsData: Data) throws -> Data

    func hasProfileKeyCredential(for address: SignalServiceAddress,
                                 transaction: SDSAnyReadTransaction) -> Bool

    func tryToEnsureProfileKeyCredentialsObjc(for addresses: [SignalServiceAddress]) -> AnyPromise

    func buildGroupContextV2Proto(groupModel: TSGroupModel,
                                  changeActionsProtoData: Data?) throws -> SSKProtoGroupContextV2

    func groupV2ContextInfo(forMasterKeyData masterKeyData: Data?) throws -> GroupV2ContextInfo

    func parseAndVerifyChangeActionsProto(_ changeProtoData: Data) throws -> GroupsProtoGroupChangeActions
}

// MARK: -

public protocol GroupsV2Swift {
    func createNewGroupOnService(groupModel: TSGroupModel) -> Promise<Void>

    func tryToEnsureProfileKeyCredentials(for addresses: [SignalServiceAddress]) -> Promise<Void>

    func fetchCurrentGroupV2Snapshot(groupModel: TSGroupModel) -> Promise<GroupV2Snapshot>

    func fetchCurrentGroupV2Snapshot(groupSecretParamsData: Data) -> Promise<GroupV2Snapshot>

    func fetchGroupChangeActions(groupSecretParamsData: Data) -> Promise<[GroupV2Change]>

    func buildChangeSet(oldGroupModel: TSGroupModel,
                        newGroupModel: TSGroupModel,
                        oldDMConfiguration: OWSDisappearingMessagesConfiguration,
                        newDMConfiguration: OWSDisappearingMessagesConfiguration,
                        transaction: SDSAnyReadTransaction) throws -> GroupsV2ChangeSet

    // On success returns a group thread model that reflects the
    // latest state in the service, which (due to races) might
    // reflect changes after the change set.
    func updateExistingGroupOnService(changeSet: GroupsV2ChangeSet) -> Promise<TSGroupThread>

    func acceptInviteToGroupV2(groupThread: TSGroupThread) -> Promise<TSGroupThread>

    func leaveGroupV2OrDeclineInvite(groupThread: TSGroupThread) -> Promise<TSGroupThread>

    func updateDisappearingMessageStateOnService(groupThread: TSGroupThread,
                                                 disappearingMessageToken: DisappearingMessageToken) -> Promise<TSGroupThread>

    func reuploadLocalProfilePromise() -> Promise<Void>
}

// MARK: -

public protocol GroupsV2ChangeSet: AnyObject {
    var groupId: Data { get }
    var groupSecretParamsData: Data { get }

    func buildGroupChangeProto(currentGroupModel: TSGroupModel,
                               currentDisappearingMessageToken: DisappearingMessageToken) -> Promise<GroupsProtoGroupChangeActions>
}

// MARK: -

public enum GroupUpdateMode {
    // * Group update should halt at a specific revision.
    // * Group update _should not_ block on message processing.
    // * Group update _should not_ be throttled.
    case upToSpecificRevisionImmediately(upToRevision: UInt32)
    // * Group update should continue until current revision.
    // * Group update _should_ block on message processing.
    // * Group update _should_ be throttled.
    case upToCurrentRevisionAfterMessageProcessWithThrottling
}

// MARK: -

@objc
public protocol GroupV2Updates: AnyObject {

    func tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithThrottling(_ groupThread: TSGroupThread)

    func tryToRefreshV2GroupUpToSpecificRevisionImmediately(_ groupThread: TSGroupThread,
                                                            upToRevision: UInt32)

    func updateGroupWithChangeActions(groupId: Data,
                                      changeActionsProto: GroupsProtoGroupChangeActions,
                                      transaction: SDSAnyWriteTransaction) throws -> TSGroupThread
}

// MARK: -

public protocol GroupV2UpdatesSwift: GroupV2Updates {
    func tryToRefreshV2GroupThreadWithThrottling(groupId: Data,
                                                 groupSecretParamsData: Data,
                                                 groupUpdateMode: GroupUpdateMode) -> Promise<Void>
}

// MARK: -

// GroupsV2 TODO: Can we eventually remove this and just use TSGroupModel?
public protocol GroupV2Snapshot {
    var groupSecretParamsData: Data { get }

    var debugDescription: String { get }

    var revision: UInt32 { get }

    var title: String { get }

    // GroupsV2 TODO: Avatar.
    // GroupsV2 TODO: DM state.

    var groupMembership: GroupMembership { get }

    var groupAccess: GroupAccess { get }

    var accessControlForAttributes: GroupsProtoAccessControlAccessRequired { get }
    var accessControlForMembers: GroupsProtoAccessControlAccessRequired { get }

    var disappearingMessageToken: DisappearingMessageToken { get }
}

// MARK: -

public struct GroupV2Change {
    public let snapshot: GroupV2Snapshot
    public let changeActionsProto: GroupsProtoGroupChangeActions

    public init(snapshot: GroupV2Snapshot,
                changeActionsProto: GroupsProtoGroupChangeActions) {
        self.snapshot = snapshot
        self.changeActionsProto = changeActionsProto
    }
}

// MARK: -

@objc
public class GroupV2ContextInfo: NSObject {
    @objc
    let masterKeyData: Data
    @objc
    let groupSecretParamsData: Data
    @objc
    let groupId: Data

    public init(masterKeyData: Data, groupSecretParamsData: Data, groupId: Data) {
        self.masterKeyData = masterKeyData
        self.groupSecretParamsData = groupSecretParamsData
        self.groupId = groupId
    }
}

// MARK: -

public class MockGroupsV2: NSObject, GroupsV2, GroupsV2Swift {

    public func createNewGroupOnService(groupModel: TSGroupModel) -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public func createNewGroupOnServiceObjc(groupModel: TSGroupModel) -> AnyPromise {
        owsFail("Not implemented.")
    }

    public func generateGroupSecretParamsData() throws -> Data {
        owsFail("Not implemented.")
    }

    public func groupId(forGroupSecretParamsData groupSecretParamsData: Data) throws -> Data {
        owsFail("Not implemented.")
    }

    public func hasProfileKeyCredential(for address: SignalServiceAddress,
                                        transaction: SDSAnyReadTransaction) -> Bool {
        owsFail("Not implemented.")
    }

    public func tryToEnsureProfileKeyCredentialsObjc(for addresses: [SignalServiceAddress]) -> AnyPromise {
        owsFail("Not implemented.")
    }

    public func tryToEnsureProfileKeyCredentials(for addresses: [SignalServiceAddress]) -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public func fetchCurrentGroupV2Snapshot(groupModel: TSGroupModel) -> Promise<GroupV2Snapshot> {
        owsFail("Not implemented.")
    }

    public func fetchCurrentGroupV2Snapshot(groupSecretParamsData: Data) -> Promise<GroupV2Snapshot> {
        owsFail("Not implemented.")
    }

    public func fetchGroupChangeActions(groupSecretParamsData: Data) -> Promise<[GroupV2Change]> {
        owsFail("Not implemented.")
    }

    public func buildGroupContextV2Proto(groupModel: TSGroupModel,
                                         changeActionsProtoData: Data?) throws -> SSKProtoGroupContextV2 {
        owsFail("Not implemented.")
    }

    public func buildChangeSet(oldGroupModel: TSGroupModel,
                               newGroupModel: TSGroupModel,
                               oldDMConfiguration: OWSDisappearingMessagesConfiguration,
                               newDMConfiguration: OWSDisappearingMessagesConfiguration,
                               transaction: SDSAnyReadTransaction) throws -> GroupsV2ChangeSet {
        owsFail("Not implemented.")
    }

    public func updateExistingGroupOnService(changeSet: GroupsV2ChangeSet) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func acceptInviteToGroupV2(groupThread: TSGroupThread) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func leaveGroupV2OrDeclineInvite(groupThread: TSGroupThread) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func updateDisappearingMessageStateOnService(groupThread: TSGroupThread,
                                                        disappearingMessageToken: DisappearingMessageToken) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func reuploadLocalProfilePromise() -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public func groupV2ContextInfo(forMasterKeyData masterKeyData: Data?) throws -> GroupV2ContextInfo {
        owsFail("Not implemented.")
    }

    public func parseAndVerifyChangeActionsProto(_ changeProtoData: Data) throws -> GroupsProtoGroupChangeActions {
        owsFail("Not implemented.")
    }
}

// MARK: -

public class MockGroupV2Updates: NSObject, GroupV2UpdatesSwift {
    @objc
    public func tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithThrottling(_ groupThread: TSGroupThread) {
        owsFail("Not implemented.")
    }

    @objc
    public func tryToRefreshV2GroupUpToSpecificRevisionImmediately(_ groupThread: TSGroupThread,
                                                                   upToRevision: UInt32) {
        owsFail("Not implemented.")
    }

    public func tryToRefreshV2GroupThreadWithThrottling(groupId: Data,
                                                        groupSecretParamsData: Data,
                                                        groupUpdateMode: GroupUpdateMode) -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public func updateGroupWithChangeActions(groupId: Data,
                                             changeActionsProto: GroupsProtoGroupChangeActions,
                                             transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {
        owsFail("Not implemented.")
    }
}
