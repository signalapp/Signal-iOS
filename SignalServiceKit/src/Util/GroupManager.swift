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

    private class var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    private class var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    // MARK: -

    // Never instantiate this class.
    private override init() {}

    private static func buildGroupModel(groupId groupIdParam: Data?,
                                        name nameParam: String?,
                                        members membersParam: [SignalServiceAddress],
                                        avatarData: Data?,
                                        groupsVersion groupsVersionParam: GroupsVersion? = nil) throws -> TSGroupModel {

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
        var name: String?
        if let strippedName = nameParam?.stripped,
            strippedName.count > 0 {
            name = strippedName
        }
        let members = Array(Set(membersParam))
            .sorted(by: { (l, r) in l.compare(r) == .orderedAscending })
        let groupsVersion: GroupsVersion
        if let groupsVersionParam = groupsVersionParam {
            groupsVersion = groupsVersionParam
        } else {
            groupsVersion = self.groupsVersion(for: members)
        }
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

            let thread = databaseStorage.write { transaction in
                return TSGroupThread.getOrCreateThread(with: model, transaction: transaction)
            }

            return thread
        }
    }

    // success and failure are invoked on the main thread.
    @objc
    public static func createGroupObjc(members: [SignalServiceAddress],
                                       groupId: Data?,
                                       name: String,
                                       avatarImage: UIImage?,
                                       success: @escaping (TSGroupThread) -> Void,
                                       failure: @escaping (Error) -> Void) {
        createGroup(members: members,
                    groupId: groupId,
                    name: name,
                    avatarImage: avatarImage).done { thread in
                        success(thread)
            }.catch { error in
                failure(error)
            }.retainUntilComplete()
    }

    // success and failure are invoked on the main thread.
    @objc
    public static func createGroupObjc(members: [SignalServiceAddress],
                                       groupId: Data?,
                                       name: String,
                                       avatarData: Data?,
                                       success: @escaping (TSGroupThread) -> Void,
                                       failure: @escaping (Error) -> Void) {
        createGroup(members: members,
                    groupId: groupId,
                    name: name,
                    avatarData: avatarData).done { thread in
                        success(thread)
            }.catch { error in
                failure(error)
            }.retainUntilComplete()
    }

    // MARK: - Tests

    #if TESTABLE_BUILD

    public static func createGroupForTests(members: [SignalServiceAddress],
                                           name: String? = nil,
                                           avatarData: Data? = nil) throws -> TSGroupThread {

        return try databaseStorage.write { transaction in
            return try createGroupForTests(transaction: transaction,
                                           members: members,
                                           name: name,
                                           avatarData: avatarData)
        }
    }

    public static func createGroupForTests(transaction: SDSAnyWriteTransaction,
                                           members: [SignalServiceAddress],
                                           name: String? = nil,
                                           avatarData: Data? = nil,
                                           groupId: Data? = nil,
                                           groupsVersion: GroupsVersion? = nil) throws -> TSGroupThread {

        let model = try buildGroupModel(groupId: groupId, name: name, members: members, avatarData: avatarData, groupsVersion: groupsVersion)

        return TSGroupThread.getOrCreateThread(with: model, transaction: transaction)
    }

    @objc(createGroupForTestsObjcWithTransaction:members:name:avatarData:error:)
    public static func createGroupForTestsObjc(transaction: SDSAnyWriteTransaction,
                                               members: [SignalServiceAddress],
                                               name: String?,
                                               avatarData: Data?) throws -> TSGroupThread {

        return try createGroupForTests(transaction: transaction,
                                       members: members,
                                       name: name,
                                       avatarData: avatarData)
    }

    #endif

    // MARK: - Messages

    private static func buildNewGroupMessage(forThread thread: TSGroupThread,
                                             transaction: SDSAnyWriteTransaction) -> TSOutgoingMessage {
        let message = TSOutgoingMessage.init(in: thread, groupMetaMessage: .new, expiresInSeconds: 0)
        message.update(withCustomMessage: NSLocalizedString("GROUP_CREATED", comment: ""), transaction: transaction)
        return message
    }

    public static func sendDurableNewGroupMessage(forThread thread: TSGroupThread) -> Promise<Void> {
        assert(thread.groupModel.groupAvatarData == nil)

        return DispatchQueue.global().async(.promise) { () -> Void in
            self.databaseStorage.write { transaction in
                let message = self.buildNewGroupMessage(forThread: thread, transaction: transaction)
                self.messageSenderJobQueue.add(message: message.asPreparer,
                                               transaction: transaction)
            }
        }
    }

    // success and failure are invoked on the main thread.
    @objc
    public static func sendDurableNewGroupMessageObjc(forThread thread: TSGroupThread,
                                                      success: @escaping () -> Void,
                                                      failure: @escaping (Error) -> Void) {
        sendDurableNewGroupMessage(forThread: thread).done { _ in
            success()
            }.catch { error in
                failure(error)
            }.retainUntilComplete()
    }

    public static func sendTemporaryNewGroupMessage(forThread thread: TSGroupThread) -> Promise<Void> {
        return DispatchQueue.global().async(.promise) { () -> TSOutgoingMessage in
            return self.databaseStorage.write { transaction in
                return self.buildNewGroupMessage(forThread: thread, transaction: transaction)
            }
        }.then(on: DispatchQueue.global()) { (message: TSOutgoingMessage) -> Promise<Void> in
            let groupModel = thread.groupModel
            var dataSource: DataSource?
            if let groupAvatarData = groupModel.groupAvatarData,
                groupAvatarData.count > 0 {
                let imageData = (groupAvatarData as NSData).imageData(withPath: nil, mimeType: OWSMimeTypeImagePng)
                if imageData.isValid && imageData.imageFormat == .png {
                    dataSource = DataSourceValue.dataSource(with: groupAvatarData, fileExtension: "png")
                    assert(dataSource != nil)
                } else {
                    owsFailDebug("Avatar is not a valid PNG.")
                }
            }

            if let dataSource = dataSource {
                // CLEANUP DURABLE - Replace with a durable operation e.g. `GroupCreateJob`, which creates
                // an error in the thread if group creation fails
                return self.messageSender.sendTemporaryAttachment(.promise,
                                                                  dataSource: dataSource,
                                                                  contentType: OWSMimeTypeImagePng,
                                                                  message: message)
            } else {
                // CLEANUP DURABLE - Replace with a durable operation e.g. `GroupCreateJob`, which creates
                // an error in the thread if group creation fails
                return self.messageSender.sendMessage(.promise, message.asPreparer)
            }
        }
    }

    // success and failure are invoked on the main thread.
    @objc
    public static func sendTemporaryNewGroupMessageObjc(forThread thread: TSGroupThread,
                                                        success: @escaping () -> Void,
                                                        failure: @escaping (Error) -> Void) {
        sendTemporaryNewGroupMessage(forThread: thread).done { _ in
            success()
            }.catch { error in
                failure(error)
            }.retainUntilComplete()
    }
}
