//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public protocol GroupsV2: AnyObject {

    func createNewGroupOnServiceObjc(groupModel: TSGroupModel) -> AnyPromise

    func generateGroupSecretParamsData() throws -> Data

    func groupId(forGroupSecretParamsData groupSecretParamsData: Data) throws -> Data

    func hasProfileKeyCredential(for address: SignalServiceAddress,
                                 transaction: SDSAnyReadTransaction) -> Bool

    func tryToEnsureProfileKeyCredentialsObjc(for addresses: [SignalServiceAddress]) -> AnyPromise

    func fetchGroupStateObjc(groupModel: TSGroupModel) -> AnyPromise

    func buildGroupContextV2Proto(groupModel: TSGroupModel,
                                  groupChangeData: Data?) throws -> SSKProtoGroupContextV2

    func groupV2ContextInfo(forMasterKeyData masterKeyData: Data?) throws -> GroupV2ContextInfo

    func fetchAndApplyGroupV2UpdatesFromServiceObjc(groupId: Data,
                                                    groupSecretParamsData: Data,
                                                    upToRevision: UInt32) -> AnyPromise
}

// MARK: -

public protocol GroupsV2Swift {
    func createNewGroupOnService(groupModel: TSGroupModel) -> Promise<Void>

    func tryToEnsureProfileKeyCredentials(for addresses: [SignalServiceAddress]) -> Promise<Void>

    func fetchGroupState(groupModel: TSGroupModel) -> Promise<GroupV2State>

    func buildChangeSet(from oldGroupModel: TSGroupModel,
    to newGroupModel: TSGroupModel) throws -> GroupsV2ChangeSet

    func updateExistingGroupOnService(changeSet: GroupsV2ChangeSet) -> Promise<Void>

    func reuploadLocalProfilePromise() -> Promise<Void>
}

// MARK: -

public protocol GroupsV2ChangeSet: AnyObject {
    var groupId: Data { get }
    var groupSecretParamsData: Data { get }

    func buildGroupChangeProto(currentGroupModel: TSGroupModel) -> Promise<GroupsProtoGroupChangeActions>
}

// MARK: -

public protocol GroupV2State {
    var groupSecretParamsData: Data { get }

    var debugDescription: String { get }

    var version: UInt32 { get }

    var title: String { get }

    // GroupsV2 TODO: Avatar.
    // GroupsV2 TODO: DM state.

    // Includes all roles: adminstrators and "default" members.
    var activeMembers: [SignalServiceAddress] { get }
    var administrators: [SignalServiceAddress] { get }

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

    public func fetchGroupState(groupModel: TSGroupModel) -> Promise<GroupV2State> {
        owsFail("Not implemented.")
    }

    public func fetchGroupStateObjc(groupModel: TSGroupModel) -> AnyPromise {
        owsFail("Not implemented.")
    }

    public func buildGroupContextV2Proto(groupModel: TSGroupModel,
                                         groupChangeData: Data?) throws -> SSKProtoGroupContextV2 {
        owsFail("Not implemented.")
    }

    public func buildChangeSet(from oldGroupModel: TSGroupModel,
    to newGroupModel: TSGroupModel) throws -> GroupsV2ChangeSet {
        owsFail("Not implemented.")
    }

    public func updateExistingGroupOnService(changeSet: GroupsV2ChangeSet) -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public func reuploadLocalProfilePromise() -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public func groupV2ContextInfo(forMasterKeyData masterKeyData: Data?) throws -> GroupV2ContextInfo {
        owsFail("Not implemented.")
    }

    public func fetchAndApplyGroupV2UpdatesFromServiceObjc(groupId: Data,
                                                           groupSecretParamsData: Data,
                                                           upToRevision: UInt32) -> AnyPromise {
        owsFail("Not implemented.")
    }
}
