//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

#if DEBUG

@objc
public extension DebugUIStress {

    // MARK: - Dependencies

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private class var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    // MARK: -

    private static func nameForClonedGroup(_ groupThread: TSGroupThread) -> String {
        guard let groupName = groupThread.groupModel.groupName else {
            return "Cloned Group"
        }
        return groupName + " Copy"
    }

    // Creates a new group (by cloning the current group) without informing the,
    // other members. This can be used to test "group info requests", etc.
    class func cloneAsV1orV2Group(_ groupThread: TSGroupThread) {
        firstly { () -> Promise<TSGroupThread> in
            let groupName = Self.nameForClonedGroup(groupThread)
            return GroupManager.localCreateNewGroup(members: groupThread.groupModel.groupMembers,
                                                    groupId: nil,
                                                    name: groupName,
                                                    avatarData: groupThread.groupModel.groupAvatarData,
                                                    newGroupSeed: nil,
                                                    shouldSendMessage: false)
        }.done { groupThread in
            Logger.info("Complete.")

            SignalApp.shared().presentConversation(for: groupThread, animated: true)
        }.catch(on: .global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    // Creates a new group (by cloning the current group) without informing the,
    // other members. This can be used to test "group info requests", etc.
    class func cloneAsV1Group(_ groupThread: TSGroupThread) {
        do {
            let groupName = Self.nameForClonedGroup(groupThread) + " (v1)"
            let groupThread = try self.databaseStorage.write { transaction in
                try GroupManager.createGroupForTests(members: groupThread.groupModel.groupMembers,
                                                     name: groupName,
                                                     avatarData: groupThread.groupModel.groupAvatarData,
                                                     groupId: nil,
                                                     groupsVersion: .V1,
                                                     transaction: transaction)
            }
            assert(groupThread.groupModel.groupsVersion == .V1)

            SignalApp.shared().presentConversation(for: groupThread, animated: true)
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

    // Creates a new group (by cloning the current group) without informing the,
    // other members. This can be used to test "group info requests", etc.
    class func cloneAsV2Group(_ groupThread: TSGroupThread) {
        firstly { () -> Promise<TSGroupThread> in
            guard FeatureFlags.groupsV2,
                RemoteConfig.groupsV2CreateGroups,
                GroupManager.defaultGroupsVersion == .V2 else {
                    throw OWSAssertionError("Groups v2 not enabled.")
            }
            let members = try self.databaseStorage.read { (transaction: SDSAnyReadTransaction) throws -> [SignalServiceAddress] in
                let members: [SignalServiceAddress] = groupThread.groupModel.groupMembers.filter { address in
                    GroupManager.doesUserSupportGroupsV2(address: address, transaction: transaction)
                }
                guard GroupManager.canUseV2(for: Set(members), transaction: transaction) else {
                    throw OWSAssertionError("Error filtering users.")
                }
                return members
            }
            let groupName = Self.nameForClonedGroup(groupThread) + " (v2)"
            return GroupManager.localCreateNewGroup(members: members,
                                                    groupId: nil,
                                                    name: groupName,
                                                    avatarData: groupThread.groupModel.groupAvatarData,
                                                    newGroupSeed: nil,
                                                    shouldSendMessage: false)
        }.done { (groupThread) in
            assert(groupThread.groupModel.groupsVersion == .V2)

            Logger.info("Complete.")

            SignalApp.shared().presentConversation(for: groupThread, animated: true)
        }.catch(on: .global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    class func addDebugMembersToGroup(_ groupThread: TSGroupThread) {

        let e164ToAdd: [String] = [
            "+16785621057"
        ]
        let membersToAdd = Set(e164ToAdd.map { SignalServiceAddress(phoneNumber: $0) })

        let oldGroupModel = groupThread.groupModel
        let newGroupModel: TSGroupModel
        do {
            newGroupModel = try databaseStorage.read { transaction in
                var builder = oldGroupModel.asBuilder
                let oldGroupMembership = oldGroupModel.groupMembership
                var groupMembershipBuilder = oldGroupMembership.asBuilder
                for address in membersToAdd {
                    assert(address.isValid)
                    guard !oldGroupMembership.isPendingOrNonPendingMember(address) else {
                        Logger.warn("Recipient is already in group.")
                        continue
                    }
                    // GroupManager will separate out members as pending if necessary.
                    groupMembershipBuilder.addNonPendingMember(address, role: .normal)
                }
                builder.groupMembership = groupMembershipBuilder.build()
                return try builder.build(transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error)")
            return
        }

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return
        }

        firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: oldGroupModel,
                                                         description: self.logTag)
        }.then(on: .global()) { _ in
            // dmConfiguration: nil means don't change disappearing messages configuration.
            GroupManager.localUpdateExistingGroup(oldGroupModel: oldGroupModel,
                                                  newGroupModel: newGroupModel,
                                                  dmConfiguration: nil,
                                                  groupUpdateSourceAddress: localAddress)
        }.done(on: .global()) { (_) in
            Logger.info("Complete.")
        }.catch(on: .global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }
}

#endif
