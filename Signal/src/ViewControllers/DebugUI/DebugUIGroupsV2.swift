//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUIGroupsV2: DebugUIPage {

    let name = "Groups v2"

    func section(thread: TSThread?) -> OWSTableSection? {
        var sectionItems = [OWSTableItem]()

        if let groupThread = thread as? TSGroupThread {
            if let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 {
                // v2 Group
                sectionItems.append(OWSTableItem(title: "Kick other group members.") { [weak self] in
                    self?.kickOtherGroupMembers(groupModel: groupModelV2)
                })
            }
        }

        if let groupThread = thread as? TSGroupThread, groupThread.isGroupV2Thread {
            sectionItems.append(OWSTableItem(title: "Send partially-invalid group messages.") { [weak self] in
                self?.sendPartiallyInvalidGroupMessages(groupThread: groupThread)
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

        Task {
            do {
                try await GroupManager.removeFromGroupOrRevokeInviteV2(groupModel: groupModel, serviceIds: serviceIdsToKick)
                Logger.info("Success.")
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
    }

    private func sendPartiallyInvalidGroupMessages(groupThread: TSGroupThread) {
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid groupModel.")
            return
        }

        var messages = [OWSDynamicOutgoingMessage]()

        let masterKey = try! groupModelV2.masterKey().serialize()
        let groupContextInfo = try! GroupV2ContextInfo.deriveFrom(masterKeyData: masterKey)

        SSKEnvironment.shared.databaseStorageRef.read { transaction in
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
                dataBuilder.setGroupV2(builder.buildInfallibly())
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
                dataBuilder.setGroupV2(builder.buildInfallibly())
                dataBuilder.setRequiredProtocolVersion(0)
                dataBuilder.setBody("Valid gv2 message.")
                return Self.contentProtoData(forDataBuilder: dataBuilder)
            })
        }

        for message in messages {
            let preparedMessage = PreparedOutgoingMessage.preprepared(transientMessageWithoutAttachments: message)
            Task { try await SSKEnvironment.shared.messageSenderRef.sendMessage(preparedMessage) }
        }
    }

    class func contentProtoData(forDataBuilder dataBuilder: SSKProtoDataMessageBuilder) -> Data {
        let dataProto = try! dataBuilder.build()
        let contentBuilder = SSKProtoContent.builder()
        contentBuilder.setDataMessage(dataProto)
        let plaintextData = try! contentBuilder.buildSerializedData()
        return plaintextData
    }
}

#endif
