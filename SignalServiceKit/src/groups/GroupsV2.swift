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
}

@objc
public protocol GroupsV2: AnyObject {

    func createNewGroupOnServiceObjc(groupModel: TSGroupModel) -> AnyPromise

    func generateGroupSecretParamsData() throws -> Data

    func groupId(forGroupSecretParamsData groupSecretParamsData: Data) throws -> Data

    func hasProfileKeyCredential(for address: SignalServiceAddress,
                                 transaction: SDSAnyReadTransaction) -> Bool

    func tryToEnsureProfileKeyCredentialsObjc(for addresses: [SignalServiceAddress]) -> AnyPromise

    func fetchCurrentGroupStateObjc(groupModel: TSGroupModel) -> AnyPromise

    func buildGroupContextV2Proto(groupModel: TSGroupModel,
                                  changeActionsProtoData: Data?) throws -> SSKProtoGroupContextV2

    func groupV2ContextInfo(forMasterKeyData masterKeyData: Data?) throws -> GroupV2ContextInfo

    func parseAndVerifyChangeActionsProto(_ changeProtoData: Data) throws -> GroupsProtoGroupChangeActions
}

// MARK: -

public protocol GroupsV2Swift {
    func createNewGroupOnService(groupModel: TSGroupModel) -> Promise<Void>

    func tryToEnsureProfileKeyCredentials(for addresses: [SignalServiceAddress]) -> Promise<Void>

    func fetchCurrentGroupState(groupModel: TSGroupModel) -> Promise<GroupV2State>

    func fetchCurrentGroupState(groupSecretParamsData: Data) -> Promise<GroupV2State>

    func buildChangeSet(from oldGroupModel: TSGroupModel,
                        to newGroupModel: TSGroupModel,
                        transaction: SDSAnyReadTransaction) throws -> GroupsV2ChangeSet

    // On success returns a group thread model that reflects the
    // latest state in the service, which (due to races) might
    // reflect changes after the change set.
    func updateExistingGroupOnService(changeSet: GroupsV2ChangeSet) -> Promise<UpdatedV2Group>

    func reuploadLocalProfilePromise() -> Promise<Void>

    func applyChangesToGroupModel(groupThread: TSGroupThread,
                                  changeActionsProto: GroupsProtoGroupChangeActions,
                                  changeActionsProtoData: Data,
                                  transaction: SDSAnyReadTransaction) throws -> ChangedGroupModel

    // GroupsV2 TODO: Move to GroupUpdates?
    func fetchAndApplyGroupV2UpdatesFromService(groupId: Data,
                                                groupSecretParamsData: Data,
                                                upToRevision: UInt32,
                                                waitForMessageProcessing: Bool) -> Promise<TSGroupThread>
}

// MARK: -

public protocol GroupsV2ChangeSet: AnyObject {
    var groupId: Data { get }
    var groupSecretParamsData: Data { get }

    func buildGroupChangeProto(currentGroupModel: TSGroupModel) -> Promise<GroupsProtoGroupChangeActions>
}

// MARK: -

public enum GroupUpdateMode {
    case upToRevisionImmediately(revision: UInt32)
    case upToLatestAfterMessageProcess
}

// MARK: -

@objc
public protocol GroupUpdates: AnyObject {
    func tryToRefreshGroupThreadToLatestStateWithThrottling(_ thread: TSThread)

    func updateGroupWithChangeActions(groupId: Data,
                                             changeActionsProto: GroupsProtoGroupChangeActions,
                                             changeActionsProtoData: Data,
                                             transaction: SDSAnyWriteTransaction) throws -> TSGroupThread
}

// MARK: -

// GroupsV2 TODO: Can we eventually remove this and just use TSGroupModel?
public protocol GroupV2State {
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

public struct ChangedGroupModel {
    public let groupThread: TSGroupThread
    public let oldGroupModel: TSGroupModel
    public let newGroupModel: TSGroupModel
    public let changeAuthorUuid: UUID
    public let changeActionsProtoData: Data

    public init(groupThread: TSGroupThread,
                oldGroupModel: TSGroupModel,
                newGroupModel: TSGroupModel,
                changeAuthorUuid: UUID,
                changeActionsProtoData: Data) {
        self.groupThread = groupThread
        self.oldGroupModel = oldGroupModel
        self.newGroupModel = newGroupModel
        self.changeAuthorUuid = changeAuthorUuid
        self.changeActionsProtoData = changeActionsProtoData
    }
}

// MARK: -

public struct UpdatedV2Group {
    public let groupThread: TSGroupThread
    public let changeActionsProtoData: Data

    public init(groupThread: TSGroupThread,
                changeActionsProtoData: Data) {
        self.groupThread = groupThread
        self.changeActionsProtoData = changeActionsProtoData
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

    public func fetchCurrentGroupState(groupModel: TSGroupModel) -> Promise<GroupV2State> {
        owsFail("Not implemented.")
    }

    public func fetchCurrentGroupState(groupSecretParamsData: Data) -> Promise<GroupV2State> {
        owsFail("Not implemented.")
    }

    public func fetchCurrentGroupStateObjc(groupModel: TSGroupModel) -> AnyPromise {
        owsFail("Not implemented.")
    }

    public func buildGroupContextV2Proto(groupModel: TSGroupModel,
                                         changeActionsProtoData: Data?) throws -> SSKProtoGroupContextV2 {
        owsFail("Not implemented.")
    }

    public func buildChangeSet(from oldGroupModel: TSGroupModel,
                               to newGroupModel: TSGroupModel,
                               transaction: SDSAnyReadTransaction) throws -> GroupsV2ChangeSet {
        owsFail("Not implemented.")
    }

    public func updateExistingGroupOnService(changeSet: GroupsV2ChangeSet) -> Promise<UpdatedV2Group> {
        owsFail("Not implemented.")
    }

    public func reuploadLocalProfilePromise() -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public func groupV2ContextInfo(forMasterKeyData masterKeyData: Data?) throws -> GroupV2ContextInfo {
        owsFail("Not implemented.")
    }

    public func fetchAndApplyGroupV2UpdatesFromService(groupId: Data,
                                                       groupSecretParamsData: Data,
                                                       upToRevision: UInt32,
                                                       waitForMessageProcessing: Bool) -> Promise<TSGroupThread> {
        owsFail("Not implemented.")
    }

    public func parseAndVerifyChangeActionsProto(_ changeProtoData: Data) throws -> GroupsProtoGroupChangeActions {
        owsFail("Not implemented.")
    }

    public func applyChangesToGroupModel(groupThread: TSGroupThread,
                                         changeActionsProto: GroupsProtoGroupChangeActions,
                                         changeActionsProtoData: Data,
                                         transaction: SDSAnyReadTransaction) throws -> ChangedGroupModel {
        owsFail("Not implemented.")
    }
}

// MARK: -

public class MockGroupUpdates: NSObject, GroupUpdates {
    public func tryToRefreshGroupThreadToLatestStateWithThrottling(_ thread: TSThread) {
        owsFail("Not implemented.")
    }

    public func updateGroupWithChangeActions(groupId: Data,
                                             changeActionsProto: GroupsProtoGroupChangeActions,
                                             changeActionsProtoData: Data,
                                             transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {
        owsFail("Not implemented.")
    }
}
