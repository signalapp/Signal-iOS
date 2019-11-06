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
            return ()
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
        let (promise, resolver) = Promise<Void>.pending()
        DispatchQueue.global().async {
            let message: TSOutgoingMessage = self.databaseStorage.writeReturningResult { transaction in
                return self.buildNewGroupMessage(forThread: thread, transaction: transaction)
            }

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
                self.messageSender.sendTemporaryAttachment(dataSource,
                                                           contentType: OWSMimeTypeImagePng,
                                                           in: message, success: {
                                                            resolver.fulfill(())
                }, failure: { error in
                    resolver.reject(error)
                })
            } else {
                // CLEANUP DURABLE - Replace with a durable operation e.g. `GroupCreateJob`, which creates
                // an error in the thread if group creation fails
                self.messageSender.sendMessage(message.asPreparer,
                                               success: {
                                                resolver.fulfill(())
                }, failure: { error in
                    resolver.reject(error)
                })
            }
        }
        return promise
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
