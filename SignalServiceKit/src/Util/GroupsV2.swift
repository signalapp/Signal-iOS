//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public protocol GroupsV2: AnyObject {
    func createNewGroupOnServiceObjc(groupModel: TSGroupModel) -> AnyPromise

    func generateGroupSecretParamsData() throws -> Data

    func hasProfileKeyCredential(for address: SignalServiceAddress,
                                 transaction: SDSAnyReadTransaction) -> Bool

    func tryToEnsureProfileKeyCredentialsObjc(for addresses: [SignalServiceAddress]) -> AnyPromise

    func fetchGroupStateObjc(groupModel: TSGroupModel) -> AnyPromise
}

// MARK: -

public protocol GroupsV2Swift {
    func fetchGroupState(groupModel: TSGroupModel) -> Promise<GroupV2State>
}

// MARK: -

public protocol GroupV2State {
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

public class MockGroupsV2: NSObject, GroupsV2, GroupsV2Swift {
    public func createNewGroupOnServiceObjc(groupModel: TSGroupModel) -> AnyPromise {
        owsFail("Not implemented.")
    }

    public func generateGroupSecretParamsData() throws -> Data {
        owsFail("Not implemented.")
    }

    public func hasProfileKeyCredential(for address: SignalServiceAddress,
                                        transaction: SDSAnyReadTransaction) -> Bool {
        owsFail("Not implemented.")
    }

    public func tryToEnsureProfileKeyCredentialsObjc(for addresses: [SignalServiceAddress]) -> AnyPromise {
        owsFail("Not implemented.")
    }

    public func fetchGroupState(groupModel: TSGroupModel) -> Promise<GroupV2State> {
        owsFail("Not implemented.")
    }

    public func fetchGroupStateObjc(groupModel: TSGroupModel) -> AnyPromise {
        owsFail("Not implemented.")
    }
}
