//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalMessaging
import SignalUI

#if USE_DEBUG_UI

class DebugUIGroupsV2: DebugUIPage, Dependencies {

    let name = "Groups v2"

    func section(thread: TSThread?) -> OWSTableSection? {
        var sectionItems = [OWSTableItem]()

        if let groupThread = thread as? TSGroupThread {
            sectionItems.append(OWSTableItem(title: "Send group update.") { [weak self] in
                self?.sendGroupUpdate(groupThread: groupThread)
            })

            if let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 {
                // v2 Group
                sectionItems.append(OWSTableItem(title: "Kick other group members.") { [weak self] in
                    self?.kickOtherGroupMembers(groupModel: groupModelV2)
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

        return OWSTableSection(title: "Groups v2", items: sectionItems)
    }

    // MARK: -

    private func kickOtherGroupMembers(groupModel: TSGroupModelV2) {
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            return owsFailDebug("Missing localAddress.")
        }

        let serviceIdsToKick = groupModel.groupMembership.allMembersOfAnyKind
            .compactMap({ $0.serviceId }).filter({ $0 != localAci })

        GroupManager.removeFromGroupOrRevokeInviteV2(groupModel: groupModel, serviceIds: serviceIdsToKick)
            .done { _ in
                Logger.info("Success.")
            }.catch { error in
                owsFailDebug("Error: \(error)")
            }
    }

    private func sendInvalidGroupMessages(contactThread: TSContactThread) {
        let otherUserAddress = contactThread.contactAddress
        // TODO: Support PNIs.
        guard let otherUserAci = otherUserAddress.serviceId as? Aci else {
            owsFailDebug("Recipient is missing ACI.")
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
                return GroupManager.changeMemberRoleV2(
                    groupModel: groupModel,
                    aci: otherUserAci,
                    role: .administrator
                )
            }.then(on: DispatchQueue.global()) { (groupThread: TSGroupThread) -> Promise<TSGroupThread> in
                self.databaseStorage.write { transaction in
                    GroupManager.localLeaveGroupOrDeclineInvite(groupThread: groupThread, tx: transaction)
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
            Task { try await self.messageSender.sendMessage(message.asPreparer) }
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
            Task { try await self.messageSender.sendMessage(message.asPreparer) }
        }
    }

    class func contentProtoData(forDataBuilder dataBuilder: SSKProtoDataMessageBuilder) -> Data {
        let dataProto = try! dataBuilder.build()
        let contentBuilder = SSKProtoContent.builder()
        contentBuilder.setDataMessage(dataProto)
        let plaintextData = try! contentBuilder.buildSerializedData()
        return plaintextData
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
