//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class GroupManager: NSObject {

    // MARK: - Dependencies

    private class var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    // Never instantiate this class.
    private override init() {}

    private static func buildGroupModel(groupId groupIdParam: Data?,
                                        name nameParam: String?,
                                        members membersParam: [SignalServiceAddress],
                                        avatarData: Data?) throws -> TSGroupModel {

        let groupId: Data
        if let groupIdParam = groupIdParam {
            groupId = groupIdParam
        } else {
            groupId = TSGroupModel.generateRandomGroupId()
        }
        guard groupId.count == kGroupIdLength else {
            throw OWSErrorMakeAssertionError("Invalid groupId.")
        }
        for recipientAddress in membersParam {
            guard recipientAddress.isValid else {
                throw OWSErrorMakeAssertionError("Invalid address.")
            }
        }
        guard let localAddress = tsAccountManager.localAddress else {
            throw OWSErrorMakeAssertionError("Missing localAddress.")
        }
        var name: String?
        if let strippedName = nameParam?.stripped,
            strippedName.count > 0 {
            name = strippedName
        }
        let members = Array(Set(membersParam + [localAddress]))
            .sorted(by: { (l, r) in l.compare(r) == .orderedAscending })
        let groupsVersion = self.groupsVersion(for: members)
        return TSGroupModel(groupId: groupId, name: name, avatarData: avatarData, members: members, groupsVersion: groupsVersion)
    }

    private static func groupsVersion(for members: [SignalServiceAddress]) -> GroupsVersion {
        for recipientAddress in members {
            guard recipientAddress.uuid != nil else {
                Logger.warn("Creating legacy group; member without UUID.")
                return .V1
            }
            // TODO: Check whether recipient supports Groups v2.
        }
        return defaultGroupsVersion
    }

    @objc
    public static var defaultGroupsVersion: GroupsVersion {
        guard FeatureFlags.tryToCreateGroupsV2 else {
            return .V1
        }
        return .V2
    }

    public static func createGroup(members: [SignalServiceAddress],
                                   groupId: Data? = nil,
                                   name: String? = nil,
                                   avatarImage: UIImage?) -> Promise<TSGroupThread> {

        return DispatchQueue.global().async(.promise) {
            return TSGroupModel.data(forGroupAvatar: avatarImage)
            }.then(on: .global()) { avatarData in
                return createGroup(members: members,
                                   groupId: groupId,
                                   name: name,
                                   avatarData: avatarData)
        }
    }

    public static func createGroup(members: [SignalServiceAddress],
                                   groupId: Data? = nil,
                                   name: String? = nil,
                                   avatarData: Data? = nil) -> Promise<TSGroupThread> {

        return DispatchQueue.global().async(.promise) {
            let model = try buildGroupModel(groupId: groupId, name: name, members: members, avatarData: avatarData)

            let thread = databaseStorage.writeReturningResult { _ in
                return TSGroupThread.getOrCreateThread(with: model)
            }

            return thread
        }
    }

    // Completion will be called on the main thread.
    @objc
    public static func createGroupObjc(members: [SignalServiceAddress],
                                       groupId: Data?,
                                       name: String,
                                       avatarImage: UIImage?,
                                       completion: @escaping (TSGroupThread) -> Void) {
        createGroup(members: members,
                    groupId: groupId,
                    name: name,
                    avatarImage: avatarImage).done { thread in
                        completion(thread)
            }.retainUntilComplete()
    }

    // Completion will be called on the main thread.
    @objc
    public static func createGroupObjc(members: [SignalServiceAddress],
                                       groupId: Data?,
                                       name: String,
                                       avatarData: Data?,
                                       completion: @escaping (TSGroupThread) -> Void) {
        createGroup(members: members,
                    groupId: groupId,
                    name: name,
                    avatarData: avatarData).done { thread in
                        completion(thread)
            }.retainUntilComplete()
    }
}
