//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
public import SignalServiceKit
public import SignalUI

public class AddToGroupViewController: OWSTableViewController2 {

    private let address: SignalServiceAddress

    init(address: SignalServiceAddress) {
        self.address = address
        super.init()
    }

    public class func presentForUser(
        _ address: SignalServiceAddress,
        from fromViewController: UIViewController,
    ) {
        AssertIsOnMainThread()

        let view = AddToGroupViewController(address: address)
        let modal = OWSNavigationController(rootViewController: view)
        fromViewController.presentFormSheet(modal, animated: true)
    }

    // MARK: -

    override public func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("ADD_TO_GROUP_TITLE", comment: "Title of the 'add to group' view.")

        navigationItem.rightBarButtonItem = .cancelButton { [weak self] in
            self?.didPressCloseButton()
        }

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing

        Task {
            await self.updateGroupThreads()
        }
    }

    private var groupThreads = [TSGroupThread]() {
        didSet {
            AssertIsOnMainThread()
            updateTableContents()
        }
    }

    private func updateGroupThreads() async {
        self.groupThreads = await fetchGroupThreads()
    }

    private nonisolated func fetchGroupThreads() async -> [TSGroupThread] {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        return databaseStorage.read { transaction in
            var result = [TSGroupThread]()

            do {
                try ThreadFinder().enumerateGroupThreads(transaction: transaction) { thread -> Bool in
                    if thread.isGroupV2Thread {
                        let groupViewHelper = GroupViewHelper(
                            threadViewModel: ThreadViewModel(
                                thread: thread,
                                forChatList: false,
                                transaction: transaction,
                            ),
                        )

                        if groupViewHelper.canEditConversationMembership {
                            result.append(thread)
                        }
                    }

                    return true
                }
            } catch {
                owsFailDebug("Failed to fetch group threads: \(error). Returning an empty array")
            }

            return result
        }
    }

    private func updateTableContents() {
        AssertIsOnMainThread()
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let groupsSection = databaseStorage.read { tx in
            return OWSTableSection(items: groupThreads.map { item(forGroupThread: $0, tx: tx) })
        }
        self.contents = OWSTableContents(sections: [groupsSection])
    }

    // MARK: Helpers

    override public func themeDidChange() {
        super.themeDidChange()
        self.tableView.sectionIndexColor = Theme.primaryTextColor
        updateTableContents()
    }

    private func didPressCloseButton() {
        Logger.info("")

        self.dismiss(animated: true)
    }

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
            message: String(format: messageFormat, shortName, groupThread.groupNameOrDefault),
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

        guard let serviceId = self.address.serviceId else {
            GroupViewUtils.showInvalidGroupMemberAlert(fromViewController: self)
            return
        }

        let oldGroupModel = groupThread.groupModel

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            updateBlock: {
                try await GroupManager.addOrInvite(
                    serviceIds: [serviceId],
                    toExistingGroup: oldGroupModel,
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
            let toastText = String(format: toastFormat, shortName, groupThread.groupNameOrDefault)
            presentingViewController?.presentToast(text: toastText)
        }
    }

    // MARK: -

    private func item(forGroupThread groupThread: TSGroupThread, tx: DBReadTransaction) -> OWSTableItem {
        let alreadyAMemberText = OWSLocalizedString(
            "ADD_TO_GROUP_ALREADY_A_MEMBER",
            comment: "Text indicating your contact is already a member of the group on the 'add to group' view.",
        )
        let isAlreadyAMember: Bool
        if let serviceId = self.address.serviceId {
            switch groupThread.groupMembership.canTryToAddToGroup(serviceId: serviceId) {
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

        return OWSTableItem(
            customCellBlock: {
                let cell = GroupTableViewCell()
                cell.configure(
                    thread: groupThread,
                    customSubtitle: isAlreadyAMember ? alreadyAMemberText : nil,
                    customTextColor: isAlreadyAMember ? .Signal.tertiaryLabel : nil,
                )
                cell.isUserInteractionEnabled = !isAlreadyAMember
                return cell
            },
            actionBlock: { [weak self] in
                self?.didSelectGroup(groupThread)
            },
        )
    }
}
