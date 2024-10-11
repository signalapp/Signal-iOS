//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUIStress: DebugUIPage {

    private let contactsManager: any ContactManager
    private let databaseStorage: SDSDatabaseStorage
    private let messageSender: MessageSender

    init(
        contactsManager: any ContactManager,
        databaseStorage: SDSDatabaseStorage,
        messageSender: MessageSender
    ) {
        self.contactsManager = contactsManager
        self.databaseStorage = databaseStorage
        self.messageSender = messageSender
    }

    let name = "Stress"

    func section(thread: TSThread?) -> OWSTableSection? {
        var items = [OWSTableItem]()

        if let thread {
            items.append(OWSTableItem(title: "Send empty message", actionBlock: { [weak self] in
                self?.sendStressMessage(toThread: thread, block: { return Data() })
            }))
            items.append(OWSTableItem(title: "Send random noise message", actionBlock: { [weak self] in
                self?.sendStressMessage(toThread: thread, block: {
                    return Randomness.generateRandomBytes(.random(in: 0...31))
                })
            }))
            items.append(OWSTableItem(title: "Send no payload message", actionBlock: { [weak self] in
                self?.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send empty null message", actionBlock: { [weak self] in
                self?.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    if let nullMessage = SSKProtoNullMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setNullMessage(nullMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))

            // Sync

            items.append(OWSTableItem(title: "Send empty sync message", actionBlock: { [weak self] in
                self?.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    if let syncMessage = SSKProtoSyncMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setSyncMessage(syncMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send empty sync sent message", actionBlock: { [weak self] in
                self?.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let syncMessageBuilder = SSKProtoSyncMessage.builder()
                    if let syncSentMessage = SSKProtoSyncMessageSent.builder().buildIgnoringErrors() {
                        syncMessageBuilder.setSent(syncSentMessage)
                    }
                    if let syncMessage = SSKProtoSyncMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setSyncMessage(syncMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send malformed sync sent message 1", actionBlock: { [weak self] in
                self?.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let syncMessageBuilder = SSKProtoSyncMessage.builder()
                    let syncSentMessageBuilder = SSKProtoSyncMessageSent.builder()
                    syncSentMessageBuilder.setDestinationServiceID("abc")
                    syncSentMessageBuilder.setTimestamp(.random(in: 1...32))
                    if let message = SSKProtoDataMessage.builder().buildIgnoringErrors() {
                        syncSentMessageBuilder.setMessage(message)
                    }
                    if let syncSentMessage = syncSentMessageBuilder.buildIgnoringErrors() {
                        syncMessageBuilder.setSent(syncSentMessage)
                    }
                    if let syncMessage = SSKProtoSyncMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setSyncMessage(syncMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send malformed sync sent message 2", actionBlock: { [weak self] in
                self?.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let syncMessageBuilder = SSKProtoSyncMessage.builder()
                    let syncSentMessageBuilder = SSKProtoSyncMessageSent.builder()
                    syncSentMessageBuilder.setDestinationServiceID("abc")
                    syncSentMessageBuilder.setTimestamp(0)
                    if let message = SSKProtoDataMessage.builder().buildIgnoringErrors() {
                        syncSentMessageBuilder.setMessage(message)
                    }
                    if let syncSentMessage = syncSentMessageBuilder.buildIgnoringErrors() {
                        syncMessageBuilder.setSent(syncSentMessage)
                    }
                    if let syncMessage = SSKProtoSyncMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setSyncMessage(syncMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send malformed sync sent message 3", actionBlock: { [weak self] in
                self?.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let syncMessageBuilder = SSKProtoSyncMessage.builder()
                    let syncSentMessageBuilder = SSKProtoSyncMessageSent.builder()
                    syncSentMessageBuilder.setDestinationServiceID("abc")
                    syncSentMessageBuilder.setTimestamp(0)
                    let dataMessageBuilder = SSKProtoDataMessage.builder()
                    dataMessageBuilder.setBody(" ")
                    if let message = dataMessageBuilder.buildIgnoringErrors() {
                        syncSentMessageBuilder.setMessage(message)
                    }
                    if let syncSentMessage = syncSentMessageBuilder.buildIgnoringErrors() {
                        syncMessageBuilder.setSent(syncSentMessage)
                    }
                    if let syncMessage = SSKProtoSyncMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setSyncMessage(syncMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send malformed sync sent message 5", actionBlock: { [weak self] in
                self?.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let syncMessageBuilder = SSKProtoSyncMessage.builder()
                    let syncSentMessageBuilder = SSKProtoSyncMessageSent.builder()
                    syncSentMessageBuilder.setDestinationServiceID("abc")
                    if let syncSentMessage = syncSentMessageBuilder.buildIgnoringErrors() {
                        syncMessageBuilder.setSent(syncSentMessage)
                    }
                    if let syncMessage = SSKProtoSyncMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setSyncMessage(syncMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
        }

        // Groups

        if let groupThread = thread as? TSGroupThread {
            items.append(OWSTableItem(title: "Copy members to another group", actionBlock: { [weak self] in
                guard let fromViewController = UIApplication.shared.frontmostViewController else { return }
                self?.copyToAnotherGroup(groupThread, fromViewController: fromViewController)
            }))
            items.append(OWSTableItem(title: "Log membership", actionBlock: {
                DebugUIStress.logMembership(groupThread)
            }))
        }

        items.append(OWSTableItem(title: "Make group w. unregistered users", actionBlock: {
            Task {
                try await DebugUIStress.makeUnregisteredGroup()
            }
        }))

        // Other
        items.append(OWSTableItem(title: "Delete other profiles", actionBlock: { [weak self] in
            self?.deleteOtherProfiles()
        }))
        if let contactThread = thread as? TSContactThread {
            items.append(OWSTableItem(title: "Log groups for contact", actionBlock: { [weak self] in
                self?.logGroupsForAddress(contactThread.contactAddress)
            }))
        }

        return OWSTableSection(title: name, items: items)
    }

    // MARK: -

    private func sendStressMessage(
        toThread thread: TSThread,
        block: @escaping DynamicOutgoingMessageBlock
    ) {
        let message = databaseStorage.read { transaction in
            OWSDynamicOutgoingMessage(
                thread: thread,
                transaction: transaction,
                plainTextDataBlock: block
            )
        }
        Task {
            do {
                let preparedMessage = PreparedOutgoingMessage.preprepared(transientMessageWithoutAttachments: message)
                try await self.messageSender.sendMessage(preparedMessage)
                Logger.info("Success.")
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
    }

    // MARK: Groups

    @MainActor
    private static func makeUnregisteredGroup() async throws {
        var recipientAddresses = [SignalServiceAddress]()

        recipientAddresses.append(contentsOf: (0...2).map { _ in SignalServiceAddress(Aci(fromUUID: UUID())) })

        if let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress {
            recipientAddresses.append(localAddress)
        }

        recipientAddresses.append(contentsOf: (0...2).map { _ in SignalServiceAddress(Aci(fromUUID: UUID())) })

        let groupThread = try await GroupManager.localCreateNewGroup(
            members: recipientAddresses,
            name: UUID().uuidString,
            disappearingMessageToken: .disabledToken,
            shouldSendMessage: false
        )
        SignalApp.shared.presentConversationForThread(groupThread, animated: true)
    }

    private func copyToAnotherGroup(_ srcGroupThread: TSGroupThread, fromViewController: UIViewController) {
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

    private static func copyToAnotherGroup(srcGroupThread: TSGroupThread, dstGroupThread: TSGroupThread) {
        let membersToAdd = srcGroupThread.groupMembership.allMembersOfAnyKind.subtracting(dstGroupThread.groupMembership.allMembersOfAnyKind)
        let serviceIdsToAdd = membersToAdd.compactMap { $0.serviceId }
        for serviceId in serviceIdsToAdd {
            Logger.verbose("Adding: \(serviceId)")
        }
        Task { @MainActor in
            do {
                let groupThread = try await GroupManager.addOrInvite(
                    serviceIds: serviceIdsToAdd,
                    toExistingGroup: dstGroupThread.groupModel
                )
                Logger.info("Complete.")
                SignalApp.shared.presentConversationForThread(groupThread, animated: true)
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
    }

    private static func logMembership(_ groupThread: TSGroupThread) {
        let groupMembership = groupThread.groupModel.groupMembership
        let addressStrings = groupMembership.allMembersOfAnyKind.map { $0.description }
        Logger.info("addresses: \(addressStrings.joined(separator: "\n"))")
    }

    private func deleteOtherProfiles() {
        databaseStorage.write { transaction in
            let profiles = OWSUserProfile.anyFetchAll(transaction: transaction)
            for profile in profiles {
                switch profile.internalAddress {
                case .localUser:
                    continue
                case .otherUser(let address):
                    Logger.verbose("Deleting: \(address)")
                    profile.anyRemove(transaction: transaction)
                }
            }
        }
    }

    private func logGroupsForAddress(_ address: SignalServiceAddress) {
        databaseStorage.read { transaction in
            TSGroupThread.enumerateGroupThreads(
                with: address,
                transaction: transaction
            ) { thread, _ in
                let displayName = contactsManager.displayName(for: thread, transaction: transaction)
                Logger.verbose("Group[\(thread.groupId.hexadecimalString)]: \(displayName)")
            }
        }
    }
}

// MARK: -

private class GroupThreadPicker: OWSTableViewController {

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

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel)
        )
    }

    private func rebuildTableContents() {
        let contactsManager = SSKEnvironment.shared.contactManagerRef
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef

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
        contents.add(section)
        self.contents = contents
    }

    // MARK: - Actions

    @objc
    private func didTapCancel() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }

    private func didSelectGroupThread(_ groupThread: TSGroupThread) {
        let completion = self.completion
        presentingViewController?.dismiss(animated: true) {
            completion(groupThread)
        }
    }
}

#endif
