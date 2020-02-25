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

    // MARK: -

    private static func groupIdLength(for groupsVersion: GroupsVersion) -> Int32 {
        switch groupsVersion {
        case .V1:
            return kGroupIdLengthV1
        case .V2:
            return kGroupIdLengthV2
        }
    }

    @objc
    public static func isValidGroupId(_ groupId: Data, groupsVersion: GroupsVersion) -> Bool {
        let expectedLength = groupIdLength(for: groupsVersion)
        guard groupId.count == expectedLength else {
            owsFailDebug("Invalid groupId: \(groupId.count) != \(expectedLength)")
            return false
        }
        return true
    }

    @objc
    public static func isValidGroupIdOfAnyKind(_ groupId: Data) -> Bool {
        guard groupId.count == kGroupIdLengthV1 ||
            groupId.count == kGroupIdLengthV2 else {
                owsFailDebug("Invalid groupId: \(groupId.count) != \(kGroupIdLengthV1), \(kGroupIdLengthV2)")
                return false
        }
        return true
    }

    // MARK: - Group Models

    private static func buildGroupModel(groupId groupIdParam: Data?,
                                        name nameParam: String?,
                                        members membersParam: [SignalServiceAddress],
                                        administrators administratorsParam: [SignalServiceAddress],
                                        avatarData: Data?,
                                        groupsVersion groupsVersionParam: GroupsVersion? = nil,
                                        groupSecretParamsData groupSecretParamsDataParam: Data? = nil,
                                        newGroupSeed newGroupSeedParam: NewGroupSeed? = nil,
                                        transaction: SDSAnyReadTransaction) throws -> TSGroupModel {

        let newGroupSeed: NewGroupSeed
        if let newGroupSeedParam = newGroupSeedParam {
            newGroupSeed = newGroupSeedParam
        } else {
            newGroupSeed = NewGroupSeed()
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
            groupsVersion = self.groupsVersion(for: members,
                                               transaction: transaction)
        }

        let administrators = members.filter { administratorsParam.contains($0) }
        if administrators.count < administratorsParam.count {
            owsFailDebug("Invalid administrator.")
        }

        var groupSecretParamsData: Data?
        if groupsVersion == .V2 {
            if let groupSecretParamsDataParam = groupSecretParamsDataParam {
                groupSecretParamsData = groupSecretParamsDataParam
            } else {
                groupSecretParamsData = newGroupSeed.groupSecretParamsData
            }
        }

        let groupId: Data
        if let groupIdParam = groupIdParam {
            groupId = groupIdParam
        } else {
            switch groupsVersion {
            case .V1:
                groupId = newGroupSeed.groupIdV1
            case .V2:
                guard let groupIdV2 = newGroupSeed.groupIdV2 else {
                    throw OWSAssertionError("Missing groupIdV2.")
                }
                groupId = groupIdV2
            }
        }
        guard isValidGroupId(groupId, groupsVersion: groupsVersion) else {
            throw OWSAssertionError("Invalid groupId.")
        }

        return TSGroupModel(groupId: groupId,
                            name: name,
                            avatarData: avatarData,
                            members: members,
                            administrators: administrators,
                            groupsVersion: groupsVersion,
                            groupSecretParamsData: groupSecretParamsData)
    }

    // Convert a group state proto received from the service
    // into a group model.
    public static func buildGroupModel(groupV2State: GroupV2State,
                                       transaction: SDSAnyReadTransaction) throws -> TSGroupModel {
        let groupSecretParamsData = groupV2State.groupSecretParamsData
        let groupId = try groupsV2.groupId(forGroupSecretParamsData: groupSecretParamsData)
        let name: String = groupV2State.title
        let members: [SignalServiceAddress] = groupV2State.activeMembers
        let administrators: [SignalServiceAddress] = groupV2State.administrators
        // GroupsV2 TODO: Avatar.
        let avatarData: Data? = nil
        let groupsVersion = GroupsVersion.V2

        return try buildGroupModel(groupId: groupId,
                                   name: name,
                                   members: members,
                                   administrators: administrators,
                                   avatarData: avatarData,
                                   groupsVersion: groupsVersion,
                                   groupSecretParamsData: groupSecretParamsData,
                                   transaction: transaction)
    }

    // This should only be used for certain legacy edge cases.
    @objc
    public static func fakeGroupModel(groupId: Data?,
                                      transaction: SDSAnyReadTransaction) -> TSGroupModel? {
        do {
            return try buildGroupModel(groupId: groupId,
                                       name: nil,
                                       members: [],
                                       administrators: [],
                                       avatarData: nil,
                                       groupsVersion: .V1,
                                       groupSecretParamsData: nil,
                                       transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    private static func groupsVersion(for members: [SignalServiceAddress],
                                      transaction: SDSAnyReadTransaction) -> GroupsVersion {

        guard FeatureFlags.tryToCreateNewGroupsV2 else {
            return .V1
        }
        let canUseV2 = self.canUseV2(for: members, transaction: transaction)
        return canUseV2 ? defaultGroupsVersion : .V1
    }

    private static func canUseV2(for members: [SignalServiceAddress],
                                 transaction: SDSAnyReadTransaction) -> Bool {

        for recipientAddress in members {
            guard let uuid = recipientAddress.uuid else {
                Logger.warn("Creating legacy group; member without UUID.")
                return false
            }
            let address = SignalServiceAddress(uuid: uuid)
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

    @objc
    public static var defaultGroupsVersion: GroupsVersion {
        guard FeatureFlags.tryToCreateNewGroupsV2 else {
            return .V1
        }
        return .V2
    }

    // MARK: - Create New Group
    //
    // "New" groups are being created for the first time; they might need to be created on the service.

    public static func createNewGroup(members: [SignalServiceAddress],
                                      groupId: Data? = nil,
                                      name: String? = nil,
                                      avatarImage: UIImage?,
                                      newGroupSeed: NewGroupSeed? = nil,
                                      shouldSendMessage: Bool) -> Promise<TSGroupThread> {

        return DispatchQueue.global().async(.promise) {
            return TSGroupModel.data(forGroupAvatar: avatarImage)
        }.then(on: .global()) { avatarData in
            return createNewGroup(members: members,
                                  groupId: groupId,
                                  name: name,
                                  avatarData: avatarData,
                                  newGroupSeed: newGroupSeed,
                                  shouldSendMessage: shouldSendMessage)
        }
    }

    public static func createNewGroup(members membersParam: [SignalServiceAddress],
                                      groupId: Data? = nil,
                                      name: String? = nil,
                                      avatarData: Data? = nil,
                                      newGroupSeed: NewGroupSeed? = nil,
                                      shouldSendMessage: Bool) -> Promise<TSGroupThread> {

        struct GroupMembers {
            let members: [SignalServiceAddress]
            let administrators: [SignalServiceAddress]
        }

        guard let localAddress = self.tsAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Missing localAddress."))
        }
        guard let groupsV2Swift = self.groupsV2 as? GroupsV2Swift else {
            return Promise(error: OWSAssertionError("Invalid groupsV2 instance."))
        }

        return DispatchQueue.global().async(.promise) { () -> GroupMembers in
            guard let localAddress = self.tsAccountManager.localAddress else {
                throw OWSAssertionError("Missing localAddress.")
            }
            // Build member list.
            let members: [SignalServiceAddress] = membersParam + [localAddress]
            let administrators: [SignalServiceAddress] = [localAddress]
            return GroupMembers(members: members, administrators: administrators)
        }.then(on: .global()) { (members: GroupMembers) -> Promise<GroupMembers> in
            // We will need a profile key credential for all users including
            // ourself.  If we've never done a versioned profile update,
            // try to do so now.
            guard FeatureFlags.tryToCreateNewGroupsV2 else {
                return Promise.value(members)
            }
            let hasLocalCredential = self.databaseStorage.read { transaction in
                return self.groupsV2.hasProfileKeyCredential(for: localAddress,
                                                             transaction: transaction)
            }
            guard !hasLocalCredential else {
                return Promise.value(members)
            }
            return groupsV2Swift.reuploadLocalProfilePromise()
                .map(on: .global()) { (_) -> GroupMembers in
                    return members
            }
        }.then(on: .global()) { (members: GroupMembers) -> Promise<GroupMembers> in
            // Try to obtain profile key credentials for all group members
            // including ourself, unless we already have them on hand.
            guard FeatureFlags.tryToCreateNewGroupsV2 else {
                return Promise.value(members)
            }
            return groupsV2Swift.tryToEnsureProfileKeyCredentials(for: members.members)
                .map(on: .global()) { (_) -> GroupMembers in
                    return members
            }
        }.then(on: .global()) { (members: GroupMembers) throws -> Promise<TSGroupModel> in
            let groupModel = try self.databaseStorage.read { transaction in
                return try self.buildGroupModel(groupId: groupId,
                                                name: name,
                                                members: members.members,
                                                administrators: members.administrators,
                                                avatarData: avatarData,
                                                newGroupSeed: newGroupSeed,
                                                transaction: transaction)
            }
            return self.createNewGroupOnServiceIfNecessary(groupModel: groupModel)
        }.then(on: .global()) { (groupModel: TSGroupModel) -> Promise<TSGroupThread> in
            // We're creating this thread, we added ourselves
            groupModel.addedByAddress = self.tsAccountManager.localAddress
            let thread = databaseStorage.write { (transaction: SDSAnyWriteTransaction) -> TSGroupThread in
                let thread = TSGroupThread(groupModelPrivate: groupModel)
                thread.anyInsert(transaction: transaction)
                let infoMessage = TSInfoMessage(thread: thread,
                                                messageType: .typeGroupUpdate,
                                                infoMessageUserInfo: [.newGroupModel: groupModel,
                                                                      .groupUpdateSourceAddress: localAddress])
                infoMessage.anyInsert(transaction: transaction)

                return thread
            }

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
        guard let groupsV2Swift = self.groupsV2 as? GroupsV2Swift else {
            return Promise(error: OWSAssertionError("Invalid groupsV2 instance."))
        }
        return groupsV2Swift.createNewGroupOnService(groupModel: groupModel)
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
                                          newGroupSeed: NewGroupSeed?,
                                          shouldSendMessage: Bool,
                                          success: @escaping (TSGroupThread) -> Void,
                                          failure: @escaping (Error) -> Void) {
        createNewGroup(members: members,
                       groupId: groupId,
                       name: name,
                       avatarImage: avatarImage,
                       newGroupSeed: newGroupSeed,
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
                                          newGroupSeed: NewGroupSeed?,
                                          shouldSendMessage: Bool,
                                          success: @escaping (TSGroupThread) -> Void,
                                          failure: @escaping (Error) -> Void) {
        createNewGroup(members: members,
                       groupId: groupId,
                       name: name,
                       avatarData: avatarData,
                       newGroupSeed: newGroupSeed,
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
                                           administrators: [SignalServiceAddress] = [],
                                           name: String? = nil,
                                           avatarData: Data? = nil,
                                           groupId: Data? = nil,
                                           groupsVersion: GroupsVersion? = nil,
                                           transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {

        // Use buildGroupModel() to fill in defaults, like it was a new group.
        let model = try buildGroupModel(groupId: groupId,
                                        name: name,
                                        members: members,
                                        administrators: administrators,
                                        avatarData: avatarData,
                                        groupsVersion: groupsVersion,
                                        transaction: transaction)

        // But just create it in the database, don't create it on the service.
        return try upsertExistingGroup(members: model.groupMembers,
                                       administrators: model.administrators,
                                       name: model.groupName,
                                       avatarData: model.groupAvatarData,
                                       groupId: model.groupId,
                                       groupsVersion: model.groupsVersion,
                                       groupSecretParamsData: model.groupSecretParamsData,
                                       shouldSendMessage: false,
                                       groupUpdateSourceAddress: tsAccountManager.localAddress!,
                                       transaction: transaction).thread
    }

    #endif

    // MARK: - Upsert Existing Group
    //
    // "Existing" groups have already been created, we just need to make sure they're in the database.

    @objc(upsertExistingGroupWithMembers:administrators:name:avatarData:groupId:groupsVersion:groupSecretParamsData:shouldSendMessage:groupUpdateSourceAddress:createInfoMessageForNewGroups:transaction:error:)
    public static func upsertExistingGroup(members: [SignalServiceAddress],
                                           administrators: [SignalServiceAddress],
                                           name: String? = nil,
                                           avatarData: Data? = nil,
                                           groupId: Data,
                                           groupsVersion: GroupsVersion,
                                           groupSecretParamsData: Data? = nil,
                                           shouldSendMessage: Bool,
                                           groupUpdateSourceAddress: SignalServiceAddress?,
                                           createInfoMessageForNewGroups: Bool = true,
                                           transaction: SDSAnyWriteTransaction) throws -> EnsureGroupResult {

        // GroupsV2 TODO: Audit all callers too see if they should include local uuid.

        let groupModel = try buildGroupModel(groupId: groupId,
                                             name: name,
                                             members: members,
                                             administrators: administrators,
                                             avatarData: avatarData,
                                             groupsVersion: groupsVersion,
                                             groupSecretParamsData: groupSecretParamsData,
                                             transaction: transaction)

        if let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
            guard !groupModel.isEqual(to: thread.groupModel) else {
                return EnsureGroupResult(action: .unchanged, thread: thread)
            }
            let updatedThread = try updateExistingGroup(groupId: groupId,
                                                        members: members,
                                                        administrators: administrators,
                                                        name: name,
                                                        avatarData: avatarData,
                                                        shouldSendMessage: shouldSendMessage,
                                                        groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                        transaction: transaction)
            return EnsureGroupResult(action: .updated, thread: updatedThread)
        } else {
            // This thread didn't previously exist, so if we're a member we
            // have to assume we were just added.
            var wasAddedToGroup = false
            if let localAddress = tsAccountManager.localAddress, groupModel.groupMembers.contains(localAddress) {
                groupModel.addedByAddress = groupUpdateSourceAddress
                wasAddedToGroup = true
            }

            // GroupsV2 TODO: Can we use upsertGroupThread(...) here and above?
            let thread = TSGroupThread(groupModelPrivate: groupModel)
            thread.anyInsert(transaction: transaction)

            // Auto-accept the message request for this group if we were added by someone we trust.
            if wasAddedToGroup, let addedByAddress = groupUpdateSourceAddress,
                profileManager.isUser(inProfileWhitelist: addedByAddress, transaction: transaction) {
                profileManager.addGroupId(toProfileWhitelist: groupModel.groupId, wasLocallyInitiated: true, transaction: transaction)
            }

            if createInfoMessageForNewGroups {
                var userInfo: [InfoMessageUserInfoKey: Any] = [
                    .newGroupModel: groupModel
                ]
                if let groupUpdateSourceAddress = groupUpdateSourceAddress {
                    userInfo[.groupUpdateSourceAddress] = groupUpdateSourceAddress
                }
                let infoMessage = TSInfoMessage(thread: thread,
                                                messageType: .typeGroupUpdate,
                                                infoMessageUserInfo: userInfo)
                infoMessage.anyInsert(transaction: transaction)
            }

            return EnsureGroupResult(action: .inserted, thread: thread)
        }
    }

    // MARK: - Update Existing Group

    @objc
    public static func updateExistingGroup(groupId: Data,
                                           members membersParam: [SignalServiceAddress],
                                           administrators: [SignalServiceAddress],
                                           name: String? = nil,
                                           avatarData: Data? = nil,
                                           shouldSendMessage: Bool,
                                           groupUpdateSourceAddress: SignalServiceAddress?,
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
                                                administrators: administrators,
                                                avatarData: avatarData,
                                                groupsVersion: oldGroupModel.groupsVersion,
                                                groupSecretParamsData: oldGroupModel.groupSecretParamsData,
                                                transaction: transaction)
        if oldGroupModel.isEqual(to: newGroupModel) {
            // Skip redundant update.
            return thread
        }

        // If we weren't previously a member and are now a member, assume whoever
        // triggered this update added us to the group.
        if !oldGroupModel.groupMembers.contains(localAddress), newGroupModel.groupMembers.contains(localAddress) {
            newGroupModel.addedByAddress = groupUpdateSourceAddress

            // Auto-accept the message request for this group if we were added by someone we trust.
            if let addedByAddress = groupUpdateSourceAddress,
                profileManager.isUser(inProfileWhitelist: addedByAddress, transaction: transaction) {
                profileManager.addGroupId(toProfileWhitelist: newGroupModel.groupId, wasLocallyInitiated: true, transaction: transaction)
            }
        }

        var userInfo: [InfoMessageUserInfoKey: Any] = [
            .oldGroupModel: oldGroupModel,
            .newGroupModel: newGroupModel
        ]
        if let groupUpdateSourceAddress = groupUpdateSourceAddress {
            userInfo[.groupUpdateSourceAddress] = groupUpdateSourceAddress
        }
        let infoMessage = TSInfoMessage(thread: thread,
                                        messageType: .typeGroupUpdate,
                                        infoMessageUserInfo: userInfo)
        infoMessage.anyInsert(transaction: transaction)

        // GroupsV2 TODO: Convert this method and callers to return a promise.
        //                We need to audit usage of upsertExistingGroup();
        //                It's possible that it should only be used for v1 groups?
        switch oldGroupModel.groupsVersion {
        case .V1:
            break
        case .V2:
            guard let groupsV2Swift = self.groupsV2 as? GroupsV2Swift else {
                throw OWSAssertionError("Invalid groupsV2 instance.")
            }
            let changeSet = try groupsV2Swift.buildChangeSet(from: oldGroupModel,
                                                             to: newGroupModel)
            // GroupsV2 TODO: Return promise.
            groupsV2Swift.updateExistingGroupOnService(changeSet: changeSet).retainUntilComplete()
        }

        // GroupsV2 TODO: v2 groups must be modified in step-wise fashion,
        //                creating local messages for each revision.
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
        // GroupsV2 TODO: This behavior will change for v2 groups.
        let expiresInSeconds = thread.disappearingMessagesDuration(with: transaction)
        let message = TSOutgoingMessage(in: thread,
                                        groupMetaMessage: .update,
                                        expiresInSeconds: expiresInSeconds)

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
        return firstly {
            self.messageSender.sendMessage(.promise, message.asPreparer)
        }.done(on: .global()) { _ in
            Logger.debug("Successfully sent group update")
        }.recover(on: .global()) { error in
            owsFailDebug("Failed to send group update with error: \(error)")
            throw error
        }
    }

    // MARK: - Utils

    // This method only updates the local database.
    // It doesn't interact with service, create interactions, etc.
    @objc
    public static func upsertGroupV2Thread(groupModel: TSGroupModel,
                                           transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {
        guard groupModel.groupsVersion == .V2 else {
            throw OWSAssertionError("unexpected v1 group")
        }

        if let thread = TSGroupThread.fetch(groupId: groupModel.groupId, transaction: transaction) {
            guard thread.groupModel.groupsVersion == .V2 else {
                throw OWSAssertionError("Invalid groupsVersion.")
            }

            // GroupsV2 TODO: how to plumb through .groupUpdateSourceAddress to get richer group update messages?
            let userInfo: [InfoMessageUserInfoKey: Any] = [
                .oldGroupModel: thread.groupModel,
                .newGroupModel: groupModel
            ]
            let infoMessage = TSInfoMessage(thread: thread,
                                            messageType: .typeGroupUpdate,
                                            infoMessageUserInfo: userInfo)
            infoMessage.anyInsert(transaction: transaction)

            thread.update(with: groupModel, transaction: transaction)
            return thread
        } else {
            let thread = TSGroupThread(groupModelPrivate: groupModel)
            thread.anyInsert(transaction: transaction)

            // GroupsV2 TODO: how to plumb through .groupUpdateSourceAddress to get richer group update messages?
            let userInfo: [InfoMessageUserInfoKey: Any] = [
                .newGroupModel: groupModel
            ]
            let infoMessage = TSInfoMessage(thread: thread,
                                            messageType: .typeGroupUpdate,
                                            infoMessageUserInfo: userInfo)
            infoMessage.anyInsert(transaction: transaction)
            return thread
        }
    }

    // MARK: - Messages

    private static func sendDurableNewGroupMessage(forThread thread: TSGroupThread) -> Promise<Void> {
        assert(thread.groupModel.groupAvatarData == nil)

        return databaseStorage.write(.promise) { transaction in
            let message = TSOutgoingMessage.init(in: thread, groupMetaMessage: .new, expiresInSeconds: 0)
            self.messageSenderJobQueue.add(message: message.asPreparer,
                                           transaction: transaction)
        }
    }
}
