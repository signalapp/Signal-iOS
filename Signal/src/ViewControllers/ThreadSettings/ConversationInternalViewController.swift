//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class ConversationInternalViewController: OWSTableViewController2 {

    private let thread: TSThread

    init(thread: TSThread) {
        self.thread = thread

        super.init()
    }

    // MARK: -

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = "Internal"

        updateTableContents()
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        let contents = OWSTableContents()
        let section = OWSTableSection()

        func addCopyableItem(title: String,
                             value: String?,
                             accessibilityIdentifier: String) {
            section.add(.actionItem(name: title,
                                    accessoryText: value ?? "Unknown",
                                    accessibilityIdentifier: accessibilityIdentifier) { [weak self] in
                                        if let value = value {
                                            UIPasteboard.general.string = value
                                            self?.presentToast(text: "Copied to Pasteboard")
                                        }
                                    })
        }

        let thread = self.thread
        self.databaseStorage.read { transaction in
            let isThreadInProfileWhitelist = Self.profileManager.isThread(inProfileWhitelist: thread,
                                                                          transaction: transaction)
            section.add(.label(withText: String(format: "Whitelisted: %@",
                                                isThreadInProfileWhitelist ? "Yes" : "No")))

            if let contactThread = thread as? TSContactThread {
                let address = contactThread.contactAddress

                addCopyableItem(title: "UUID",
                                value: address.uuid?.uuidString,
                                accessibilityIdentifier: "uuid")

                addCopyableItem(title: "Phone Number",
                                value: address.phoneNumber,
                                accessibilityIdentifier: "phoneNumber")

                let profileKey = profileManager.profileKeyData(for: address, transaction: transaction)
                addCopyableItem(title: "Profile Key",
                                value: profileKey?.hexadecimalString,
                                accessibilityIdentifier: "profile_key")

                let identityKey = identityManager.recipientIdentity(for: address,
                                                                    transaction: transaction)?.identityKey
                addCopyableItem(title: "Identity Key",
                                value: identityKey?.hexadecimalString,
                                accessibilityIdentifier: "identity_key")

                var capabilities = [String]()
                if GroupManager.doesUserHaveGroupsV2Capability(address: address,
                                                               transaction: transaction) {
                    capabilities.append("gv2")
                }
                if GroupManager.doesUserHaveGroupsV2MigrationCapability(address: address,
                                                                        transaction: transaction) {
                    capabilities.append("migration")
                }
                section.add(.label(withText: String(format: "Capabilities: %@",
                                                    capabilities.joined(separator: ", "))))

                let arePaymentsEnabled = payments.arePaymentsEnabled(for: address,
                                                                     transaction: transaction)
                section.add(.label(withText: String(format: "Payments Enabled: %@",
                                                    arePaymentsEnabled ? "Yes" : "No")))
            } else if let groupThread = thread as? TSGroupThread {
                addCopyableItem(title: "Group id",
                                value: groupThread.groupId.hexadecimalString,
                                accessibilityIdentifier: "group_id")
            } else {
                owsFailDebug("Invalid thread.")
            }

            addCopyableItem(title: "thread.uniqueId",
                            value: thread.uniqueId,
                            accessibilityIdentifier: "thread.uniqueId")
        }

        contents.addSection(section)

        self.contents = contents
    }

    // MARK: - Helpers

    public override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }
}
