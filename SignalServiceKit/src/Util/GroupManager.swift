//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class GroupManager: NSObject {

    // MARK: - Dependencies

//    private class var networkManager: TSNetworkManager {
//        return SSKEnvironment.shared.networkManager
//    }
//
//    private class var messageReceiver: OWSMessageReceiver {
//        return SSKEnvironment.shared.messageReceiver
//    }
//
//    private class var signalService: OWSSignalService {
//        return OWSSignalService.sharedInstance()
//    }

    private class var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    // Never instantiate this class.
    private override init() {}

    private static func buildGroupModel(groupId: Data,
                                        name nameParam: String,
                                        recipientAddresses recipientAddressesParam: [SignalServiceAddress],
                                        avatarData: Data?) throws -> TSGroupModel {
        guard groupId.count == kGroupIdLength else {
            throw OWSErrorMakeAssertionError("Invalid groupId.")
        }
        for recipientAddress in recipientAddressesParam {
            guard recipientAddress.isValid else {
                throw OWSErrorMakeAssertionError("Invalid address.")
            }
        }
        guard let localAddress = tsAccountManager.localAddress else {
            throw OWSErrorMakeAssertionError("Missing localAddress.")
        }
        let name = nameParam.stripped
        let recipientAddresses = Array(Set(recipientAddressesParam + [localAddress]))
            .sorted(by: { (l, r) in l.compare(r) == .orderedAscending })
        let groupsVersion = self.groupsVersion(for: recipientAddresses)
        return TSGroupModel(groupId: groupId, name: name, avatarData: avatarData, members: recipientAddresses, groupsVersion: groupsVersion)
    }

    private static func groupsVersion(for recipientAddresses: [SignalServiceAddress]) -> GroupsVersion {
        guard FeatureFlags.tryToCreateGroupsV2 else {
            return .groupsV1
        }
        for recipientAddress in recipientAddresses {
            guard recipientAddress.uuid != nil else {
                Logger.warn("Creating legacy group; member without UUID.")
                return .groupsV1
            }
            // TODO: Check whether recipient supports Groups v2.
        }

        // TODO:
        return .groupsV2
    }

    // TODO: Return promise.
    @objc
    public static func createGroup(groupId: Data?,
                                   name: String,
                                   recipientAddresses: [SignalServiceAddress],
                                   avatarImage: UIImage?) throws -> TSGroupThread {
        AssertIsOnMainThread()

        let avatarData = TSGroupModel.data(forGroupAvatar: avatarImage)

        return try createGroup(groupId: groupId,
                               name: name,
                               recipientAddresses: recipientAddresses,
                               avatarData: avatarData)
    }

    // TODO: Return promise.
    @objc
    public static func createGroup(groupId groupIdParam: Data?,
                                   name: String,
                                   recipientAddresses: [SignalServiceAddress],
                                   avatarData: Data? = nil) throws -> TSGroupThread {
        AssertIsOnMainThread()

        let groupId: Data
        if let groupIdParam = groupIdParam {
            groupId = groupIdParam
        } else {
            groupId = TSGroupModel.generateRandomGroupId()
        }

        let model = try buildGroupModel(groupId: groupId, name: name, recipientAddresses: recipientAddresses, avatarData: avatarData)

        let thread = databaseStorage.writeReturningResult { _ in
            return TSGroupThread.getOrCreateThread(with: model)
        }

        return thread
    }
}
