//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class BlockListViewController: OWSTableViewController2 {

    override init() {
        super.init()

        title = NSLocalizedString(
            "SETTINGS_BLOCK_LIST_TITLE",
            comment: "Label for the block list section of the settings view",
        )
    }

    override func viewDidLoad() {
        updateContactList(reloadTableView: false)

        super.viewDidLoad()

        SUIEnvironment.shared.contactsViewHelperRef.addObserver(self)

        tableView.estimatedRowHeight = 60
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)
    }

    private func updateContactList(reloadTableView: Bool) {
        let contents = OWSTableContents()

        // "Add" section
        let sectionAddContact = OWSTableSection(items: [
            OWSTableItem.disclosureItem(
                withText: NSLocalizedString(
                    "SETTINGS_BLOCK_LIST_ADD_BUTTON",
                    comment: "A label for the 'add phone number' button in the block list table.",
                ),
                actionBlock: { [weak self] in
                    let viewController = AddToBlockListViewController()
                    viewController.delegate = self
                    self?.navigationController?.pushViewController(viewController, animated: true)
                },
            ),
        ])
        sectionAddContact.footerTitle = NSLocalizedString(
            "BLOCK_USER_BEHAVIOR_EXPLANATION",
            comment: "An explanation of the consequences of blocking another user.",
        )
        contents.add(sectionAddContact)

        let addresses: [SignalServiceAddress]
        let groups: [(groupId: Data, groupName: String, groupModel: TSGroupModel?, groupAvatarImage: UIImage?)]
        (addresses, groups) = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let avatarBuilder = SSKEnvironment.shared.avatarBuilderRef
            let blockingManager = SSKEnvironment.shared.blockingManagerRef
            let contactManager = SSKEnvironment.shared.contactManagerRef
            let addresses = contactManager.sortSignalServiceAddresses(
                blockingManager.blockedAddresses(transaction: transaction),
                transaction: transaction,
            )
            let groups: [(groupId: Data, groupName: String, groupModel: TSGroupModel?, groupAvatarImage: UIImage?)]
            groups = blockingManager.blockedGroupIds(transaction: transaction).map { groupId in
                let groupModel = TSGroupThread.fetch(groupId: groupId, transaction: transaction)?.groupModel
                let groupName = groupModel?.groupNameOrDefault ?? TSGroupThread.defaultGroupName
                let groupAvatarImage: UIImage? = {
                    if let avatarData = groupModel?.avatarDataState.dataIfPresent {
                        return UIImage(data: avatarData)
                    }

                    return avatarBuilder.defaultAvatarImage(
                        forGroupId: groupId,
                        diameterPoints: AvatarBuilder.standardAvatarSizePoints,
                        transaction: transaction,
                    )
                }()
                return (groupId, groupName, groupModel, groupAvatarImage)
            }.sorted(by: {
                switch $0.groupName.localizedCaseInsensitiveCompare($1.groupName) {
                case .orderedAscending:
                    return true
                case .orderedDescending:
                    return false
                case .orderedSame:
                    return $0.groupId.hexadecimalString < $0.groupId.hexadecimalString
                }
            })
            return (addresses, groups)
        }

        // Contacts
        let contactsSectionItems = addresses.map { address in
            OWSTableItem(
                dequeueCellBlock: { [weak self] tableView in
                    let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as! ContactTableViewCell
                    let config = ContactCellConfiguration(
                        address: address,
                        localUserDisplayMode: .asUser,
                    )
                    if self != nil {
                        SSKEnvironment.shared.databaseStorageRef.read { transaction in
                            cell.configure(configuration: config, transaction: transaction)
                        }
                    }
                    cell.accessibilityIdentifier = "BlockListViewController.user"
                    return cell
                },
                actionBlock: { [weak self] in
                    guard let self else { return }
                    BlockListUIUtils.showUnblockAddressActionSheet(address, from: self) { isBlocked in
                        if !isBlocked {
                            // Reload if unblocked.
                            self.updateContactList(reloadTableView: true)
                        }
                    }
                },
            )
        }
        if !contactsSectionItems.isEmpty {
            contents.add(OWSTableSection(
                title: NSLocalizedString(
                    "BLOCK_LIST_BLOCKED_USERS_SECTION",
                    comment: "Section header for users that have been blocked",
                ),
                items: contactsSectionItems,
            ))
        }

        // Groups
        let groupsSectionItems = groups.map { groupId, groupName, groupModel, groupAvatarImage in
            return OWSTableItem(
                customCellBlock: {
                    let cell = AvatarTableViewCell()
                    cell.configure(image: groupAvatarImage, text: groupName)
                    return cell
                },
                actionBlock: { [weak self] in
                    guard let self else { return }
                    BlockListUIUtils.showUnblockGroupActionSheet(groupId: groupId, groupNameOrDefault: groupName, from: self) { isBlocked in
                        if !isBlocked {
                            self.updateContactList(reloadTableView: true)
                        }
                    }
                },
            )
        }
        if !groupsSectionItems.isEmpty {
            contents.add(OWSTableSection(
                title: NSLocalizedString(
                    "BLOCK_LIST_BLOCKED_GROUPS_SECTION",
                    comment: "Section header for groups that have been blocked",
                ),
                items: groupsSectionItems,
            ))
        }

        setContents(contents, shouldReload: reloadTableView)
    }
}

extension BlockListViewController: ContactsViewHelperObserver {

    func contactsViewHelperDidUpdateContacts() {
        updateContactList(reloadTableView: true)
    }
}

extension BlockListViewController: AddToBlockListDelegate {

    func addToBlockListComplete() {
        navigationController?.popToViewController(self, animated: true)
    }
}
