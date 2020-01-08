//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

    private class var profileManager: ProfileManagerProtocol {
        return SSKEnvironment.shared.profileManager
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

    // This should only be used for certain legacy edge cases.
    @objc
    public static func fakeGroupModel(groupId: Data?) -> TSGroupModel? {
        do {
            return try buildGroupModel(groupId: groupId,
                                       name: nil,
                                       members: [],
                                       avatarData: nil,
                                       groupsVersion: .V1,
                                       groupSecretParamsData: nil)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    private static func groupsVersion(for members: [SignalServiceAddress]) -> GroupsVersion {

        let canUseV2: Bool = databaseStorage.read { transaction in
            for recipientAddress in members {
                guard let uuid = recipientAddress.uuid else {
                    Logger.warn("Creating legacy group; member without UUID.")
                    return false
                }
                let address = SignalServiceAddress(uuid: uuid, phoneNumber: nil)
                let hasCredential = self.groupsV2.hasProfileKeyCredential(for: address,
                                                                          transaction: transaction)
                guard hasCredential else {
                    Logger.warn("Creating legacy group; member missing credential.")
                    return false
                }
                // GroupsV2 TODO: Check capability.
            }
            return true
        }
        return canUseV2 ? defaultGroupsVersion : .V1
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
                                      avatarImage: UIImage?,
                                      shouldSendMessage: Bool) -> Promise<TSGroupThread> {

        return DispatchQueue.global().async(.promise) {
            return TSGroupModel.data(forGroupAvatar: avatarImage)
            }.then(on: .global()) { avatarData in
                return createNewGroup(members: members,
                                      groupId: groupId,
                                      name: name,
                                      avatarData: avatarData,
                                      shouldSendMessage: shouldSendMessage)
        }
    }

    public static func createNewGroup(members membersParam: [SignalServiceAddress],
                                      groupId: Data? = nil,
                                      name: String? = nil,
                                      avatarData: Data? = nil,
                                      shouldSendMessage: Bool) -> Promise<TSGroupThread> {

        return DispatchQueue.global().async(.promise) {
            guard let localAddress = self.tsAccountManager.localAddress else {
                throw OWSAssertionError("Missing localAddress.")
            }
            let members: [SignalServiceAddress] = membersParam + [localAddress]
            return members
            }.then(on: .global()) { (members: [SignalServiceAddress]) -> Promise<[SignalServiceAddress]> in
                guard FeatureFlags.tryToCreateNewGroupsV2 else {
                    return Promise.value(members)
                }
                return self.groupsV2.tryToEnsureProfileKeyCredentialsObjc(for: members)
                    .map(on: .global()) { (_) -> [SignalServiceAddress] in
                        return members
                }
            }.map(on: .global()) { (members: [SignalServiceAddress]) throws -> TSGroupModel in
                return try self.buildGroupModel(groupId: groupId, name: name, members: members, avatarData: avatarData, isCreating: true)
            }
            .then(on: .global()) { (groupModel: TSGroupModel) -> Promise<TSGroupModel> in
                return self.createNewGroupOnServiceIfNecessary(groupModel: groupModel)
            }.map(on: .global()) { (groupModel: TSGroupModel) -> TSGroupThread in
                let thread = databaseStorage.write { (transaction: SDSAnyWriteTransaction) -> TSGroupThread in
                    if let thread = TSGroupThread.fetch(groupId: groupModel.groupId, transaction: transaction) {
                        thread.update(with: groupModel, transaction: transaction)
                        return thread
                    } else {
                        let thread = TSGroupThread(groupModelPrivate: groupModel)
                        thread.anyInsert(transaction: transaction)
                        return thread
                    }
                }
                return thread
            }.then(on: .global()) { (thread: TSGroupThread) -> Promise<TSGroupThread> in
                self.profileManager.addThread(toProfileWhitelist: thread)

                if shouldSendMessage {
                    return sendDurableNewGroupMessage(forThread: thread)
                        .map(on: .global()) { _ in
                            return thread
                    }
                } else {
                    return Promise.value(thread)
                }
        }
    }

    private static func createNewGroupOnServiceIfNecessary(groupModel: TSGroupModel) -> Promise<TSGroupModel> {
        guard groupModel.groupsVersion == .V2 else {
            return Promise.value(groupModel)
        }
        return groupsV2.createNewGroupOnServiceObjc(groupModel: groupModel)
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
                                          shouldSendMessage: Bool,
                                          success: @escaping (TSGroupThread) -> Void,
                                          failure: @escaping (Error) -> Void) {
        createNewGroup(members: members,
                       groupId: groupId,
                       name: name,
                       avatarImage: avatarImage,
                       shouldSendMessage: shouldSendMessage).done { thread in
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
                                          shouldSendMessage: Bool,
                                          success: @escaping (TSGroupThread) -> Void,
                                          failure: @escaping (Error) -> Void) {
        createNewGroup(members: members,
                       groupId: groupId,
                       name: name,
                       avatarData: avatarData,
                       shouldSendMessage: shouldSendMessage).done { thread in
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
            return try createGroupForTests(members: members,
                                           name: name,
                                           avatarData: avatarData,
                                           transaction: transaction)
        }
    }

    @objc
    public static func createGroupForTestsObjc(members: [SignalServiceAddress],
                                               name: String? = nil,
                                               avatarData: Data? = nil,
                                               transaction: SDSAnyWriteTransaction) -> TSGroupThread {
        do {
            let groupsVersion = self.defaultGroupsVersion
            return try createGroupForTests(members: members,
                                           name: name,
                                           avatarData: avatarData,
                                           groupsVersion: groupsVersion,
                                           transaction: transaction)
        } catch {
            owsFail("Error: \(error)")
        }
    }

    public static func createGroupForTests(members: [SignalServiceAddress],
                                           name: String? = nil,
                                           avatarData: Data? = nil,
                                           groupId: Data? = nil,
                                           groupsVersion: GroupsVersion? = nil,
                                           transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {

        // Use buildGroupModel() to fill in defaults, like it was a new group.
        let model = try buildGroupModel(groupId: groupId, name: name, members: members, avatarData: avatarData, groupsVersion: groupsVersion)

        // But just create it in the database, don't create it on the service.
        return try upsertExistingGroup(members: model.groupMembers,
                                       name: model.groupName,
                                       avatarData: model.groupAvatarData,
                                       groupId: model.groupId,
                                       groupsVersion: model.groupsVersion,
                                       groupSecretParamsData: model.groupSecretParamsData,
                                       shouldSendMessage: false,
                                       transaction: transaction).thread
    }

    #endif

    // MARK: - Upsert Existing Group
    //
    // "Existing" groups have already been created, we just need to make sure they're in the database.

    @objc(upsertExistingGroupWithMembers:name:avatarData:groupId:groupsVersion:groupSecretParamsData:shouldSendMessage:transaction:error:)
    public static func upsertExistingGroup(members: [SignalServiceAddress],
                                           name: String? = nil,
                                           avatarData: Data? = nil,
                                           groupId: Data,
                                           groupsVersion: GroupsVersion,
                                           groupSecretParamsData: Data? = nil,
                                           shouldSendMessage: Bool,
                                           transaction: SDSAnyWriteTransaction) throws -> EnsureGroupResult {

        // GroupsV2 TODO: Audit all callers too see if they should include local uuid.

        let groupModel = try buildGroupModel(groupId: groupId,
                                             name: name,
                                             members: members,
                                             avatarData: avatarData,
                                             groupsVersion: groupsVersion,
                                             groupSecretParamsData: groupSecretParamsData)

        if let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
            guard !groupModel.isEqual(to: thread.groupModel) else {
                return EnsureGroupResult(action: .unchanged, thread: thread)
            }
            let updatedThread = try updateExistingGroup(groupId: groupId,
                                                        members: members,
                                                        name: name,
                                                        avatarData: avatarData,
                                                        shouldSendMessage: shouldSendMessage,
                                                        transaction: transaction)
            return EnsureGroupResult(action: .updated, thread: updatedThread)
        } else {
            let thread = TSGroupThread(groupModelPrivate: groupModel)
            thread.anyInsert(transaction: transaction)
            return EnsureGroupResult(action: .inserted, thread: thread)
        }
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

        guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
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

    private static func sendDurableNewGroupMessage(forThread thread: TSGroupThread) -> Promise<Void> {
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
    private static func sendDurableNewGroupMessageObjc(forThread thread: TSGroupThread,
                                                       success: @escaping () -> Void,
                                                       failure: @escaping (Error) -> Void) {
        sendDurableNewGroupMessage(forThread: thread).done { _ in
            success()
            }.catch { error in
                failure(error)
            }.retainUntilComplete()
    }
}

// MARK: -

// GroupsV2 TODO: Convert this extension into tests.
@objc
public extension GroupManager {
    static func testGroupsV2Functionality() {
        guard !FeatureFlags.isUsingProductionService,
            FeatureFlags.tryToCreateNewGroupsV2,
            FeatureFlags.versionedProfiledFetches,
            FeatureFlags.versionedProfiledUpdate else {
                owsFailDebug("Incorrect feature flags.")
                return
        }
        let members = [SignalServiceAddress]()
        let title0 = "hello"
        guard let localUuid = self.tsAccountManager.localUuid else {
            owsFailDebug("Missing localUuid.")
            return
        }
        createNewGroup(members: members,
                       name: title0,
                       shouldSendMessage: true)
            .then(on: .global()) { (groupThread: TSGroupThread) -> Promise<GroupV2State> in
                let groupModel = groupThread.groupModel
                guard groupModel.groupsVersion == .V2 else {
                    throw OWSAssertionError("Not a V2 group.")
                }
                guard let groupsV2Swift = self.groupsV2 as? GroupsV2Swift else {
                    throw OWSAssertionError("Invalid groupsV2 instance.")
                }
                return groupsV2Swift.fetchGroupState(groupModel: groupModel)
            }.done { (groupV2State: GroupV2State) -> Void in
                guard groupV2State.version == 0 else {
                    throw OWSAssertionError("Unexpected group version: \(groupV2State.version).")
                }
                guard groupV2State.title == title0 else {
                    throw OWSAssertionError("Unexpected group title: \(groupV2State.title).")
                }
                let expectedMembers = [SignalServiceAddress(uuid: localUuid, phoneNumber: nil)]
                guard groupV2State.activeMembers == expectedMembers else {
                    throw OWSAssertionError("Unexpected members: \(groupV2State.activeMembers).")
                }
                let expectedAdministrators = expectedMembers
                guard groupV2State.administrators == expectedAdministrators else {
                    throw OWSAssertionError("Unexpected administrators: \(groupV2State.administrators).")
                }
                guard groupV2State.accessControlForMembers == .member else {
                    throw OWSAssertionError("Unexpected accessControlForMembers: \(groupV2State.accessControlForMembers).")
                }
                guard groupV2State.accessControlForAttributes == .member else {
                    throw OWSAssertionError("Unexpected accessControlForAttributes: \(groupV2State.accessControlForAttributes).")
                }
                Logger.info("---- Success.")
            }.catch { error in
                owsFailDebug("---- Error: \(error)")
        }
    }
}
