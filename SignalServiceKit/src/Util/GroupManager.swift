//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class EnsureGroupResult: NSObject {
    @objc
    public enum Action: UInt {
        case inserted
        case updated
        case unchanged
    }

    @objc
    public let action: Action

    @objc
    public let thread: TSGroupThread

    public required init(action: Action, thread: TSGroupThread) {
        self.action = action
        self.thread = thread
    }
}

// MARK: -

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

    private class var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
    }

    private class var contactsManager: ContactsManagerProtocol {
        return SSKEnvironment.shared.contactsManager
    }

    // MARK: -

    // Never instantiate this class.
    private override init() {}

    // MARK: - Create New Group
    //
    // "New" groups are being created for the first time; they might need to be created on the service.

    private static func buildGroupModel(groupId groupIdParam: Data?,
                                        name nameParam: String?,
                                        members membersParam: [SignalServiceAddress],
                                        avatarData: Data?,
                                        groupsVersion groupsVersionParam: GroupsVersion? = nil,
                                        groupSecretParamsData groupSecretParamsDataParam: Data? = nil,
                                        isCreating: Bool = false) throws -> TSGroupModel {

        let groupId: Data
        if let groupIdParam = groupIdParam {
            groupId = groupIdParam
        } else {
            groupId = TSGroupModel.generateRandomGroupId()
        }
        guard groupId.count == kGroupIdLength else {
            throw OWSAssertionError("Invalid groupId.")
        }
        for recipientAddress in membersParam {
            guard recipientAddress.isValid else {
                throw OWSAssertionError("Invalid address.")
            }
        }
        var name: String?
        if let strippedName = nameParam?.stripped,
            strippedName.count > 0 {
            name = strippedName
        }

        // We de-duplicate our member set.
        let members = Array(Set(membersParam))
            .sorted(by: { (l, r) in l.compare(r) == .orderedAscending })
        let groupsVersion: GroupsVersion
        if let groupsVersionParam = groupsVersionParam {
            groupsVersion = groupsVersionParam
        } else {
            groupsVersion = self.groupsVersion(for: members)
        }

        var groupSecretParamsData: Data?
        if groupsVersion == .V2 {
            if isCreating {
                assert(groupSecretParamsDataParam == nil)
                groupSecretParamsData = try groupsV2.generateGroupSecretParamsData()
            } else {
                groupSecretParamsData = groupSecretParamsDataParam
                guard groupSecretParamsData != nil else {
                    throw OWSAssertionError("Missing or invalid groupSecretParamsData.")
                }
            }
        }

        return TSGroupModel(groupId: groupId,
                            name: name,
                            avatarData: avatarData,
                            members: members,
                            groupsVersion: groupsVersion,
                            groupSecretParamsData: groupSecretParamsData)
    }

    private static func groupsVersion(for members: [SignalServiceAddress]) -> GroupsVersion {
        for recipientAddress in members {
            guard recipientAddress.uuid != nil else {
                Logger.warn("Creating legacy group; member without UUID.")
                return .V1
            }
            // GroupsV2 TODO: Check whether recipient supports Groups v2.
        }
        return defaultGroupsVersion
    }

    @objc
    public static var defaultGroupsVersion: GroupsVersion {
        guard FeatureFlags.tryToCreateNewGroupsV2 else {
            return .V1
        }
        return .V2
    }

    public static func createNewGroup(members: [SignalServiceAddress],
                                      groupId: Data? = nil,
                                      name: String? = nil,
                                      avatarImage: UIImage?) -> Promise<TSGroupThread> {

        return DispatchQueue.global().async(.promise) {
            return TSGroupModel.data(forGroupAvatar: avatarImage)
            }.then(on: .global()) { avatarData in
                return createNewGroup(members: members,
                                      groupId: groupId,
                                      name: name,
                                      avatarData: avatarData)
        }
    }

    public static func createNewGroup(members: [SignalServiceAddress],
                                      groupId: Data? = nil,
                                      name: String? = nil,
                                      avatarData: Data? = nil) -> Promise<TSGroupThread> {

        return DispatchQueue.global().async(.promise) {
            return try buildGroupModel(groupId: groupId, name: name, members: members, avatarData: avatarData, isCreating: true)
            }.then(on: .global()) { groupModel in
                return self.createNewGroupOnServiceIfNecessary(groupModel: groupModel)
            }.map(on: .global()) { groupModel in
                let thread = databaseStorage.write { transaction in
                    return TSGroupThread.getOrCreateThread(with: groupModel, transaction: transaction)
                }

                return thread
        }
    }

    private static func createNewGroupOnServiceIfNecessary(groupModel: TSGroupModel) -> Promise<TSGroupModel> {
        guard groupModel.groupsVersion == .V2 else {
            return Promise.value(groupModel)
        }
        return groupsV2.createNewGroupV2OnService(groupModel: groupModel)
            .map(on: .global()) { _ in
                return groupModel
        }
    }

    // success and failure are invoked on the main thread.
    @objc
    public static func createNewGroupObjc(members: [SignalServiceAddress],
                                          groupId: Data?,
                                          name: String,
                                          avatarImage: UIImage?,
                                          success: @escaping (TSGroupThread) -> Void,
                                          failure: @escaping (Error) -> Void) {
        createNewGroup(members: members,
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
    public static func createNewGroupObjc(members: [SignalServiceAddress],
                                          groupId: Data?,
                                          name: String,
                                          avatarData: Data?,
                                          success: @escaping (TSGroupThread) -> Void,
                                          failure: @escaping (Error) -> Void) {
        createNewGroup(members: members,
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

    @objc
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

    @objc
    public static func createGroupForTestsObjc(transaction: SDSAnyWriteTransaction,
                                               members: [SignalServiceAddress],
                                               name: String? = nil,
                                               avatarData: Data? = nil) throws -> TSGroupThread {
        let groupsVersion = self.defaultGroupsVersion
        return try createGroupForTests(transaction: transaction,
                                       members: members,
                                       name: name,
                                       avatarData: avatarData,
                                       groupsVersion: groupsVersion)
    }

    public static func createGroupForTests(transaction: SDSAnyWriteTransaction,
                                           members: [SignalServiceAddress],
                                           name: String? = nil,
                                           avatarData: Data? = nil,
                                           groupId: Data? = nil,
                                           groupsVersion: GroupsVersion? = nil) throws -> TSGroupThread {

        // Use buildGroupModel() to fill in defaults, like it was a new group.
        let model = try buildGroupModel(groupId: groupId, name: name, members: members, avatarData: avatarData, groupsVersion: groupsVersion)

        // But just create it in the database, don't create it on the service.
        return try ensureExistingGroup(transaction: transaction,
                                       members: model.groupMembers,
                                       name: model.groupName,
                                       avatarData: model.groupAvatarData,
                                       groupId: model.groupId,
                                       groupsVersion: model.groupsVersion,
                                       groupSecretParamsData: model.groupSecretParamsData).thread
    }

    #endif

    // MARK: - Ensure Existing Group
    //
    // "Existing" groups have already been created, we just need to make sure they're in the database.

    public static func ensureExistingGroup(transaction: SDSAnyWriteTransaction,
                                           members: [SignalServiceAddress],
                                           name: String? = nil,
                                           avatarData: Data? = nil,
                                           groupId: Data,
                                           groupsVersion: GroupsVersion,
                                           groupSecretParamsData: Data? = nil) throws -> EnsureGroupResult {

        let groupModel = try buildGroupModel(groupId: groupId,
                                             name: name,
                                             members: members,
                                             avatarData: avatarData,
                                             groupsVersion: groupsVersion,
                                             groupSecretParamsData: groupSecretParamsData)

        if let thread = TSGroupThread.getWithGroupId(groupId, transaction: transaction) {
            guard !groupModel.isEqual(to: thread.groupModel) else {
                return EnsureGroupResult(action: .unchanged, thread: thread)
            }
            let updatedThread = try updateExistingGroup(groupId: groupId,
                                                        members: members,
                                                        name: name,
                                                        avatarData: avatarData,
                                                        shouldSendMessage: true,
                                                        transaction: transaction)
            return EnsureGroupResult(action: .updated, thread: updatedThread)
        } else {
            let thread = TSGroupThread(groupModel: groupModel)
            thread.anyInsert(transaction: transaction)
            return EnsureGroupResult(action: .inserted, thread: thread)
        }
    }

    @objc(ensureExistingGroupObjcWithTransaction:members:name:avatarData:groupId:groupsVersion:groupSecretParamsData:error:)
    public static func ensureExistingGroupObjc(transaction: SDSAnyWriteTransaction,
                                               members: [SignalServiceAddress],
                                               name: String?,
                                               avatarData: Data?,
                                               groupId: Data,
                                               groupsVersion: GroupsVersion,
                                               groupSecretParamsData: Data? = nil) throws -> EnsureGroupResult {

        return try ensureExistingGroup(transaction: transaction,
                                       members: members,
                                       name: name,
                                       avatarData: avatarData,
                                       groupId: groupId,
                                       groupsVersion: groupsVersion,
                                       groupSecretParamsData: groupSecretParamsData)
    }

    // MARK: - Update Existing Group

    @objc
    public static func updateExistingGroup(groupId: Data,
                                           members membersParam: [SignalServiceAddress],
                                           name: String? = nil,
                                           avatarData: Data? = nil,
                                           shouldSendMessage: Bool,
                                           transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {

        // Always ensure we're a member of any group we're updating.
        guard let localAddress = self.tsAccountManager.localAddress else {
            throw OWSAssertionError("Missing localAddress.")
        }
        let members: [SignalServiceAddress] = membersParam + [localAddress]

        guard let thread = TSGroupThread.getWithGroupId(groupId, transaction: transaction) else {
            throw OWSAssertionError("Thread does not exist.")
        }
        let oldGroupModel = thread.groupModel
        guard oldGroupModel.groupId.count > 0 else {
            throw OWSAssertionError("Missing or invalid group id.")
        }
        let newGroupModel = try buildGroupModel(groupId: oldGroupModel.groupId,
                                                name: name,
                                                members: members,
                                                avatarData: avatarData,
                                                groupsVersion: oldGroupModel.groupsVersion,
                                                groupSecretParamsData: oldGroupModel.groupSecretParamsData)
        if oldGroupModel.isEqual(to: newGroupModel) {
            // Skip redundant update.
            return thread
        }

        thread.update(with: newGroupModel, transaction: transaction)

        if shouldSendMessage {
            self.sendGroupUpdateMessage(thread: thread,
                                        oldGroupModel: oldGroupModel,
                                        newGroupModel: newGroupModel,
                                        transaction: transaction).retainUntilComplete()
        }

        return thread
    }

    @objc
    public static func sendGroupUpdateMessageObjc(thread: TSGroupThread,
                                                  oldGroupModel: TSGroupModel,
                                                  newGroupModel: TSGroupModel,
                                                  transaction: SDSAnyWriteTransaction) -> AnyPromise {
        return AnyPromise(self.sendGroupUpdateMessage(thread: thread,
                                                     oldGroupModel: oldGroupModel,
                                                     newGroupModel: newGroupModel,
                                                     transaction: transaction))
    }

    public static func sendGroupUpdateMessage(thread: TSGroupThread,
                                              oldGroupModel: TSGroupModel,
                                              newGroupModel: TSGroupModel,
                                              transaction: SDSAnyWriteTransaction) -> Promise<Void> {
        let updateDescription = oldGroupModel.getInfoStringAboutUpdate(to: newGroupModel, contactsManager: self.contactsManager)

        // GroupsV2 TODO: This behavior will change for v2 groups.
        let expiresInSeconds = thread.disappearingMessagesDuration(with: transaction)
        let message = TSOutgoingMessage(in: thread,
                                        groupMetaMessage: .update,
                                        expiresInSeconds: expiresInSeconds)
        message.update(withCustomMessage: updateDescription, transaction: transaction)

        if let avatarData = newGroupModel.groupAvatarData,
            avatarData.count > 0 {
            if let dataSource = DataSourceValue.dataSource(with: avatarData, fileExtension: "png") {

                // DURABLE CLEANUP - currently one caller uses the completion handler to delete the tappable error message
                // which causes this code to be called. Once we're more aggressive about durable sending retry,
                // we could get rid of this "retryable tappable error message".
                return self.messageSender.sendTemporaryAttachment(.promise,
                                                                  dataSource: dataSource,
                                                                  contentType: OWSMimeTypeImagePng,
                                                                  message: message)
                    .done(on: .global()) { _ in
                        Logger.debug("Successfully sent group update with avatar")
                    }.recover(on: .global()) { error in
                        owsFailDebug("Failed to send group avatar update with error: \(error)")
                        throw error
                }
            }
        }

        // DURABLE CLEANUP - currently one caller uses the completion handler to delete the tappable error message
        // which causes this code to be called. Once we're more aggressive about durable sending retry,
        // we could get rid of this "retryable tappable error message".
        return self.messageSender.sendMessage(.promise, message.asPreparer)
            .done(on: .global()) { _ in
                Logger.debug("Successfully sent group update")
            }.recover(on: .global()) { error in
                owsFailDebug("Failed to send group update with error: \(error)")
                throw error
        }
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
