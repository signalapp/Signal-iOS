//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

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
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let section = infoSection

            let isThreadInProfileWhitelist = SSKEnvironment.shared.profileManagerRef.isThread(
                inProfileWhitelist: thread, transaction: transaction
            )
            section.add(.copyableItem(
                label: "Whitelisted",
                value: isThreadInProfileWhitelist ? "Yes" : "No"
            ))

            if let contactThread = thread as? TSContactThread {
                let address = contactThread.contactAddress

                let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
                let signalRecipient = recipientDatabaseTable.fetchRecipient(address: address, tx: transaction.asV2Read)

                section.add(.copyableItem(
                    label: "ACI",
                    value: signalRecipient?.aci?.serviceIdString
                ))

                section.add(.copyableItem(
                    label: "Phone Number",
                    value: signalRecipient?.phoneNumber?.stringValue
                ))

                section.add(.copyableItem(
                    label: "PNI",
                    value: signalRecipient?.pni?.serviceIdString
                ))

                section.add(.copyableItem(
                    label: "Discoverable Phone Number?",
                    value: signalRecipient?.phoneNumber?.isDiscoverable == true ? "Yes" : "No"
                ))

                let userProfile = SSKEnvironment.shared.profileManagerRef.getUserProfile(for: address, transaction: transaction)

                section.add(.copyableItem(
                    label: "Sharing Phone Number?",
                    value: {
                        switch userProfile?.isPhoneNumberShared {
                        case .some(true):
                            return "Yes"
                        case .some(false):
                            return "No"
                        case .none:
                            return "!isProfileNameKnown"
                        }
                    }()
                ))

                section.add(.copyableItem(
                    label: "Profile Key",
                    value: userProfile?.profileKey?.keyData.hexadecimalString
                ))

                let identityManager = DependenciesBridge.shared.identityManager
                let identityKey = identityManager.recipientIdentity(for: address, tx: transaction.asV2Read)?.identityKey
                section.add(.copyableItem(
                    label: "Identity Key",
                    value: identityKey?.hexadecimalString
                ))

                let arePaymentsEnabled = SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled(for: address, transaction: transaction)
                section.add(.copyableItem(
                    label: "Payments",
                    value: arePaymentsEnabled ? "Yes" : "No"
                ))

            } else {
                // Nothing extra to show for groups.
            }

            section.add(.copyableItem(
                label: "DB Unique ID",
                value: thread.uniqueId
            ))
        }
        contents.add(infoSection)

        if let contactThread = thread as? TSContactThread {
            let address = contactThread.contactAddress
            let actionSection = OWSTableSection()
            let section = actionSection

            section.add(.actionItem(withText: "Fetch Profile") {
                Task {
                    let profileFetcher = SSKEnvironment.shared.profileFetcherRef
                    _ = try? await profileFetcher.fetchProfile(for: address.serviceId!)
                }
            })

            contents.add(actionSection)

            let sessionSection = OWSTableSection()
            sessionSection.add(.actionItem(withText: "Delete Session") {
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    let aciStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci)
                    aciStore.sessionStore.deleteAllSessions(for: address.serviceId!, tx: transaction.asV2Write)
                }
            })

            contents.add(sessionSection)
        }

        self.contents = contents
    }

    // MARK: - Helpers

    public override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }
}
