//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalMessaging

#if USE_DEBUG_UI

class DebugUIGroupsV2: DebugUIPage {

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

            sectionItems.append(OWSTableItem(title: "Send group update.") { [weak self] in
                self?.sendGroupUpdate(groupThread: groupThread)
            })

            if let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 {
                // v2 Group
                sectionItems.append(OWSTableItem(title: "Kick other group members.") { [weak self] in
                    self?.kickOtherGroupMembers(groupModel: groupModelV2)
                })
            } else {
                // v1 Group
                sectionItems.append(OWSTableItem(title: "Send empty v1 group update.") { [weak self] in
                    self?.sendEmptyV1GroupUpdate(groupThread: groupThread)
                })
            }
        }

        if let contactThread = thread as? TSContactThread {
            sectionItems.append(OWSTableItem(title: "Send invalid group messages.") { [weak self] in
                self?.sendInvalidGroupMessages(contactThread: contactThread)
            })
        }

        if let groupThread = thread as? TSGroupThread,
            groupThread.isGroupV2Thread {
            sectionItems.append(OWSTableItem(title: "Send partially-invalid group messages.") { [weak self] in
                self?.sendPartiallyInvalidGroupMessages(groupThread: groupThread)
            })
            sectionItems.append(OWSTableItem(title: "Update v2 group immediately.") { [weak self] in
                self?.updateV2GroupImmediately(groupThread: groupThread)
            })
        }

        if let groupThread = thread as? TSGroupThread {
            sectionItems.append(OWSTableItem(title: "Try to migrate group (is already migrated on service).") {
                Self.migrate(groupThread: groupThread,
                             migrationMode: .isAlreadyMigratedOnService)
            })
            sectionItems.append(OWSTableItem(title: "Try to migrate group (aggressive manual migration).") {
                Self.migrate(groupThread: groupThread,
                             migrationMode: .manualMigrationAggressive)
            })
            sectionItems.append(OWSTableItem(title: "Try to migrate group (polite auto migration).") {
                Self.migrate(groupThread: groupThread,
                             migrationMode: .autoMigrationPolite)
            })
        }

        return OWSTableSection(title: "Groups v2", items: sectionItems)
    }

    private static func migrate(groupThread: TSGroupThread,
                                migrationMode: GroupsV2MigrationMode) {
        _ = firstly { () -> Promise<TSGroupThread> in
            GroupsV2Migration.tryToMigrate(groupThread: groupThread,
                                           migrationMode: migrationMode)
        }.done { _ in
            Logger.verbose("Done.")
        }.catch { error in
            Logger.verbose("Error: \(error).")
        }
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

        let signalAccounts = self.contactsManagerImpl.unsortedSignalAccounts(transaction: transaction)

        // These will fail if you aren't registered or
        // don't have some Signal users in your contacts.
        let localAddress = tsAccountManager.localAddress!
        var allAddresses = signalAccounts.map { $0.recipientAddress }
        if groupsVersion == .V2 {
            // V2 group members must have a uuid.
            allAddresses = allAddresses.filter { $0.uuid != nil }
        }
        guard allAddresses.count >= 3 else {
            return owsFailDebug("Not enough Signal users in your contacts.")
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
            TSOutgoingMessageBuilder(thread: groupThread, messageBody: body).build(transaction: transaction).anyInsert(transaction: transaction)
        }

        var defaultModelBuilder = TSGroupModelBuilder()
        defaultModelBuilder.groupsVersion = groupsVersion
        var defaultMembershipBuilder = GroupMembership.Builder()
        defaultMembershipBuilder.addFullMember(localAddress, role: .administrator)
        defaultModelBuilder.groupMembership = defaultMembershipBuilder.build()
        let defaultModel = try defaultModelBuilder.build()
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
            let model2 = try modelBuilder2.build()
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
            groupMembershipBuilder1.addFullMember(otherAddress0, role: .normal)
            if groupsVersion == .V2,
                let updaterUuid = updaterAddress?.uuid {
                groupMembershipBuilder1.addInvitedMember(otherAddress1,
                                                         role: .normal,
                                                         addedByUuid: updaterUuid)
            }

            modelBuilder2.groupMembership = groupMembershipBuilder1.build()
            modelBuilder2.groupAccess = .adminOnly

            let model2 = try modelBuilder2.build()
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
            let model1 = try modelBuilder1.build()

            var modelBuilder2 = model1.asBuilder
            modelBuilder2.groupAccess = .adminOnly
            let model2 = try modelBuilder2.build()

            var modelBuilder3 = model1.asBuilder
            modelBuilder3.groupAccess = .allAccess
            let model3 = try modelBuilder3.build()

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
                groupMembershipBuilder1.addFullMember(member, role: .normal)
            }
            modelBuilder1.groupMembership = groupMembershipBuilder1.build()
            let model1 = try modelBuilder1.build()

            var modelBuilder2 = defaultModel.asBuilder
            var groupMembershipBuilder2 = defaultModel.groupMembership.asBuilder
            for member in members {
                groupMembershipBuilder2.remove(member)
                groupMembershipBuilder2.addFullMember(member, role: .administrator)
            }
            modelBuilder2.groupMembership = groupMembershipBuilder2.build()
            let model2 = try modelBuilder2.build()

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
            let model1 = try modelBuilder1.build()

            var modelBuilder2 = defaultModel.asBuilder
            var groupMembershipBuilder2 = defaultModel.groupMembership.asBuilder
            for member in members {
                groupMembershipBuilder2.remove(member)
                groupMembershipBuilder2.addFullMember(member, role: .administrator)
            }
            modelBuilder2.groupMembership = groupMembershipBuilder2.build()
            let model2 = try modelBuilder2.build()

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
                let model1 = try modelBuilder1.build()

                // Model 2: Invited.
                var modelBuilder2 = defaultModel.asBuilder
                var groupMembershipBuilder2 = defaultModel.groupMembership.asBuilder
                for member in members {
                    groupMembershipBuilder2.remove(member)
                    groupMembershipBuilder2.addInvitedMember(member, role: .normal, addedByUuid: inviterUuid)
                }
                modelBuilder2.groupMembership = groupMembershipBuilder2.build()
                let model2 = try modelBuilder2.build()

                // Model 3: Active members.
                var modelBuilder3 = defaultModel.asBuilder
                var groupMembershipBuilder3 = defaultModel.groupMembership.asBuilder
                for member in members {
                    groupMembershipBuilder3.remove(member)
                    groupMembershipBuilder3.addFullMember(member, role: .administrator)
                }
                modelBuilder3.groupMembership = groupMembershipBuilder3.build()
                let model3 = try modelBuilder3.build()

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

    private func kickOtherGroupMembers(groupModel: TSGroupModelV2) {
        guard let localAddress = tsAccountManager.localAddress else {
            return owsFailDebug("Missing localAddress.")
        }

        let uuidsToKick = groupModel.groupMembership.allMembersOfAnyKind.filter { address in
            address != localAddress
        }.compactMap({ $0.uuid })

        GroupManager.removeFromGroupOrRevokeInviteV2(groupModel: groupModel, uuids: uuidsToKick)
            .done { _ in
                Logger.info("Success.")
            }.catch { error in
                owsFailDebug("Error: \(error)")
            }
    }

    private func sendInvalidGroupMessages(contactThread: TSContactThread) {
        let otherUserAddress = contactThread.contactAddress
        guard let otherUserUuid = otherUserAddress.uuid else {
            owsFailDebug("Recipient is missing UUID.")
            return
        }

        firstly { () -> Promise<TSGroupModelV2> in
            // Make a real v2 group on the service.
            // Local user and "other user" are members.
            return firstly {
                GroupManager.localCreateNewGroup(members: [otherUserAddress],
                                                 name: "Real group, both users are in the group",
                                                 disappearingMessageToken: .disabledToken,
                                                 shouldSendMessage: false)
            }.map(on: DispatchQueue.global()) { (groupThread: TSGroupThread) in
                guard let validGroupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid groupModel.")
                }
                return validGroupModelV2
            }
        }.then(on: DispatchQueue.global()) { (validGroupModelV2: TSGroupModelV2) -> Promise<(TSGroupModelV2, TSGroupModelV2)> in
            // Make a real v2 group on the service.
            // Local user is a member but "other user" is not.
            return firstly {
                GroupManager.localCreateNewGroup(members: [],
                                                 name: "Real group, recipient is not in the group",
                                                 disappearingMessageToken: .disabledToken,
                                                 shouldSendMessage: false)
            }.map(on: DispatchQueue.global()) { (groupThread: TSGroupThread) in
                guard let missingOtherUserGroupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid groupModel.")
                }
                return (validGroupModelV2, missingOtherUserGroupModelV2)
            }
        }.then(on: DispatchQueue.global()) { (validGroupModelV2: TSGroupModelV2, missingOtherUserGroupModelV2: TSGroupModelV2)
            -> Promise<(TSGroupModelV2, TSGroupModelV2, TSGroupModelV2)> in
            // Make a real v2 group on the service.
            // "Other user" is a member but local user is not.
            return firstly { () -> Promise<TSGroupThread> in
                GroupManager.localCreateNewGroup(members: [otherUserAddress],
                                                 name: "Real group, sender is not in the group",
                                                 disappearingMessageToken: .disabledToken,
                                                 shouldSendMessage: false)
            }.then(on: DispatchQueue.global()) { (groupThread: TSGroupThread) -> Promise<TSGroupThread> in
                guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid groupModel.")
                }
                guard groupModel.groupMembership.isFullMember(otherUserAddress) else {
                    throw OWSAssertionError("Other user is not a full member.")
                }
                // Last admin (local user) can't leave group, so first
                // make the "other user" an admin.
                return GroupManager.changeMemberRoleV2(groupModel: groupModel,
                                                       uuid: otherUserUuid,
                                                       role: .administrator)
            }.then(on: DispatchQueue.global()) { (groupThread: TSGroupThread) -> Promise<TSGroupThread> in
                self.databaseStorage.write { transaction in
                    GroupManager.localLeaveGroupOrDeclineInvite(
                        groupThread: groupThread,
                        transaction: transaction
                    )
                }
            }.map(on: DispatchQueue.global()) { (groupThread: TSGroupThread) in
                guard let missingLocalUserGroupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid groupModel.")
                }
                return (validGroupModelV2, missingOtherUserGroupModelV2, missingLocalUserGroupModelV2)
            }
        }.map(on: DispatchQueue.global()) { (validGroupModelV2: TSGroupModelV2, missingOtherUserGroupModelV2: TSGroupModelV2, missingLocalUserGroupModelV2: TSGroupModelV2) in
            self.sendInvalidGroupMessages(contactThread: contactThread,
                                          validGroupModelV2: validGroupModelV2,
                                          missingOtherUserGroupModelV2: missingOtherUserGroupModelV2,
                                          missingLocalUserGroupModelV2: missingLocalUserGroupModelV2)
        }.done(on: DispatchQueue.global()) { _ in
            Logger.info("Complete.")
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private func sendInvalidGroupMessages(contactThread: TSContactThread,
                                          validGroupModelV2: TSGroupModelV2,
                                          missingOtherUserGroupModelV2: TSGroupModelV2,
                                          missingLocalUserGroupModelV2: TSGroupModelV2) {
        var messages = [TSOutgoingMessage]()

        let groupContextInfoForGroupModel = { (groupModelV2: TSGroupModelV2) -> GroupV2ContextInfo in
            let masterKey = try! GroupsV2Protos.masterKeyData(forGroupModel: groupModelV2)
            return try! self.groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
        }

        let validGroupContextInfo = groupContextInfoForGroupModel(validGroupModelV2)
        let missingOtherUserGroupContextInfo = groupContextInfoForGroupModel(missingOtherUserGroupModelV2)
        let missingLocalUserGroupContextInfo = groupContextInfoForGroupModel(missingLocalUserGroupModelV2)

        let buildValidGroupContextInfo = { () -> GroupV2ContextInfo in
            let groupsV2 = self.groupsV2
            let groupSecretParamsData = try! groupsV2.generateGroupSecretParamsData()
            let masterKeyData = try! GroupsV2Protos.masterKeyData(forGroupSecretParamsData: groupSecretParamsData)
            return try! groupsV2.groupV2ContextInfo(forMasterKeyData: masterKeyData)
        }

        databaseStorage.read { transaction in
            messages.append(OWSDynamicOutgoingMessage(thread: contactThread, transaction: transaction) {
                // Real and valid group id/master key/secret params.
                // Other user is not in the group.
                let masterKeyData = missingOtherUserGroupContextInfo.masterKeyData
                // Real revision.
                let revision: UInt32 = 0

                let builder = SSKProtoGroupContextV2.builder()
                builder.setMasterKey(masterKeyData)
                builder.setRevision(revision)

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setGroupV2(try! builder.build())
                dataBuilder.setRequiredProtocolVersion(0)
                dataBuilder.setBody("\(messages.count)")
                return Self.contentProtoData(forDataBuilder: dataBuilder)
            })

            messages.append(OWSDynamicOutgoingMessage(thread: contactThread, transaction: transaction) {
                // Real and valid group id/master key/secret params.
                // Local user is not in the group.
                let masterKeyData = missingLocalUserGroupContextInfo.masterKeyData
                // Real revision.
                let revision: UInt32 = 0

                let builder = SSKProtoGroupContextV2.builder()
                builder.setMasterKey(masterKeyData)
                builder.setRevision(revision)

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setGroupV2(try! builder.build())
                dataBuilder.setRequiredProtocolVersion(0)
                dataBuilder.setBody("\(messages.count)")
                return Self.contentProtoData(forDataBuilder: dataBuilder)
            })

            messages.append(OWSDynamicOutgoingMessage(thread: contactThread, transaction: transaction) {
                // Real and valid group id/master key/secret params.
                let masterKeyData = validGroupContextInfo.masterKeyData
                // Non-existent revision.
                let revision: UInt32 = 99

                let builder = SSKProtoGroupContextV2.builder()
                builder.setMasterKey(masterKeyData)
                builder.setRevision(revision)

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setGroupV2(try! builder.build())
                dataBuilder.setRequiredProtocolVersion(0)
                dataBuilder.setBody("\(messages.count)")
                return Self.contentProtoData(forDataBuilder: dataBuilder)
            })

            messages.append(OWSDynamicOutgoingMessage(thread: contactThread, transaction: transaction) {
                // Real and valid group id/master key/secret params.
                var masterKeyData = validGroupContextInfo.masterKeyData
                // Truncate the master key.
                masterKeyData = masterKeyData.subdata(in: Int(0)..<Int(1))
                // Real revision.
                let revision: UInt32 = 0

                let builder = SSKProtoGroupContextV2.builder()
                builder.setMasterKey(masterKeyData)
                builder.setRevision(revision)

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setGroupV2(try! builder.build())
                dataBuilder.setRequiredProtocolVersion(0)
                dataBuilder.setBody("\(messages.count)")
                return Self.contentProtoData(forDataBuilder: dataBuilder)
            })

            messages.append(OWSDynamicOutgoingMessage(thread: contactThread, transaction: transaction) {
                // Real and valid group id/master key/secret params.
                var masterKeyData = validGroupContextInfo.masterKeyData
                // Append garbage to the master key.
                masterKeyData += Randomness.generateRandomBytes(1)
                // Real revision.
                let revision: UInt32 = 0

                let builder = SSKProtoGroupContextV2.builder()
                builder.setMasterKey(masterKeyData)
                builder.setRevision(revision)

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setGroupV2(try! builder.build())
                dataBuilder.setRequiredProtocolVersion(0)
                dataBuilder.setBody("\(messages.count)")
                return Self.contentProtoData(forDataBuilder: dataBuilder)
            })

            messages.append(OWSDynamicOutgoingMessage(thread: contactThread, transaction: transaction) {
                // Real and valid group id/master key/secret params.
                var masterKeyData = validGroupContextInfo.masterKeyData
                // Replace master key with zeroes.
                masterKeyData = Data(repeating: 0, count: masterKeyData.count)
                // Real revision.
                let revision: UInt32 = 0

                let builder = SSKProtoGroupContextV2.builder()
                builder.setMasterKey(masterKeyData)
                builder.setRevision(revision)

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setGroupV2(try! builder.build())
                dataBuilder.setRequiredProtocolVersion(0)
                dataBuilder.setBody("\(messages.count)")
                return Self.contentProtoData(forDataBuilder: dataBuilder)
            })

            messages.append(OWSDynamicOutgoingMessage(thread: contactThread, transaction: transaction) {
                // Real and valid group id/master key/secret params.
                let masterKeyData = validGroupContextInfo.masterKeyData

                let builder = SSKProtoGroupContextV2.builder()
                builder.setMasterKey(masterKeyData)
                // Don't set revision.

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setGroupV2(try! builder.build())
                dataBuilder.setRequiredProtocolVersion(0)
                dataBuilder.setBody("\(messages.count)")
                return Self.contentProtoData(forDataBuilder: dataBuilder)
            })

            messages.append(OWSDynamicOutgoingMessage(thread: contactThread, transaction: transaction) {
                // Real revision.
                let revision: UInt32 = 0

                let builder = SSKProtoGroupContextV2.builder()
                // Don't set master key.
                builder.setRevision(revision)

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setGroupV2(try! builder.build())
                dataBuilder.setRequiredProtocolVersion(0)
                dataBuilder.setBody("\(messages.count)")
                return Self.contentProtoData(forDataBuilder: dataBuilder)
            })

            messages.append(OWSDynamicOutgoingMessage(thread: contactThread, transaction: transaction) {
                // Valid-looking group id/master key/secret params, but doesn't
                // correspond to an actual group on the service.
                let groupV2ContextInfo: GroupV2ContextInfo = buildValidGroupContextInfo()
                let masterKeyData = groupV2ContextInfo.masterKeyData
                let revision: UInt32 = 0

                let builder = SSKProtoGroupContextV2.builder()
                builder.setMasterKey(masterKeyData)
                builder.setRevision(revision)

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setGroupV2(try! builder.build())
                dataBuilder.setRequiredProtocolVersion(0)
                dataBuilder.setBody("\(messages.count)")
                return Self.contentProtoData(forDataBuilder: dataBuilder)
            })

            messages.append(OWSDynamicOutgoingMessage(thread: contactThread, transaction: transaction) {
                // Real and valid group id/master key/secret params.
                let masterKeyData = validGroupContextInfo.masterKeyData
                // Real revision.
                let revision: UInt32 = 0

                let builder = SSKProtoGroupContextV2.builder()
                builder.setMasterKey(masterKeyData)
                builder.setRevision(revision)

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setGroupV2(try! builder.build())
                dataBuilder.setRequiredProtocolVersion(0)
                dataBuilder.setBody("Valid gv2 message.")
                return Self.contentProtoData(forDataBuilder: dataBuilder)
            })
        }

        for message in messages {
            messageSender.sendMessage(message.asPreparer, success: {}, failure: { _ in })
        }
    }

    private func sendPartiallyInvalidGroupMessages(groupThread: TSGroupThread) {
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid groupModel.")
            return
        }

        var messages = [TSOutgoingMessage]()

        let masterKey = try! GroupsV2Protos.masterKeyData(forGroupModel: groupModelV2)
        let groupContextInfo = try! self.groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)

        databaseStorage.read { transaction in
            messages.append(OWSDynamicOutgoingMessage(thread: groupThread, transaction: transaction) {
                // Real and valid group id/master key/secret params.
                let masterKeyData = groupContextInfo.masterKeyData
                // Real revision.
                let revision: UInt32 = 0

                let builder = SSKProtoGroupContextV2.builder()
                builder.setMasterKey(masterKeyData)
                builder.setRevision(revision)

                // Invalid embedded change actions proto data.
                let changeActionsProtoData = Randomness.generateRandomBytes(256)
                builder.setGroupChange(changeActionsProtoData)

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setGroupV2(try! builder.build())
                dataBuilder.setRequiredProtocolVersion(0)
                dataBuilder.setBody("Invalid embedded change actions proto: \(messages.count)")
                return Self.contentProtoData(forDataBuilder: dataBuilder)
            })

            messages.append(OWSDynamicOutgoingMessage(thread: groupThread, transaction: transaction) {
                // Real and valid group id/master key/secret params.
                let masterKeyData = groupContextInfo.masterKeyData
                // Real revision.
                let revision: UInt32 = 0

                let builder = SSKProtoGroupContextV2.builder()
                builder.setMasterKey(masterKeyData)
                builder.setRevision(revision)

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setGroupV2(try! builder.build())
                dataBuilder.setRequiredProtocolVersion(0)
                dataBuilder.setBody("Valid gv2 message.")
                return Self.contentProtoData(forDataBuilder: dataBuilder)
            })
        }

        for message in messages {
            messageSender.sendMessage(message.asPreparer, success: {}, failure: { _ in })
        }
    }

    class func contentProtoData(forDataBuilder dataBuilder: SSKProtoDataMessageBuilder) -> Data {
        let dataProto = try! dataBuilder.build()
        let contentBuilder = SSKProtoContent.builder()
        contentBuilder.setDataMessage(dataProto)
        let plaintextData = try! contentBuilder.buildSerializedData()
        return plaintextData
    }

    private func sendEmptyV1GroupUpdate(groupThread: TSGroupThread) {

        guard let localAddress = tsAccountManager.localAddress else {
            return owsFailDebug("Missing localAddress.")
        }

        let groupModel = groupThread.groupModel
        let timestamp = NSDate.ows_millisecondTimeStamp()

        let message = databaseStorage.read { transaction in
            OWSDynamicOutgoingMessage(thread: groupThread, transaction: transaction) {
                let groupContextBuilder = SSKProtoGroupContext.builder(id: groupModel.groupId)
                groupContextBuilder.setType(.update)
                groupContextBuilder.addMembersE164(localAddress.phoneNumber!)

                let memberBuilder = SSKProtoGroupContextMember.builder()
                memberBuilder.setE164(localAddress.phoneNumber!)
                groupContextBuilder.addMembers(try! memberBuilder.build())

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setTimestamp(timestamp)
                dataBuilder.setGroup(try! groupContextBuilder.build())
                dataBuilder.setRequiredProtocolVersion(0)
                return Self.contentProtoData(forDataBuilder: dataBuilder)
            }
        }

        firstly { () -> Promise<Void> in
            messageSender.sendMessage(.promise, message.asPreparer)
        }.done { (_) -> Void in
            Logger.info("Success.")
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private func sendGroupUpdate(groupThread: TSGroupThread) {
        firstly {
            GroupManager.sendGroupUpdateMessage(thread: groupThread)
        }.done { _ in
            Logger.info("Success.")
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private func updateV2GroupImmediately(groupThread: TSGroupThread) {
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid groupModel.")
            return
        }
        firstly {
            self.groupV2Updates.tryToRefreshV2GroupUpToCurrentRevisionImmediately(groupId: groupModelV2.groupId,
                                                                                  groupSecretParamsData: groupModelV2.secretParamsData)
        }.done { _ in
            Logger.info("Success.")
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }
}

#endif
