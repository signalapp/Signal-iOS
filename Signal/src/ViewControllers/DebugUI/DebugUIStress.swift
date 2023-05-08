//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit

#if USE_DEBUG_UI

@objc
public extension DebugUIStress {

    private static func nameForClonedGroup(_ groupThread: TSGroupThread) -> String {
        guard let groupName = groupThread.groupModel.groupName else {
            return "Cloned Group"
        }
        return groupName + " Copy"
    }

    // Creates a new group (by cloning the current group) without informing the,
    // other members. This can be used to test "group info requests", etc.
    class func cloneAsV1Group(_ oldGroupThread: TSGroupThread) {
        do {
            let groupName = Self.nameForClonedGroup(oldGroupThread) + " (v1)"
            let newGroupThread = try self.databaseStorage.write { (transaction: SDSAnyWriteTransaction) throws -> TSGroupThread in
                let newGroupThread = try GroupManager.createGroupForTests(members: oldGroupThread.groupModel.groupMembers,
                                                                          name: groupName,
                                                                          avatarData: oldGroupThread.groupModel.avatarData,
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
        firstly { () -> Promise<TSGroupThread> in
            guard GroupManager.defaultGroupsVersion == .V2 else {
                throw OWSAssertionError("Groups v2 not enabled.")
            }
            let members: [SignalServiceAddress] = oldGroupThread.groupModel.groupMembers.filter { address in
                GroupManager.doesUserSupportGroupsV2(address: address)
            }
            for member in members {
                Logger.verbose("Member: \(member)")
            }
            var groupName = Self.nameForClonedGroup(oldGroupThread) + " (v2)"
            groupName = groupName.trimToGlyphCount(GroupManager.maxGroupNameGlyphCount)

            return GroupManager.localCreateNewGroup(members: members,
                                                    groupId: nil,
                                                    name: groupName,
                                                    avatarData: oldGroupThread.groupModel.avatarData,
                                                    disappearingMessageToken: .disabledToken,
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
        }.catch(on: DispatchQueue.global()) { error in
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
        let membersToAdd = srcGroupThread.groupMembership.allMembersOfAnyKind.subtracting(dstGroupThread.groupMembership.allMembersOfAnyKind)
        let uuidsToAdd = membersToAdd.compactMap { $0.uuid }
        for uuid in uuidsToAdd {
            Logger.verbose("Adding: \(uuid)")
        }
        firstly {
            GroupManager.addOrInvite(
                aciOrPniUuids: uuidsToAdd,
                toExistingGroup: dstGroupThread.groupModel
            )
        }.done { (groupThread) in
            Logger.info("Complete.")

            SignalApp.shared().presentConversation(for: groupThread, animated: true)
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    class func addDebugMembersToGroup(_ groupThread: TSGroupThread) {
        let oldGroupModel = groupThread.groupModel

        let e164ToAdd: [String] = [
            "+16785621057"
        ]

        let uuidsToAdd = e164ToAdd
            .map { SignalServiceAddress(phoneNumber: $0) }
            .compactMap { $0.uuid }
            .filter { uuid in
                if oldGroupModel.groupMembership.isMemberOfAnyKind(uuid) {
                    Logger.warn("Recipient is already in group.")
                    return false
                }

                return true
            }

        firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: oldGroupModel,
                                                         description: self.logTag())
        }.then(on: DispatchQueue.global()) { _ in
            GroupManager.addOrInvite(
                aciOrPniUuids: uuidsToAdd,
                toExistingGroup: oldGroupModel
            )
        }.done(on: DispatchQueue.global()) { (_) in
            Logger.info("Complete.")
        }.catch(on: DispatchQueue.global()) { error in
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
        }.done(on: DispatchQueue.global()) { (_) in
            Logger.info("Complete.")
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    class func logMembership(_ groupThread: TSGroupThread) {
        let groupMembership = groupThread.groupModel.groupMembership
        let uuids = groupMembership.allMembersOfAnyKind.compactMap { $0.uuid }
        let phoneNumbers = groupMembership.allMembersOfAnyKind.compactMap { $0.phoneNumber }
        Logger.info("uuids: \(uuids.map { $0.uuidString }.joined(separator: "\n")).")
        Logger.info("phoneNumbers: \(phoneNumbers.joined(separator: "\n")).")
    }

    class func deleteOtherProfiles() {
        databaseStorage.write { transaction in
            let profiles = OWSUserProfile.anyFetchAll(transaction: transaction)
            for profile in profiles {
                guard !OWSUserProfile.isLocalProfileAddress(profile.address) else {
                    continue
                }
                Logger.verbose("Deleting: \(profile.address)")
                profile.anyRemove(transaction: transaction)
            }
        }
    }

    class func logGroupsForAddress(_ address: SignalServiceAddress) {
        Self.databaseStorage.read { transaction in
            TSGroupThread.enumerateGroupThreads(
                with: address,
                transaction: transaction
            ) { thread, _ in
                let displayName = Self.contactsManager.displayName(for: thread, transaction: transaction)
                Logger.verbose("Group[\(thread.groupId.hexadecimalString)]: \(displayName)")
            }
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
        let contactsManager = Self.contactsManager
        let databaseStorage = Self.databaseStorage

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

    @objc
    func didTapCancel() {
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
