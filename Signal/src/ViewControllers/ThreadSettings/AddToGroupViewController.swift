//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

final class AddToGroupViewController: OWSTableViewController2, UISearchResultsUpdating {

    private let address: SignalServiceAddress

    init(address: SignalServiceAddress) {
        self.address = address
        super.init()
    }

    class func presentForUser(
        _ address: SignalServiceAddress,
        from fromViewController: UIViewController,
    ) {
        AssertIsOnMainThread()

        let view = AddToGroupViewController(address: address)
        let modal = OWSNavigationController(rootViewController: view)
        fromViewController.presentFormSheet(modal, animated: true)
    }

    // MARK: -

    private let searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.hidesNavigationBarDuringPresentation = false
        return controller
    }()

    private let collation = UILocalizedIndexedCollation.current()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("ADD_TO_GROUP_TITLE", comment: "Title of the 'add to group' view.")

        navigationItem.rightBarButtonItem = .cancelButton(dismissingFrom: self)

        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing

        tableView.sectionIndexColor = UIColor.Signal.label

        Task {
            await self.updateGroupThreads()
        }
    }

    private var searchText: String? {
        didSet {
            guard oldValue != searchText else { return }
            updateTableContents()
        }
    }

    private var groupThreads = [TSGroupThread]() {
        didSet {
            AssertIsOnMainThread()
            updateTableContents()
        }
    }

    private func updateGroupThreads() async {
        let groupThreads = await fetchGroupThreads()
        self.groupThreads = groupThreads.sorted {
            $0.groupNameOrDefault.localizedCaseInsensitiveCompare($1.groupNameOrDefault) == .orderedAscending
        }
    }

    @concurrent
    private func fetchGroupThreads() async -> [TSGroupThread] {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        return databaseStorage.read { transaction in
            var result = [TSGroupThread]()

            ThreadFinder().enumerateGroupThreads(tx: transaction) { groupThread -> Bool in
                if groupThread.isGroupV2Thread {
                    let groupViewHelper = GroupViewHelper(
                        threadViewModel: ThreadViewModel(
                            thread: groupThread,
                            forChatList: false,
                            transaction: transaction,
                        ),
                        memberLabelCoordinator: nil,
                    )

                    if groupViewHelper.canEditConversationMembership {
                        result.append(groupThread)
                    }
                }

                return true
            }

            return result
        }
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        let alreadyAMemberText = OWSLocalizedString(
            "ADD_TO_GROUP_ALREADY_A_MEMBER",
            comment: "Text indicating your contact is already a member of the group on the 'add to group' view.",
        )

        let db = DependenciesBridge.shared.db
        let groups: [(thread: TSGroupThread, isAlreadyAMember: Bool, subtitle: String)] = db.read { tx in
            groupThreads.compactMap { thread in
                guard
                    searchText.map({
                        thread.groupNameOrDefault.localizedCaseInsensitiveContains($0)
                    }) ?? true
                else {
                    return nil
                }

                let isAlreadyAMember: Bool
                if let serviceId = self.address.serviceId {
                    switch thread.groupMembership.canTryToAddToGroup(serviceId: serviceId) {
                    case .alreadyInGroup:
                        isAlreadyAMember = true
                    case .addableWithProfileKeyCredential:
                        let canAddToGroup = GroupMembership.canTryToAddWithProfileKeyCredential(serviceId: serviceId, tx: tx)
                        isAlreadyAMember = !canAddToGroup
                    case .addableOrInvitable:
                        isAlreadyAMember = false
                    }
                } else {
                    isAlreadyAMember = false
                }
                let subtitle = if isAlreadyAMember {
                    alreadyAMemberText
                } else {
                    GroupViewUtils.membersNamesPreview(for: thread, tx: tx)
                }
                return (thread, isAlreadyAMember, subtitle)
            }
        }

        func item(thread: TSGroupThread, isAlreadyAMember: Bool, subtitle: String) -> OWSTableItem {
            OWSTableItem(
                customCellBlock: {
                    let cell = GroupTableViewCell()
                    cell.configure(
                        thread: thread,
                        customSubtitle: subtitle,
                        customTextColor: isAlreadyAMember ? .Signal.tertiaryLabel : nil,
                    )
                    cell.isUserInteractionEnabled = !isAlreadyAMember
                    return cell
                },
                actionBlock: { [weak self] in
                    self?.didSelectGroup(thread)
                },
            )
        }

        if searchText != nil {
            let items = groups.map { group in item(
                thread: group.thread,
                isAlreadyAMember: group.isAlreadyAMember,
                subtitle: group.subtitle,
            ) }
            self.contents = OWSTableContents(sections: [OWSTableSection(items: items)])
        } else {
            let sections = collation.sectionTitles.map(OWSTableSection.init(title:))
            for group in groups {
                // `collation` needs a class and selector, so use NSString
                let sectionIndex = collation.section(
                    for: group.thread.groupNameOrDefault as NSString,
                    collationStringSelector: #selector(getter: NSObjectProtocol.description),
                )
                sections[safe: sectionIndex]?.add(item(
                    thread: group.thread,
                    isAlreadyAMember: group.isAlreadyAMember,
                    subtitle: group.subtitle,
                ))
            }

            for section in sections where section.itemCount == 0 {
                section.headerTitle = nil
            }

            let contents = OWSTableContents(sections: sections)
            contents.sectionForSectionIndexTitleBlock = { [weak self] _, index in
                return self?.collation.section(forSectionIndexTitle: index) ?? 0
            }
            contents.sectionIndexTitlesForTableViewBlock = { [weak self] in
                return self?.collation.sectionIndexTitles ?? []
            }
            self.contents = contents
        }

    }

    // MARK: UISearchResultsUpdating

    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text?.stripped.nilIfEmpty
    }

    // MARK: Helpers

    private func didSelectGroup(_ groupThread: TSGroupThread) {
        let shortName = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return SSKEnvironment.shared.contactManagerRef.displayName(for: self.address, tx: transaction).resolvedValue(useShortNameIfAvailable: true)
        }

        let messageFormat = OWSLocalizedString(
            "ADD_TO_GROUP_ACTION_SHEET_MESSAGE_FORMAT",
            comment: "The title on the 'add to group' confirmation action sheet. Embeds {contact name, group name}",
        )

        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString(
                "ADD_TO_GROUP_ACTION_SHEET_TITLE",
                comment: "The title on the 'add to group' confirmation action sheet.",
            ),
            message: String.nonPluralLocalizedStringWithFormat(messageFormat, shortName, groupThread.groupNameOrDefault),
            proceedTitle: OWSLocalizedString(
                "ADD_TO_GROUP_ACTION_PROCEED_BUTTON",
                comment: "The button on the 'add to group' confirmation to add the user to the group.",
            ),
            proceedStyle: .default,
        ) { _ in
            self.addToGroup(groupThread, shortName: shortName)
        }
    }

    private func addToGroup(_ groupThread: TSGroupThread, shortName: String) {
        AssertIsOnMainThread()
        owsPrecondition(groupThread.isGroupV2Thread) // non-gv2 filtered above when fetching groups
        let oldGroupModel = groupThread.groupModel as! TSGroupModelV2

        guard let serviceId = self.address.serviceId else {
            GroupViewUtils.showInvalidGroupMemberAlert(fromViewController: self)
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            updateBlock: {
                try await GroupManager.addOrInvite(
                    secretParams: oldGroupModel.secretParams(),
                    serviceIds: [serviceId],
                )
            },
            completion: { [weak self] in
                self?.notifyOfAddedAndDismiss(groupThread: groupThread, shortName: shortName)
            },
        )
    }

    private func notifyOfAddedAndDismiss(groupThread: TSGroupThread, shortName: String) {
        dismiss(animated: true) { [presentingViewController] in
            let toastFormat = OWSLocalizedString(
                "ADD_TO_GROUP_SUCCESS_TOAST_FORMAT",
                comment: "A toast on the 'add to group' view indicating the user was added. Embeds {contact name} and {group name}",
            )
            let toastText = String.nonPluralLocalizedStringWithFormat(toastFormat, shortName, groupThread.groupNameOrDefault)
            presentingViewController?.presentToast(text: toastText)
        }
    }
}
