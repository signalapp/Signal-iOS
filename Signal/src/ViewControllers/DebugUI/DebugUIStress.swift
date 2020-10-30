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
        return .shared()
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
    class func cloneAsV1orV2Group(_ oldGroupThread: TSGroupThread) {
        firstly { () -> Promise<TSGroupThread> in
            let groupName = Self.nameForClonedGroup(oldGroupThread)
            return GroupManager.localCreateNewGroup(members: oldGroupThread.groupModel.groupMembers,
                                                    groupId: nil,
                                                    name: groupName,
                                                    avatarData: oldGroupThread.groupModel.groupAvatarData,
                                                    newGroupSeed: nil,
                                                    shouldSendMessage: false)
        }.done { newGroupThread in

            self.databaseStorage.write { transaction in
                let oldDMConfig = oldGroupThread.disappearingMessagesConfiguration(with: transaction)
                _ = OWSDisappearingMessagesConfiguration.applyToken(oldDMConfig.asToken,
                                                                    toThread: newGroupThread,
                                                                    transaction: transaction)
            }

            Logger.info("Complete.")

            SignalApp.shared().presentConversation(for: newGroupThread, animated: true)
        }.catch(on: .global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    // Creates a new group (by cloning the current group) without informing the,
    // other members. This can be used to test "group info requests", etc.
    class func cloneAsV1Group(_ oldGroupThread: TSGroupThread) {
        do {
            let groupName = Self.nameForClonedGroup(oldGroupThread) + " (v1)"
            let newGroupThread = try self.databaseStorage.write { (transaction: SDSAnyWriteTransaction) throws -> TSGroupThread in
                let newGroupThread = try GroupManager.createGroupForTests(members: oldGroupThread.groupModel.groupMembers,
                                                                          name: groupName,
                                                                          avatarData: oldGroupThread.groupModel.groupAvatarData,
                                                                          groupId: nil,
                                                                          groupsVersion: .V1,
                                                                          transaction: transaction)

                let oldDMConfig = oldGroupThread.disappearingMessagesConfiguration(with: transaction)
                _ = OWSDisappearingMessagesConfiguration.applyToken(oldDMConfig.asToken,
                                                                    toThread: newGroupThread,
                                                                    transaction: transaction)

                return newGroupThread
            }
            assert(newGroupThread.groupModel.groupsVersion == .V1)

            SignalApp.shared().presentConversation(for: newGroupThread, animated: true)
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

    // Creates a new group (by cloning the current group) without informing the,
    // other members. This can be used to test "group info requests", etc.
    class func cloneAsV2Group(_ oldGroupThread: TSGroupThread) {
        firstly { () -> Promise<Void> in
            let members: [SignalServiceAddress] = oldGroupThread.groupModel.groupMembers
            for member in members {
                Logger.verbose("Candidate member: \(member)")
            }
            return GroupManager.tryToEnableGroupsV2(for: members, isBlocking: true, ignoreErrors: true)
        }.then { () -> Promise<TSGroupThread> in
            guard GroupManager.defaultGroupsVersion == .V2 else {
                throw OWSAssertionError("Groups v2 not enabled.")
            }
            let members = try self.databaseStorage.read { (transaction: SDSAnyReadTransaction) throws -> [SignalServiceAddress] in
                let members: [SignalServiceAddress] = oldGroupThread.groupModel.groupMembers.filter { address in
                    GroupManager.doesUserSupportGroupsV2(address: address, transaction: transaction)
                }
                guard GroupManager.canUseV2(for: Set(members), transaction: transaction) else {
                    throw OWSAssertionError("Error filtering users.")
                }
                return members
            }
            for member in members {
                Logger.verbose("Member: \(member)")
            }
            let groupName = Self.nameForClonedGroup(oldGroupThread) + " (v2)"
            return GroupManager.localCreateNewGroup(members: members,
                                                    groupId: nil,
                                                    name: groupName,
                                                    avatarData: oldGroupThread.groupModel.groupAvatarData,
                                                    newGroupSeed: nil,
                                                    shouldSendMessage: false)
        }.done { (newGroupThread) in
            assert(newGroupThread.groupModel.groupsVersion == .V2)

            self.databaseStorage.write { transaction in
                let oldDMConfig = oldGroupThread.disappearingMessagesConfiguration(with: transaction)
                _ = OWSDisappearingMessagesConfiguration.applyToken(oldDMConfig.asToken,
                                                                    toThread: newGroupThread,
                                                                    transaction: transaction)
            }

            Logger.info("Complete.")

            SignalApp.shared().presentConversation(for: newGroupThread, animated: true)
        }.catch(on: .global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    class func copyToAnotherGroup(_ srcGroupThread: TSGroupThread, fromViewController: UIViewController) {
        let groupThreads = self.databaseStorage.read { (transaction: SDSAnyReadTransaction) -> [TSGroupThread] in
            TSThread.anyFetchAll(transaction: transaction).compactMap { $0 as? TSGroupThread }
        }
        guard !groupThreads.isEmpty else {
            owsFailDebug("No groups.")
            return
        }
        let groupThreadPicker = GroupThreadPicker(groupThreads: groupThreads) { (dstGroupThread: TSGroupThread) in
            Self.copyToAnotherGroup(srcGroupThread: srcGroupThread, dstGroupThread: dstGroupThread)
        }
        fromViewController.present(groupThreadPicker, animated: true)
    }

    class func copyToAnotherGroup(srcGroupThread: TSGroupThread, dstGroupThread: TSGroupThread) {
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return
        }

        let membersToAdd = srcGroupThread.groupMembership.allMembersOfAnyKind.subtracting(dstGroupThread.groupMembership.allMembersOfAnyKind)
        firstly { () -> Promise<Void> in
            for member in membersToAdd {
                Logger.verbose("Candidate member: \(member)")
            }
            return GroupManager.tryToEnableGroupsV2(for: Array(membersToAdd), isBlocking: true, ignoreErrors: true)
        }.then { () -> Promise<TSGroupThread> in
            let oldGroupModel = dstGroupThread.groupModel
            let newGroupModel = try self.databaseStorage.read { (transaction: SDSAnyReadTransaction) throws -> TSGroupModel in
                let validMembersToAdd: [SignalServiceAddress]
                if dstGroupThread.isGroupV1Thread {
                    validMembersToAdd = membersToAdd.filter { $0.phoneNumber != nil }
                } else {
                    validMembersToAdd = membersToAdd.filter { address in
                        GroupManager.doesUserSupportGroupsV2(address: address, transaction: transaction)
                    }
                }

                for member in validMembersToAdd {
                    Logger.verbose("Adding: \(member)")
                }
                Logger.verbose("Adding: \(validMembersToAdd.count)")
                guard !validMembersToAdd.isEmpty else {
                    throw OWSAssertionError("No valid members to add.")
                }

                var groupModelBuilder = oldGroupModel.asBuilder
                var groupMembershipBuilder = oldGroupModel.groupMembership.asBuilder
                groupMembershipBuilder.addFullMembers(Set(validMembersToAdd), role: .`normal`)
                groupModelBuilder.groupMembership = groupMembershipBuilder.build()
                return try groupModelBuilder.build(transaction: transaction)
            }
            guard oldGroupModel.groupsVersion == newGroupModel.groupsVersion else {
                throw OWSAssertionError("Group Version failure.")
            }

            return GroupManager.localUpdateExistingGroup(oldGroupModel: oldGroupModel,
                                                         newGroupModel: newGroupModel,
                                                         dmConfiguration: nil,
                                                         groupUpdateSourceAddress: localAddress)
        }.done { (groupThread) in
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
                    guard !oldGroupMembership.isMemberOfAnyKind(address) else {
                        Logger.warn("Recipient is already in group.")
                        continue
                    }
                    // GroupManager will separate out members as pending if necessary.
                    groupMembershipBuilder.addFullMember(address, role: .normal)
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
                                                         description: self.logTag())
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

    class func makeAllMembersAdmin(_ groupThread: TSGroupThread) {
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid group model.")
            return
        }
        let uuids = groupModelV2.groupMembership.fullMembers.compactMap { $0.uuid }
        firstly { () -> Promise<TSGroupThread> in
            GroupManager.changeMemberRolesV2(groupModel: groupModelV2, uuids: uuids, role: .administrator)
        }.done(on: .global()) { (_) in
            Logger.info("Complete.")
        }.catch(on: .global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }
}

// MARK: -

class GroupThreadPicker: OWSTableViewController {

    private let groupThreads: [TSGroupThread]
    private let completion: (TSGroupThread) -> Void

    init(groupThreads: [TSGroupThread], completion: @escaping (TSGroupThread) -> Void) {
        self.groupThreads = groupThreads
        self.completion = completion

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Select Destination Group"

        rebuildTableContents()
        setupNavigationBar()
        applyTheme()
    }

    // MARK: - Data providers

    func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: CommonStrings.cancelButton,
            style: .plain,
            target: self,
            action: #selector(didTapCancel)
        )
    }

    func rebuildTableContents() {
        let contactsManager = SSKEnvironment.shared.contactsManager
        let databaseStorage = SSKEnvironment.shared.databaseStorage

        let contents = OWSTableContents()
        let section = OWSTableSection()
        section.headerTitle = "Select a group to add the members to"

        databaseStorage.read { transaction in
            let sortedGroupThreads = self.groupThreads.sorted { (left, right) -> Bool in
                left.lastInteractionRowId > right.lastInteractionRowId
            }
            for groupThread in sortedGroupThreads {
                let groupName = contactsManager.displayName(for: groupThread, transaction: transaction)
                section.add(OWSTableItem.actionItem(withText: groupName) { [weak self] in
                    self?.didSelectGroupThread(groupThread)
                })
            }
        }
        contents.addSection(section)
        self.contents = contents
    }

    // MARK: - Actions

    @objc func didTapCancel() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }

    func didSelectGroupThread(_ groupThread: TSGroupThread) {
        let completion = self.completion
        presentingViewController?.dismiss(animated: true) {
            completion(groupThread)
        }
    }
}

#endif
