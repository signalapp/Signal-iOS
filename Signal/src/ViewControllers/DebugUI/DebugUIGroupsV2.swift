//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging
import PromiseKit

#if DEBUG

class DebugUIGroupsV2: DebugUIPage {

    // MARK: Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    private var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
    }

    // MARK: Overrides 

    override func name() -> String {
        return "Groups v2"
    }

    override func section(thread: TSThread?) -> OWSTableSection? {
        var sectionItems = [OWSTableItem]()

        if let groupThread = thread as? TSGroupThread {
            sectionItems.append(OWSTableItem(title: "Make group update info messages.") { [weak self] in
                self?.insertGroupUpdateInfoMessages(groupThread: groupThread)
            })

            if groupThread.isGroupV2Thread {
                sectionItems.append(OWSTableItem(title: "Kick other group members.") { [weak self] in
                    self?.kickOtherGroupMembers(groupThread: groupThread)
                })
            }
        }

        if let contactThread = thread as? TSContactThread {
            sectionItems.append(OWSTableItem(title: "Send invalid group messages.") { [weak self] in
                self?.sendInvalidGroupMessages(contactThread: contactThread)
            })
        }

        return OWSTableSection(title: "Groups v2", items: sectionItems)
    }

    private func insertGroupUpdateInfoMessages(groupThread: TSGroupThread) {

        databaseStorage.asyncWrite { transaction in
            do {
                try self.insertGroupUpdateInfoMessages(groupThread: groupThread,
                                                       groupsVersion: .V1,
                                                       isLocalUpdate: true,
                                                       prefix: "V1 Group, Local Updater:",
                                                       transaction: transaction)

                try self.insertGroupUpdateInfoMessages(groupThread: groupThread,
                                                       groupsVersion: .V1,
                                                       isLocalUpdate: false,
                                                       prefix: "V1 Group, Other Updater:",
                                                       transaction: transaction)

                try self.insertGroupUpdateInfoMessages(groupThread: groupThread,
                                                       groupsVersion: .V1,
                                                       isAnonymousUpdate: true,
                                                       prefix: "V1 Group, Anon Updater:",
                                                       transaction: transaction)

                if FeatureFlags.groupsV2CreateGroups {
                    try self.insertGroupUpdateInfoMessages(groupThread: groupThread,
                                                           groupsVersion: .V2,
                                                           isLocalUpdate: true,
                                                           prefix: "V2 Group, Local Updater:",
                                                           transaction: transaction)

                    try self.insertGroupUpdateInfoMessages(groupThread: groupThread,
                                                           groupsVersion: .V2,
                                                           isLocalUpdate: false,
                                                           prefix: "V2 Group, Other Updater:",
                                                           transaction: transaction)

                    try self.insertGroupUpdateInfoMessages(groupThread: groupThread,
                                                           groupsVersion: .V2,
                                                           isAnonymousUpdate: true,
                                                           prefix: "V2 Group, Anon Updater:",
                                                           transaction: transaction)

                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
    }

    private func insertGroupUpdateInfoMessages(groupThread: TSGroupThread,
                                               groupsVersion: GroupsVersion,
                                               isLocalUpdate: Bool = false,
                                               isAnonymousUpdate: Bool = false,
                                               prefix: String,
                                               transaction: SDSAnyWriteTransaction) throws {

        let prefix = prefix + " "

        // These will fail if you aren't registered or
        // don't have some Signal users in your contacts.
        let localAddress = tsAccountManager.localAddress!
        var allAddresses = contactsManager.signalAccounts.map { $0.recipientAddress }
        if groupsVersion == .V2 {
            // V2 group members must have a uuid.
            allAddresses = allAddresses.filter { $0.uuid != nil }
        }
        let updaterAddress: SignalServiceAddress?
        if isAnonymousUpdate {
            updaterAddress = nil
        } else if isLocalUpdate {
            updaterAddress = localAddress
        } else {
            updaterAddress = allAddresses[0]
        }
        let otherAddresses = allAddresses.filter { $0 != localAddress && $0 != updaterAddress }.shuffled()
        let otherAddress0: SignalServiceAddress = otherAddresses[0]
        let otherAddress1: SignalServiceAddress = otherAddresses[1]
        let randoAddress = SignalServiceAddress(uuid: UUID())

        let insertOutgoingMessage = { body in
            TSOutgoingMessageBuilder(thread: groupThread, messageBody: body).build().anyInsert(transaction: transaction)
        }

        var defaultModelBuilder = TSGroupModelBuilder()
        defaultModelBuilder.groupsVersion = groupsVersion
        var defaultMembershipBuilder = GroupMembership.Builder()
        defaultMembershipBuilder.addNonPendingMember(localAddress, role: .administrator)
        defaultModelBuilder.groupMembership = defaultMembershipBuilder.build()
        let defaultModel = try defaultModelBuilder.build(transaction: transaction)
        let defaultDMToken = DisappearingMessageToken.disabledToken

        do {
            insertOutgoingMessage(prefix + "created, empty.")

            let model1 = defaultModel
            let dmToken1 = defaultDMToken

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: nil,
                                                      newGroupModel: model1,
                                                      oldDisappearingMessageToken: nil,
                                                      newDisappearingMessageToken: dmToken1,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)
            guard groupsVersion == .V2 else {
                // We add a "revision = 1" variant for v2 only.
                return
            }

            var modelBuilder2 = model1.asBuilder
            modelBuilder2.groupV2Revision = 1
            let model2 = try modelBuilder2.build(transaction: transaction)
            let dmToken2 = defaultDMToken

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: nil,
                                                      newGroupModel: model2,
                                                      oldDisappearingMessageToken: nil,
                                                      newDisappearingMessageToken: dmToken2,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)
        }

        do {
            guard groupsVersion == .V1 else {
                // Inserting info messages for no-op updates will
                // trip an assert in v2 groups.
                return
            }

            insertOutgoingMessage(prefix + "modified, empty.")

            let model1 = defaultModel
            let dmToken1 = defaultDMToken

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: model1,
                                                      newGroupModel: model1,
                                                      oldDisappearingMessageToken: dmToken1,
                                                      newDisappearingMessageToken: dmToken1,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)
        }

        do {
            insertOutgoingMessage(prefix + "modified, empty -> complicated -> empty.")

            let model1 = defaultModel
            let dmToken1 = defaultDMToken

            var modelBuilder2 = model1.asBuilder
            modelBuilder2.name = "name 2"
            modelBuilder2.avatarData = "avatar 2".data(using: .utf8)
            var groupMembershipBuilder1 = model1.groupMembership.asBuilder
            groupMembershipBuilder1.addNonPendingMember(otherAddress0, role: .normal)
            if groupsVersion == .V2,
                let updaterUuid = updaterAddress?.uuid {
                groupMembershipBuilder1.addPendingMember(otherAddress1,
                                                         role: .normal,
                                                         addedByUuid: updaterUuid)
            }

            modelBuilder2.groupMembership = groupMembershipBuilder1.build()
            modelBuilder2.groupAccess = .adminOnly

            let model2 = try modelBuilder2.build(transaction: transaction)
            let dmToken2 = DisappearingMessageToken(isEnabled: true, durationSeconds: 30)

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: model1,
                                                      newGroupModel: model2,
                                                      oldDisappearingMessageToken: dmToken1,
                                                      newDisappearingMessageToken: dmToken2,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: model2,
                                                      newGroupModel: model1,
                                                      oldDisappearingMessageToken: dmToken2,
                                                      newDisappearingMessageToken: dmToken1,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)
        }

        do {
            insertOutgoingMessage(prefix + "DMs off -> on -> changed -> off.")

            let model = defaultModel

            let dmToken0 = DisappearingMessageToken.disabledToken
            let dmToken1 = DisappearingMessageToken(isEnabled: true, durationSeconds: 30)
            let dmToken2 = DisappearingMessageToken(isEnabled: true, durationSeconds: 60)
            let dmToken3 = DisappearingMessageToken.disabledToken

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: model,
                                                      newGroupModel: model,
                                                      oldDisappearingMessageToken: dmToken0,
                                                      newDisappearingMessageToken: dmToken1,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: model,
                                                      newGroupModel: model,
                                                      oldDisappearingMessageToken: dmToken1,
                                                      newDisappearingMessageToken: dmToken2,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: model,
                                                      newGroupModel: model,
                                                      oldDisappearingMessageToken: dmToken2,
                                                      newDisappearingMessageToken: dmToken3,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)
        }

        do {
            guard groupsVersion == .V2 else {
                return
            }

            insertOutgoingMessage(prefix + "access changes.")

            var modelBuilder1 = TSGroupModelBuilder()
            modelBuilder1.groupsVersion = groupsVersion
            modelBuilder1.groupAccess = .defaultForV2
            modelBuilder1.groupMembership = defaultMembershipBuilder.build()
            let model1 = try modelBuilder1.build(transaction: transaction)

            var modelBuilder2 = model1.asBuilder
            modelBuilder2.groupAccess = .adminOnly
            let model2 = try modelBuilder2.build(transaction: transaction)

            var modelBuilder3 = model1.asBuilder
            modelBuilder3.groupAccess = .allAccess
            let model3 = try modelBuilder3.build(transaction: transaction)

            let dmToken = defaultDMToken

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: model1,
                                                      newGroupModel: model2,
                                                      oldDisappearingMessageToken: dmToken,
                                                      newDisappearingMessageToken: dmToken,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: model2,
                                                      newGroupModel: model3,
                                                      oldDisappearingMessageToken: dmToken,
                                                      newDisappearingMessageToken: dmToken,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: model3,
                                                      newGroupModel: model1,
                                                      oldDisappearingMessageToken: dmToken,
                                                      newDisappearingMessageToken: dmToken,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)
        }

        do {
            guard groupsVersion == .V2 else {
                return
            }

            insertOutgoingMessage(prefix + "role changes.")

            var members = [localAddress, otherAddress0, randoAddress ]
            if let updaterAddress = updaterAddress {
                members.append(updaterAddress)
            }
            members = Array(Set(members)).shuffled()

            var modelBuilder1 = defaultModel.asBuilder
            var groupMembershipBuilder1 = defaultModel.groupMembership.asBuilder
            for member in members {
                groupMembershipBuilder1.remove(member)
                groupMembershipBuilder1.addNonPendingMember(member, role: .normal)
            }
            modelBuilder1.groupMembership = groupMembershipBuilder1.build()
            let model1 = try modelBuilder1.build(transaction: transaction)

            var modelBuilder2 = defaultModel.asBuilder
            var groupMembershipBuilder2 = defaultModel.groupMembership.asBuilder
            for member in members {
                groupMembershipBuilder2.remove(member)
                groupMembershipBuilder2.addNonPendingMember(member, role: .administrator)
            }
            modelBuilder2.groupMembership = groupMembershipBuilder2.build()
            let model2 = try modelBuilder2.build(transaction: transaction)

            let dmToken = defaultDMToken

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: model1,
                                                      newGroupModel: model2,
                                                      oldDisappearingMessageToken: dmToken,
                                                      newDisappearingMessageToken: dmToken,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: model2,
                                                      newGroupModel: model1,
                                                      oldDisappearingMessageToken: dmToken,
                                                      newDisappearingMessageToken: dmToken,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)
        }

        do {
            guard groupsVersion == .V2 else {
                return
            }

            insertOutgoingMessage(prefix + "basic membership changes.")

            var members = [localAddress, otherAddress0 ]
            if let updaterAddress = updaterAddress {
                members.append(updaterAddress)
            }
            members = Array(Set(members)).shuffled()

            var modelBuilder1 = defaultModel.asBuilder
            modelBuilder1.groupMembership = GroupMembership()
            let model1 = try modelBuilder1.build(transaction: transaction)

            var modelBuilder2 = defaultModel.asBuilder
            var groupMembershipBuilder2 = defaultModel.groupMembership.asBuilder
            for member in members {
                groupMembershipBuilder2.remove(member)
                groupMembershipBuilder2.addNonPendingMember(member, role: .administrator)
            }
            modelBuilder2.groupMembership = groupMembershipBuilder2.build()
            let model2 = try modelBuilder2.build(transaction: transaction)

            let dmToken = defaultDMToken

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: model1,
                                                      newGroupModel: model2,
                                                      oldDisappearingMessageToken: dmToken,
                                                      newDisappearingMessageToken: dmToken,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)

            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: model2,
                                                      newGroupModel: model1,
                                                      oldDisappearingMessageToken: dmToken,
                                                      newDisappearingMessageToken: dmToken,
                                                      groupUpdateSourceAddress: updaterAddress,
                                                      transaction: transaction)
        }

        do {
            guard groupsVersion == .V2 else {
                return
            }
            guard !isAnonymousUpdate else {
                return
            }

            insertOutgoingMessage(prefix + "invite variations.")

            var members = [localAddress, otherAddress0, otherAddress1 ]
            var inviters = [localAddress, otherAddress0 ]
            if let updaterAddress = updaterAddress {
                members.append(updaterAddress)
                inviters.append(updaterAddress)
            }
            members = Array(Set(members)).shuffled()
            inviters = Array(Set(inviters)).shuffled()

            for inviter in inviters {
                guard let inviterUuid = inviter.uuid else {
                    continue
                }

                // Model 1: Empty.
                var modelBuilder1 = defaultModel.asBuilder
                modelBuilder1.groupMembership = GroupMembership()
                let model1 = try modelBuilder1.build(transaction: transaction)

                // Model 2: Invited.
                var modelBuilder2 = defaultModel.asBuilder
                var groupMembershipBuilder2 = defaultModel.groupMembership.asBuilder
                for member in members {
                    groupMembershipBuilder2.remove(member)
                    groupMembershipBuilder2.addPendingMember(member, role: .normal, addedByUuid: inviterUuid)
                }
                modelBuilder2.groupMembership = groupMembershipBuilder2.build()
                let model2 = try modelBuilder2.build(transaction: transaction)

                // Model 3: Active members.
                var modelBuilder3 = defaultModel.asBuilder
                var groupMembershipBuilder3 = defaultModel.groupMembership.asBuilder
                for member in members {
                    groupMembershipBuilder3.remove(member)
                    groupMembershipBuilder3.addNonPendingMember(member, role: .administrator)
                }
                modelBuilder3.groupMembership = groupMembershipBuilder3.build()
                let model3 = try modelBuilder3.build(transaction: transaction)

                let dmToken = defaultDMToken

                // Invite: 1 -> 2
                GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                          oldGroupModel: model1,
                                                          newGroupModel: model2,
                                                          oldDisappearingMessageToken: dmToken,
                                                          newDisappearingMessageToken: dmToken,
                                                          groupUpdateSourceAddress: updaterAddress,
                                                          transaction: transaction)

                // Invite Accepted: 2 -> 3
                GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                          oldGroupModel: model2,
                                                          newGroupModel: model3,
                                                          oldDisappearingMessageToken: dmToken,
                                                          newDisappearingMessageToken: dmToken,
                                                          groupUpdateSourceAddress: updaterAddress,
                                                          transaction: transaction)

                // Invite Declined or Revoked: 2 -> 1
                GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                          oldGroupModel: model2,
                                                          newGroupModel: model1,
                                                          oldDisappearingMessageToken: dmToken,
                                                          newDisappearingMessageToken: dmToken,
                                                          groupUpdateSourceAddress: updaterAddress,
                                                          transaction: transaction)
            }
        }
    }

    private func kickOtherGroupMembers(groupThread: TSGroupThread) {

        guard let localAddress = tsAccountManager.localAddress else {
            return owsFailDebug("Missing localAddress.")
        }

        let oldGroupModel = groupThread.groupModel

        let oldGroupMembership = oldGroupModel.groupMembership
        var groupMembershipBuilder = oldGroupMembership.asBuilder
        for address in oldGroupMembership.allUsers {
            if address != localAddress {
                groupMembershipBuilder.remove(address)
            }
        }
        let newGroupMembership = groupMembershipBuilder.build()
        firstly { () -> Promise<TSGroupThread> in
            var groupModelBuilder = oldGroupModel.asBuilder
            groupModelBuilder.groupMembership = newGroupMembership
            let newGroupModel = try databaseStorage.read { transaction in
                try groupModelBuilder.buildAsV2(transaction: transaction)
            }
            return GroupManager.localUpdateExistingGroup(groupModel: newGroupModel,
                                                         dmConfiguration: nil,
                                                         groupUpdateSourceAddress: localAddress)
        }.done { (_) -> Void in
            Logger.info("Success.")
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }.retainUntilComplete()
    }

    private func sendInvalidGroupMessages(contactThread: TSContactThread) {
        var messages = [TSOutgoingMessage]()

        let buildValidGroupContextInfo = { () -> GroupV2ContextInfo in
            let groupsV2 = self.groupsV2
            let groupSecretParamsData = try! groupsV2.generateGroupSecretParamsData()
            let masterKeyData = try! GroupsV2Protos.masterKeyData(forGroupSecretParamsData: groupSecretParamsData)
            return try! groupsV2.groupV2ContextInfo(forMasterKeyData: masterKeyData)
        }

        do {
            messages.append(OWSDynamicOutgoingMessage(thread: contactThread) { (_: SignalRecipient) -> Data in
                // Valid-looking group id/master key/secret params, but doesn't
                // correspond to an actual group on the service.
                let groupV2ContextInfo: GroupV2ContextInfo = buildValidGroupContextInfo()
                let revision: UInt32 = 0

                let builder = SSKProtoGroupContextV2.builder()
                builder.setMasterKey(groupV2ContextInfo.masterKeyData)
                builder.setRevision(revision)

//                if let changeActionsProtoData = changeActionsProtoData {
//                    assert(changeActionsProtoData.count > 0)
//                    builder.setGroupChange(changeActionsProtoData)
//                }

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setTimestamp(NSDate.ows_millisecondTimeStamp())
                dataBuilder.setRequiredProtocolVersion(0)
                return try! dataBuilder.buildSerializedData()
            })

//                }
//            - (OutgoingGroupProtoResult)addGroupsV2ToDataMessageBuilder:(SSKProtoDataMessageBuilder *)builder
//            groupThread:(TSGroupThread *)groupThread
//            transaction:(SDSAnyReadTransaction *)transaction
//            {
//                OWSAssertDebug(builder);
//                OWSAssertDebug(groupThread);
//                OWSAssertDebug(transaction);
//
//                if (![groupThread.groupModel isKindOfClass:[TSGroupModelV2 class]]) {
//                    OWSFailDebug(@"Invalid group model.");
//                    return OutgoingGroupProtoResult_Error;
//                }
//                TSGroupModelV2 *groupModel = (TSGroupModelV2 *)groupThread.groupModel;
//
//                NSError *error;
//                SSKProtoGroupContextV2 *_Nullable groupContextV2 =
//                    [self.groupsV2 buildGroupContextV2ProtoWithGroupModel:groupModel
//                        changeActionsProtoData:self.changeActionsProtoData
//                        error:&error];
//                if (groupContextV2 == nil || error != nil) {
//                    OWSFailDebug(@"Error: %@", error);
//                    return OutgoingGroupProtoResult_Error;
//                }
//                [builder setGroupV2:groupContextV2];
//                return OutgoingGroupProtoResult_AddedWithoutGroupAvatar;
//

        }

//        guard let localAddress = tsAccountManager.localAddress else {
//            return owsFailDebug("Missing localAddress.")
//        }
//        
//        let oldGroupModel = groupThread.groupModel
//        
//        let oldGroupMembership = oldGroupModel.groupMembership
//        var groupMembershipBuilder = oldGroupMembership.asBuilder
//        for address in oldGroupMembership.allUsers {
//            if address != localAddress {
//                groupMembershipBuilder.remove(address)
//            }
//        }
//        let newGroupMembership = groupMembershipBuilder.build()
//        firstly { () -> Promise<TSGroupThread> in
//            var groupModelBuilder = oldGroupModel.asBuilder
//            groupModelBuilder.groupMembership = newGroupMembership
//            let newGroupModel = try databaseStorage.read { transaction in
//                try groupModelBuilder.buildAsV2(transaction: transaction)
//            }
//            return GroupManager.localUpdateExistingGroup(groupModel: newGroupModel,
//                                                         dmConfiguration: nil,
//                                                         groupUpdateSourceAddress: localAddress)
//        }.done { (_) -> Void in
//            Logger.info("Success.")
//        }.catch { error in
//            owsFailDebug("Error: \(error)")
//        }.retainUntilComplete()

//        [self.messageSenderJobQueue
//        messageSenderJobQueue.addMessage(

//        NSUInteger contentLength = arc4random_uniform(32);
//        return [Cryptography generateRandomBytes:contentLength];
//        SSKProtoContentBuilder *contentBuilder =
//            [SSKProtoContent builder];
//        return [[contentBuilder buildIgnoringErrors]
//            serializedDataIgnoringErrors];
//
//        let message = [[OWSDynamicOutgoingMessage alloc] initWithPlainTextDataBlock:block
//            thread:thread];
//
//        [self sendStressMessage:message];
        databaseStorage.write { transaction in
            for message in messages {
                self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
            }
        }
    }
}

#endif
