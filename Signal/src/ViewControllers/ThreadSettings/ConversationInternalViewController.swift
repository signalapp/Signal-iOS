//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

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
        let thread = self.thread

        let infoSection = OWSTableSection()
        self.databaseStorage.read { transaction in
            let section = infoSection
            let isThreadInProfileWhitelist = Self.profileManager.isThread(inProfileWhitelist: thread,
                                                                          transaction: transaction)
            section.add(.label(withText: String(format: "Whitelisted: %@",
                                                isThreadInProfileWhitelist ? "Yes" : "No")))

            if let contactThread = thread as? TSContactThread {
                let address = contactThread.contactAddress

                section.add(.copyableItem(label: "UUID",
                                          value: address.uuid?.uuidString,
                                          accessibilityIdentifier: "uuid"))

                section.add(.copyableItem(label: "Phone Number",
                                          value: address.phoneNumber,
                                          accessibilityIdentifier: "phoneNumber"))

                let profileKey = profileManager.profileKeyData(for: address, transaction: transaction)
                section.add(.copyableItem(label: "Profile Key",
                                          value: profileKey?.hexadecimalString,
                                          accessibilityIdentifier: "profile_key"))

                let identityKey = identityManager.recipientIdentity(for: address,
                                                                    transaction: transaction)?.identityKey
                section.add(.copyableItem(label: "Identity Key",
                                          value: identityKey?.hexadecimalString,
                                          accessibilityIdentifier: "identity_key"))

                var canReceiveGiftBadgesString: String
                if let profile = profileManager.getUserProfile(for: address, transaction: transaction) {
                    canReceiveGiftBadgesString = profile.canReceiveGiftBadges ? "Yes" : "No"
                } else {
                    canReceiveGiftBadgesString = "Profile not found!"
                }
                section.add(.label(withText: String(format: "Can Receive Gift Badges? %@",
                                                    canReceiveGiftBadgesString)))

                let arePaymentsEnabled = paymentsHelper.arePaymentsEnabled(for: address,
                                                                     transaction: transaction)
                section.add(.label(withText: String(format: "Payments Enabled: %@",
                                                    arePaymentsEnabled ? "Yes" : "No")))

            } else {
                owsFailDebug("Invalid thread.")
            }

            section.add(.copyableItem(label: "thread.uniqueId",
                                      value: thread.uniqueId,
                                      accessibilityIdentifier: "thread.uniqueId"))
        }
        contents.addSection(infoSection)

        if let contactThread = thread as? TSContactThread {
            let address = contactThread.contactAddress
            let actionSection = OWSTableSection()
            let section = actionSection

            section.add(.actionItem(withText: "Fetch Profile") {
                ProfileFetcherJob.fetchProfile(address: address, ignoreThrottling: true)
            })

            contents.addSection(actionSection)
        }

        self.contents = contents
    }

    // MARK: - Helpers

    public override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }
}
